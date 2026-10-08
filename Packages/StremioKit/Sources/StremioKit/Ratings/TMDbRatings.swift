import Foundation

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

    private struct Response: Decodable { let movie_results: [Match]?; let tv_results: [Match]? }
    private struct Match: Decodable { let id: Int; let vote_average: Double?; let vote_count: Int? }
}
