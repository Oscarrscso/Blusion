import Foundation

/// The Trakt feeds a row can show. Each is public: it needs the client ID and no account.
public enum TraktFeed: String, Sendable, Codable, CaseIterable, Hashable {
    case moviesTrending, moviesPopular, showsTrending, showsPopular

    /// The name shown on a row and in its source summary.
    public var title: String {
        switch self {
        case .moviesTrending: return "Trending Movies"
        case .moviesPopular: return "Popular Movies"
        case .showsTrending: return "Trending Shows"
        case .showsPopular: return "Popular Shows"
        }
    }

    /// The API path, e.g. `movies/trending`.
    var path: String {
        switch self {
        case .moviesTrending: return "movies/trending"
        case .moviesPopular: return "movies/popular"
        case .showsTrending: return "shows/trending"
        case .showsPopular: return "shows/popular"
        }
    }

    /// The type the items carry: `movie`, or `series` for shows (as Stremio names them).
    var mediaType: String {
        switch self {
        case .moviesTrending, .moviesPopular: return "movie"
        case .showsTrending, .showsPopular: return "series"
        }
    }
}

/// Reads public Trakt lists as catalog items. The Trakt API key is the client ID the user supplies in Settings; the app ships none.
public struct TraktClient: Sendable {
    /// `https://api.trakt.tv`. Built from components, so there is no force unwrap; the fallback is never used in practice.
    public static let defaultBaseURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.trakt.tv"
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    private static let pathCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private let client: AddonClient
    private let baseURL: URL

    public init(client: AddonClient, baseURL: URL = TraktClient.defaultBaseURL) {
        self.client = client
        self.baseURL = baseURL
    }

    /// One page of a public list. Movies map to type `movie`, shows to `series`; other entries, and entries without an IMDb id, are dropped.
    public func listItems(_ list: TraktListReference, clientID: String, page: Int = 1, limit: Int = 50) async throws -> [MetaPreview] {
        guard let user = Self.segment(list.username), let slug = Self.segment(list.listSlug),
              let url = apiURL("users/\(user)/lists/\(slug)/items", page: page, limit: limit) else { throw AddonError.invalidURL }
        let result = try await client.get(url, headers: Self.headers(clientID))
        return try Self.previews(from: result.data)
    }

    /// One page of a Trakt feed. Trending entries are wrapped with a watcher count; popular entries are the media themselves.
    public func feedItems(_ feed: TraktFeed, clientID: String, page: Int = 1, limit: Int = 50) async throws -> [MetaPreview] {
        guard let url = apiURL(feed.path, page: page, limit: limit) else { throw AddonError.invalidURL }
        let result = try await client.get(url, headers: Self.headers(clientID))
        return try Self.feedPreviews(from: result.data, feed: feed)
    }

    /// The name and Trakt id of a public list, for a list added by link. The name falls back to the slug when Trakt omits it.
    public func listInfo(username: String, listSlug: String, clientID: String) async throws -> (name: String, traktID: Int?) {
        guard let user = Self.segment(username), let slug = Self.segment(listSlug),
              let url = apiURL("users/\(user)/lists/\(slug)", page: 1, limit: 1, paged: false) else { throw AddonError.invalidURL }
        let result = try await client.get(url, headers: Self.headers(clientID))
        do {
            let info = try JSONDecoder().decode(TraktListInfo.self, from: result.data)
            return (info.name ?? listSlug, info.ids?.trakt)
        } catch {
            throw AddonError.invalidJSON
        }
    }

    /// The owner and slug of a `trakt.tv/users/<user>/lists/<slug>` link. A link without a scheme is accepted. nil when the text is not a list link.
    public static func listReference(fromLink text: String) -> (username: String, listSlug: String)? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased(), host == "trakt.tv" || host.hasSuffix(".trakt.tv") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[0] == "users", parts[2] == "lists", !parts[1].isEmpty, !parts[3].isEmpty else { return nil }
        return (parts[1], parts[3])
    }

    /// `base/<path>?page=…&limit=…&extended=full`. Lists keep their page and limit; a feed's `paged` is false only for a single object.
    private func apiURL(_ path: String, page: Int, limit: Int, paged: Bool = true) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let query = paged ? "?page=\(max(page, 1))&limit=\(min(max(limit, 1), 100))&extended=full" : "?extended=full"
        return URL(string: "\(base)/\(path)\(query)")
    }

    private static func headers(_ clientID: String) -> [String: String] {
        ["trakt-api-version": "2", "trakt-api-key": clientID, "Content-Type": "application/json"]
    }

    private static func segment(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: pathCharacters)
    }

    /// The response must be an array; a bad element is dropped rather than failing the page.
    private static func previews(from data: Data) throws -> [MetaPreview] {
        do {
            return try JSONDecoder().decode([LossyEntry].self, from: data).compactMap(\.preview)
        } catch {
            throw AddonError.invalidJSON
        }
    }

    private static func feedPreviews(from data: Data, feed: TraktFeed) throws -> [MetaPreview] {
        do {
            return try JSONDecoder().decode([LossyFeedEntry].self, from: data).compactMap { $0.preview(for: feed) }
        } catch {
            throw AddonError.invalidJSON
        }
    }
}

