import Foundation

public struct TMDbArtwork: Sendable, Equatable {
    public let backdrop: URL?
    public let portrait: URL?
    public let logo: URL?
}

/// Resolves an IMDb ID to the matching movie or show, its community score and its direct TMDB page.
public struct TMDbRatings: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.themoviedb.org/3/") ?? URL(fileURLWithPath: "/")
    private let client: AddonClient
    private let readAccessToken: String
    private let baseURL: URL

    public init(client: AddonClient, readAccessToken: String, baseURL: URL = TMDbRatings.defaultBaseURL) {
        self.client = client
        self.readAccessToken = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
    }

    public func ratings(imdbID: String, type: String) async throws -> ReviewRatings {
        guard LetterboxdRatings.isIMDbID(imdbID), ["movie", "series"].contains(type), !readAccessToken.isEmpty else { return ReviewRatings() }
        var parts = URLComponents(url: baseURL.appendingPathComponent("find").appendingPathComponent(imdbID), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "external_source", value: "imdb_id")]
        guard let url = parts?.url else { throw AddonError.invalidURL }
        let result = try await client.get(url, headers: ["Authorization": "Bearer \(readAccessToken)"],
                                          limits: FetchLimits(maxBytes: 256 * 1024), timeout: 6)
        return try Self.parse(result.data, type: type)
    }

    public static func parse(_ data: Data, type: String) throws -> ReviewRatings {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw AddonError.invalidJSON }
        guard ["movie", "series"].contains(type) else { return ReviewRatings() }
        let matches = type == "movie" ? response.movie_results : response.tv_results
        guard let matches else { throw AddonError.invalidJSON }
        guard let match = matches.first, match.id > 0 else { return ReviewRatings() }
        let rating: Double?
        if let average = match.vote_average, average.isFinite, (0...10).contains(average), (match.vote_count ?? 0) > 0 {
            rating = average
        } else { rating = nil }
        return ReviewRatings(tmdb: rating, tmdbURL: URL(string: "https://www.themoviedb.org/\(type == "movie" ? "movie" : "tv")/\(match.id)"))
    }

    /// Uses the most-voted backdrop and English logo, with rating and image width breaking ties.
    public func artwork(imdbID: String, type: String) async throws -> TMDbArtwork? {
        let resolved = try await ratings(imdbID: imdbID, type: type)
        guard let id = resolved.tmdbURL?.lastPathComponent, Int(id) != nil else { return nil }
        let path = "\(type == "movie" ? "movie" : "tv")/\(id)/images"
        var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "include_image_language", value: "en,null")]
        guard let url = parts?.url else { throw AddonError.invalidURL }
        let result = try await client.get(url, headers: ["Authorization": "Bearer \(readAccessToken)"],
                                          limits: FetchLimits(maxBytes: 1024 * 1024), timeout: 6)
        let images: Images
        do { images = try JSONDecoder().decode(Images.self, from: result.data) } catch { throw AddonError.invalidJSON }
        let logos = images.logos ?? []
        let english = logos.filter { $0.iso_639_1 == "en" }
        let portraits = images.posters ?? []
        let textless = portraits.filter { $0.iso_639_1 == nil }
        return TMDbArtwork(backdrop: Self.popular(images.backdrops ?? [])?.url(size: "w1280"),
                           portrait: Self.popular(textless.isEmpty ? portraits : textless)?.url(size: "w780"),
                           logo: Self.popular(english.isEmpty ? logos : english)?.url(size: "original"))
    }

    private static func popular(_ images: [Image]) -> Image? {
        images.filter { $0.file_path.hasPrefix("/") }.max {
            if $0.vote_count != $1.vote_count { return ($0.vote_count ?? 0) < ($1.vote_count ?? 0) }
            if $0.vote_average != $1.vote_average { return ($0.vote_average ?? 0) < ($1.vote_average ?? 0) }
            return ($0.width ?? 0) < ($1.width ?? 0)
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

    private struct Response: Decodable { let movie_results: [Match]?; let tv_results: [Match]? }
    private struct Match: Decodable { let id: Int; let vote_average: Double?; let vote_count: Int? }
}
