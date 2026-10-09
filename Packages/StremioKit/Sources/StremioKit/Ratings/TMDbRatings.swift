import Foundation

public struct TMDbArtwork: Sendable, Hashable {
    public let backdrop: URL?
    public let portrait: URL?
    public let logo: URL?
}

public struct TMDbReview: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let author: String
    public let content: String
    public let url: URL?
    private let author_details: AuthorDetails?

    public var rating: Double? {
        guard let rating = author_details?.rating, rating.isFinite, (0...10).contains(rating) else { return nil }
        return rating
    }

    private struct AuthorDetails: Decodable, Sendable, Equatable { let rating: Double? }
}

/// The TMDb id of each IMDb title, kept for the session. Artwork, reviews and cast all need it and a title's id never changes, so one
/// lookup serves them all. Callers that ask at the same time share one lookup. Unknown titles are not kept, so they are asked again.
public actor TMDbTitleIDCache {
    public static let shared = TMDbTitleIDCache()

    private var ids: [String: Int] = [:]
    private var lookups: [String: Task<Int?, Error>] = [:]

    public init() {}

    func id(for key: String, lookup: @escaping @Sendable () async throws -> Int?) async throws -> Int? {
        if let id = ids[key] { return id }
        if let pending = lookups[key] { return try await pending.value }
        let task = Task { try await lookup() }
        lookups[key] = task
        defer { lookups[key] = nil }
        let id = try await task.value
        if let id { ids[key] = id }
        return id
    }
}