/// The public list endpoint: a name and the list's ids. Only the trakt id is kept.
private struct TraktListInfo: Decodable {
    let name: String?
    let ids: Ids?

    struct Ids: Decodable { let trakt: Int? }
}

/// A feed entry, either wrapped (`{"watchers": 3, "movie": {…}}`) or the media itself. One that fails to decode becomes nil.
private struct LossyFeedEntry: Decodable {
    let wrapped: TraktMedia?
    let bare: TraktMedia?

    private enum Keys: String, CodingKey { case movie, show }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        wrapped = container.object(.movie) ?? container.object(.show)
        bare = try? TraktMedia(from: decoder)
    }

    func preview(for feed: TraktFeed) -> MetaPreview? {
        let media = wrapped ?? bare
        return media?.preview(type: feed.mediaType)
    }
}

/// Wraps an entry so that one that fails to decode becomes nil instead of failing the whole array.
private struct LossyEntry: Decodable {
    let preview: MetaPreview?

    init(from decoder: Decoder) throws {
        preview = try? TraktEntry(from: decoder).preview
    }
}

private struct TraktEntry: Decodable {
    let type: String?
    let movie: TraktMedia?
    let show: TraktMedia?

    private enum Keys: String, CodingKey { case type, movie, show }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        type = container.string(.type)
        movie = container.object(.movie)
        show = container.object(.show)
    }

    var preview: MetaPreview? {
        switch type {
        case "movie": return movie?.preview(type: "movie")
        case "show": return show?.preview(type: "series")
        default: return nil
        }
    }
}

private struct TraktMedia: Decodable {
    let title: String?
    let year: String?
    let imdbID: String?
    let overview: String?
    let rating: Double?
    let runtime: Int?
    let genres: [String]

    private enum Keys: String, CodingKey { case title, year, ids, overview, rating, runtime, genres }
    private enum IDKeys: String, CodingKey { case imdb }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        title = container.string(.title)
        year = container.string(.year)
        if container.contains(.ids), let ids = try? container.nestedContainer(keyedBy: IDKeys.self, forKey: .ids) {
            imdbID = ids.string(.imdb)
        } else {
            imdbID = nil
        }
        overview = container.string(.overview)
        rating = container.double(.rating)
        runtime = container.int(.runtime)
        genres = container.stringArray(.genres)
    }

    func preview(type: String) -> MetaPreview? {
        guard let imdbID else { return nil }
        return MetaPreview(id: imdbID, type: type, name: title,
                           poster: MetahubArtwork.poster(imdbID: imdbID),
                           background: MetahubArtwork.background(imdbID: imdbID),
                           logo: MetahubArtwork.logo(imdbID: imdbID),
                           description: overview,
                           releaseInfo: year,
                           imdbRating: rating.map { ($0 * 10).rounded() / 10 },
                           genres: genres.map(Self.genreLabel),
                           runtime: runtime.flatMap { $0 > 0 ? "\($0) min" : nil })
    }

    /// Trakt slugs read `science-fiction`; catalogs read `Science fiction`.
    private static func genreLabel(_ slug: String) -> String {
        let spaced = slug.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

/// Artwork Stremio's metadata service publishes for an IMDb id.
public enum MetahubArtwork {
    private static let idCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    public static func poster(imdbID: String) -> URL? { artwork("poster", imdbID: imdbID) }

    public static func background(imdbID: String) -> URL? { artwork("background", imdbID: imdbID) }

    public static func logo(imdbID: String) -> URL? { artwork("logo", imdbID: imdbID) }

    private static func artwork(_ kind: String, imdbID: String) -> URL? {
        guard !imdbID.isEmpty, imdbID.unicodeScalars.allSatisfy({ idCharacters.contains($0) }) else { return nil }
        return URL(string: "https://images.metahub.space/\(kind)/medium/\(imdbID)/img")
    }
}
