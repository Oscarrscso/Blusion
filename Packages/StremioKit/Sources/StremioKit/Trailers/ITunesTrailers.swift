import Foundation

/// The session's iTunes answers by title, including the titles the store has no preview for, so reopening a title does not search
/// again. Callers that ask at the same time share one search. A failed search is not kept, so it is asked again.
public actor ITunesTrailerCache {
    public static let shared = ITunesTrailerCache()

    /// `nil` is a kept answer too: the store has no preview for that title.
    private var answers: [String: Trailer?] = [:]
    private var lookups: [String: Task<Trailer?, Error>] = [:]

    public init() {}

    func trailer(for key: String, lookup: @escaping @Sendable () async throws -> Trailer?) async throws -> Trailer? {
        if let answer = answers[key] { return answer }
        if let pending = lookups[key] { return try await pending.value }
        let task = Task { try await lookup() }
        lookups[key] = task
        defer { lookups[key] = nil }
        let answer = try await task.value
        answers[key] = .some(answer)
        return answer
    }
}

/// A movie's or series' preview from Apple's iTunes store: the short clip the store publishes for a film, or for a season of a show. The
/// clip is a direct file, so it plays in the app. The store answers per country, so the search is for Ireland.
public struct ITunesTrailers: Sendable {
    let client: AddonClient
    let cache: ITunesTrailerCache

    public init(client: AddonClient, cache: ITunesTrailerCache = .shared) {
        self.client = client
        self.cache = cache
    }

    /// The preview of a movie (`type` "movie") or series (`type` "series") titled `title`, released in `year` when that is known. Nil
    /// when the store has none, or for another type. Throws `AddonError` when the search fails.
    public func preview(title: String, year: Int?, type: String) async throws -> Trailer? {
        guard !Self.normalized(title).isEmpty, let url = Self.searchURL(title: title, type: type) else { return nil }
        let key = "\(type)|\(Self.normalized(title))|\(year.map(String.init) ?? "")"
        let client = client
        return try await cache.trailer(for: key) {
            let result = try await client.get(url, limits: FetchLimits(maxBytes: 256 * 1024), timeout: 6)
            return try Self.parse(result.data, title: title, year: year, type: type)
        }
    }

    /// The store search for a movie or a series' seasons. Built with `URLComponents`, so the title is encoded as a query value.
    static func searchURL(title: String, type: String) -> URL? {
        let media: (media: String, entity: String)
        switch type {
        case "movie": media = ("movie", "movie")
        case "series": media = ("tvShow", "tvSeason")
        default: return nil
        }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "media", value: media.media),
            URLQueryItem(name: "entity", value: media.entity),
            URLQueryItem(name: "country", value: "ie"),
        ]
        return components?.url
    }

    /// The first result whose name matches `title` and whose preview is an https file. A movie takes the first match; a series takes the
    /// match for its lowest season. A known `year` must match the release year within one year. Throws `invalidJSON` when the answer has no
    /// `results` list.
    public static func parse(_ data: Data, title: String, year: Int?, type: String) throws -> Trailer? {
        let response: SearchResponse
        do { response = try JSONDecoder().decode(SearchResponse.self, from: data) } catch { throw AddonError.invalidJSON }
        guard ["movie", "series"].contains(type) else { return nil }
        let wanted = normalized(title)
        guard !wanted.isEmpty else { return nil }
        var best: (url: URL, season: Int)?
        for result in response.results {
            guard let text = result.previewUrl, let url = URL(string: text), url.scheme?.lowercased() == "https" else { continue }
            let name: String?
            var season = Int.max
            if type == "series" {
                let parts = seasonParts(result.collectionName ?? "")
                name = parts.name
                season = parts.number ?? Int.max
            } else {
                name = result.trackName
            }
            guard let name, normalized(name) == wanted else { continue }
            if let year {
                guard let released = result.releaseDate.flatMap({ Int($0.prefix(4)) }), abs(released - year) <= 1 else { continue }
            }
            if best == nil || season < best!.season { best = (url, season) }
            if type == "movie" { break }
        }
        return best.map { Trailer(source: .direct($0.url), title: "Trailer", kind: .trailer, isOfficial: true, language: nil) }
    }

    /// A season's collection name without its season suffix ("Show, Season 2" gives "Show" and 2).
    private static func seasonParts(_ collection: String) -> (name: String, number: Int?) {
        guard let suffix = collection.range(of: #"\s*[,\-–:]?\s*Season\s+\d+\s*$"#, options: [.regularExpression, .caseInsensitive]) else {
            return (collection, nil)
        }
        let number = collection[suffix].range(of: #"\d+$"#, options: .regularExpression).flatMap { Int(collection[suffix][$0]) }
        return (String(collection[..<suffix.lowerBound]), number)
    }

    /// Case, accents and punctuation (and spaces) removed, so "Amélie" and "AMELIE!" are the same name.
    static func normalized(_ text: String) -> String {
        var out = ""
        for scalar in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).unicodeScalars
        where CharacterSet.alphanumerics.contains(scalar) {
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    private struct SearchResponse: Decodable { let results: [Result] }
    private struct Result: Decodable {
        let trackName: String?
        let collectionName: String?
        let previewUrl: String?
        let releaseDate: String?
    }
}