/// Resolves an IMDb ID to the matching movie or show, its community score and its direct TMDB page.
public struct TMDbRatings: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.themoviedb.org/3/") ?? URL(fileURLWithPath: "/")
    let client: AddonClient
    let credential: Credential?
    private let baseURL: URL
    let titleIDs: TMDbTitleIDCache

    /// The credential as TMDb expects it. `nil` for an empty token: no request is sent.
    enum Credential: Sendable, Equatable {
        case bearer(String)
        case apiKey(String)
    }

    public init(client: AddonClient, readAccessToken: String, baseURL: URL = TMDbRatings.defaultBaseURL,
                titleIDs: TMDbTitleIDCache = .shared) {
        self.client = client
        self.credential = Self.credential(for: readAccessToken)
        self.baseURL = baseURL
        self.titleIDs = titleIDs
    }

    /// Trims the text, drops a pasted `Bearer ` prefix, and picks the header for a JWT or the query for anything else.
    static func credential(for raw: String) -> Credential? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") { token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        guard !token.isEmpty else { return nil }
        return looksLikeJWT(token) ? .bearer(token) : .apiKey(token)
    }

    /// v4 Read Access Tokens are JWTs: base64 of `{"` is `eyJ`.
    static func looksLikeJWT(_ token: String) -> Bool { token.hasPrefix("eyJ") }

    /// Movie or series ratings for an IMDb id. Empty when the id, the type or the credential is unusable; throws `AddonError` when
    /// TMDb refuses the request (a 401 for a bad token, 429 for the rate limit), so the caller can say why nothing shows.
    public func ratings(imdbID: String, type: String) async throws -> ReviewRatings {
        guard LetterboxdRatings.isIMDbID(imdbID), ["movie", "series"].contains(type), credential != nil else { return ReviewRatings() }
        let data = try await findData(imdbID: imdbID)
        return try Self.parse(data, type: type)
    }

    /// Per-episode TMDb scores for one season, keyed by episode number. Empty when the series is unknown to TMDb, the season does
    /// not exist, or no episode has votes. Throws `AddonError` for refusals and transport failures.
    public func seasonEpisodeRatings(seriesIMDbID: String, season: Int) async throws -> [Int: Double] {
        guard LetterboxdRatings.isIMDbID(seriesIMDbID), season >= 0, credential != nil else { return [:] }
        let find = try await findData(imdbID: seriesIMDbID)
        guard let show = try Self.parseFind(find).tv_results?.first, show.id > 0 else { return [:] }
        let (url, headers) = try request(path: ["tv", String(show.id), "season", String(season)])
        do {
            let result = try await client.get(url, headers: headers, limits: FetchLimits(maxBytes: 512 * 1024), timeout: 6)
            return try Self.parseSeason(result.data)
        } catch AddonError.notFound {
            return [:]
        }
    }

    /// The `movie` or `tv` answer for `type`. Throws `invalidJSON` when the response has no result lists at all.
    public static func parse(_ data: Data, type: String) throws -> ReviewRatings {
        guard ["movie", "series"].contains(type) else { return ReviewRatings() }
        let response = try parseFind(data)
        let matches = type == "movie" ? response.movie_results : response.tv_results
        guard let matches else { throw AddonError.invalidJSON }
        guard let match = matches.first, match.id > 0 else { return ReviewRatings() }
        let rating: Double?
        if let average = match.vote_average, average.isFinite, (0...10).contains(average), (match.vote_count ?? 0) > 0 {
            rating = average
        } else { rating = nil }
        return ReviewRatings(tmdb: rating, tmdbURL: URL(string: "https://www.themoviedb.org/\(type == "movie" ? "movie" : "tv")/\(match.id)"))
    }

    /// The TMDb id for an IMDb title, looked up once per session (see `TMDbTitleIDCache`). Nil when TMDb does not know the title.
    func tmdbID(imdbID: String, type: String) async throws -> Int? {
        try await titleIDs.id(for: "\(type)|\(imdbID)") {
            let resolved = try await self.ratings(imdbID: imdbID, type: type)
            guard let id = resolved.tmdbURL?.lastPathComponent else { return nil }
            return Int(id)
        }
    }

    /// The backdrop is the best one `BackdropPicker` finds (textless first, then the highest rated). The poster and logo keep the most-voted pick.
    public func artwork(imdbID: String, type: String) async throws -> TMDbArtwork? {
        guard let number = try await tmdbID(imdbID: imdbID, type: type) else { return nil }
        let id = String(number)
        let (url, headers) = try request(path: [type == "movie" ? "movie" : "tv", id, "images"],
                                         query: [URLQueryItem(name: "include_image_language", value: "en,null")])
        let result = try await client.get(url, headers: headers,
                                          limits: FetchLimits(maxBytes: 1024 * 1024), timeout: 6)
        let images: Images
        do { images = try JSONDecoder().decode(Images.self, from: result.data) } catch { throw AddonError.invalidJSON }
        let logos = images.logos ?? []
        let english = logos.filter { $0.iso_639_1 == "en" }
        let portraits = images.posters ?? []
        let textless = portraits.filter { $0.iso_639_1 == nil }
        return TMDbArtwork(backdrop: BackdropPicker.best(Self.backdropCandidates(images.backdrops ?? [])),
                           portrait: Self.popular(textless.isEmpty ? portraits : textless)?.url(size: "original"),
                           logo: Self.popular(english.isEmpty ? logos : english)?.url(size: "original"))
    }

    public func reviews(imdbID: String, type: String) async throws -> [TMDbReview] {
        guard let number = try await tmdbID(imdbID: imdbID, type: type) else { return [] }
        let id = String(number)
        let (url, headers) = try request(path: [type == "movie" ? "movie" : "tv", id, "reviews"],
                                         query: [URLQueryItem(name: "language", value: "en-US")])
        let result = try await client.get(url, headers: headers,
                                          limits: FetchLimits(maxBytes: 1024 * 1024), timeout: 6)
        let response: ReviewsResponse
        do { response = try JSONDecoder().decode(ReviewsResponse.self, from: result.data) } catch { throw AddonError.invalidJSON }
        return response.results.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private struct ReviewsResponse: Decodable { let results: [TMDbReview] }

    /// The US age rating: a film's certificate ("R") from its release dates, or a show's content rating ("TV-MA"). Nil when TMDb
    /// has none for the US.
    public func certification(imdbID: String, type: String) async throws -> String? {
        guard let number = try await tmdbID(imdbID: imdbID, type: type) else { return nil }
        let isMovie = type == "movie"
        let (url, headers) = try request(path: [isMovie ? "movie" : "tv", String(number), isMovie ? "release_dates" : "content_ratings"])
        let result = try await client.get(url, headers: headers, limits: FetchLimits(maxBytes: 1024 * 1024), timeout: 6)
        return try Self.parseCertification(result.data, isMovie: isMovie)
    }

    /// The `release_dates` answer for a movie or the `content_ratings` answer for a show, read for the US only.
    static func parseCertification(_ data: Data, isMovie: Bool) throws -> String? {
        let response: CertificationResponse
        do { response = try JSONDecoder().decode(CertificationResponse.self, from: data) } catch { throw AddonError.invalidJSON }
        guard let region = response.results?.first(where: { $0.iso_3166_1 == "US" }) else { return nil }
        let value: String?
        if isMovie {
            value = region.release_dates?.compactMap(\.certification).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            value = region.rating
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private struct CertificationResponse: Decodable {
        let results: [Region]?
        struct Region: Decodable {
            let iso_3166_1: String
            let rating: String?
            let release_dates: [Release]?
        }
        struct Release: Decodable { let certification: String? }
    }

    private static func popular(_ images: [Image]) -> Image? {
        images.filter { $0.file_path.hasPrefix("/") }.max {
            if $0.vote_count != $1.vote_count { return ($0.vote_count ?? 0) < ($1.vote_count ?? 0) }
            if $0.vote_average != $1.vote_average { return ($0.vote_average ?? 0) < ($1.vote_average ?? 0) }
            return ($0.width ?? 0) < ($1.width ?? 0)
        }
    }

    /// The backdrops with a usable path, in the form `BackdropPicker` ranks.
    private static func backdropCandidates(_ images: [Image]) -> [BackdropCandidate] {
        images.compactMap { image -> BackdropCandidate? in
            guard image.file_path.hasPrefix("/"), let url = image.url(size: "original") else { return nil }
            return BackdropCandidate(url: url, language: image.iso_639_1, voteAverage: image.vote_average,
                                     voteCount: image.vote_count, width: image.width)
        }
    }

    private struct Images: Decodable { let backdrops: [Image]?; let posters: [Image]?; let logos: [Image]? }
    private struct Image: Decodable {
        let file_path: String
        let iso_639_1: String?
        let vote_count: Int?
        let vote_average: Double?
        let width: Int?
        func url(size: String) -> URL? { URL(string: "https://image.tmdb.org/t/p/\(size)\(file_path)") }
    }

    /// Episode number to score, for episodes with votes and a score in 0...10.
    public static func parseSeason(_ data: Data) throws -> [Int: Double] {
        let response: SeasonResponse
        do { response = try JSONDecoder().decode(SeasonResponse.self, from: data) } catch { throw AddonError.invalidJSON }
        guard let episodes = response.episodes else { throw AddonError.invalidJSON }
        var scores: [Int: Double] = [:]
        for episode in episodes {
            guard let number = episode.episode_number, let average = episode.vote_average, average.isFinite,
                  (0...10).contains(average), (episode.vote_count ?? 0) > 0 else { continue }
            scores[number] = average
        }
        return scores
    }

    static func parseFind(_ data: Data) throws -> FindResponse {
        do { return try JSONDecoder().decode(FindResponse.self, from: data) } catch { throw AddonError.invalidJSON }
    }

    private func findData(imdbID: String) async throws -> Data {
        let (url, headers) = try request(path: ["find", imdbID], query: [URLQueryItem(name: "external_source", value: "imdb_id")])
        let result = try await client.get(url, headers: headers, limits: FetchLimits(maxBytes: 256 * 1024), timeout: 6)
        return result.data
    }

    /// The URL and headers for a path under `baseURL`. The credential goes in the header or the query, never in the path.
    func request(path: [String], query: [URLQueryItem] = []) throws -> (URL, [String: String]) {
        var url = baseURL
        for component in path { url = url.appendingPathComponent(component) }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw AddonError.invalidURL }
        var items = query
        var headers: [String: String] = [:]
        switch credential {
        case .bearer(let token): headers["Authorization"] = "Bearer \(token)"
        case .apiKey(let key): items.append(URLQueryItem(name: "api_key", value: key))
        case nil: break
        }
        parts.queryItems = items.isEmpty ? nil : items
        guard let result = parts.url else { throw AddonError.invalidURL }
        return (result, headers)
    }

    struct FindResponse: Decodable {
        let movie_results: [Match]?
        let tv_results: [Match]?
    }
    struct Match: Decodable { let id: Int; let vote_average: Double?; let vote_count: Int? }

    private struct SeasonResponse: Decodable { let episodes: [Episode]? }
    private struct Episode: Decodable { let episode_number: Int?; let vote_average: Double?; let vote_count: Int? }
}
