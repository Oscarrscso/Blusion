import Foundation

/// IMDb, Rotten Tomatoes and Metacritic scores supplied by OMDb, when the user has provided an API key.
public struct OMDbRatings: Sendable {
    public static let defaultBaseURL = URL(string: "https://www.omdbapi.com/") ?? URL(fileURLWithPath: "/")
    private let client: AddonClient
    private let apiKey: String
    private let baseURL: URL

    public init(client: AddonClient, apiKey: String, baseURL: URL = OMDbRatings.defaultBaseURL) {
        self.client = client
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
    }

    public func ratings(imdbID: String) async throws -> ReviewRatings {
        guard LetterboxdRatings.isIMDbID(imdbID), !apiKey.isEmpty else { return ReviewRatings() }
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "apikey", value: apiKey), URLQueryItem(name: "i", value: imdbID)]
        guard let url = parts?.url else { throw AddonError.invalidURL }
        let result = try await client.get(url, limits: FetchLimits(maxBytes: 64 * 1024), timeout: 6)
        return try Self.parse(result.data)
    }

    public static func parse(_ data: Data) throws -> ReviewRatings {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw AddonError.invalidJSON }
        if response.Response == "False" {
            if response.Error == "Movie not found!" { return ReviewRatings() }
            // Invalid keys and exhausted quotas are failures, so they do not become cached "no rating" answers.
            throw AddonError.http(status: response.Error?.lowercased().contains("limit") == true ? 429 : 401)
        }
        guard response.Response == "True" else { throw AddonError.invalidJSON }
        let ratings = response.Ratings ?? []
        let imdb = score(response.imdbRating, scale: 10)
            ?? score(ratings.first { $0.Source == "Internet Movie Database" }?.Value, scale: 10, suffix: "/10")
        let tomatoes = score(ratings.first { $0.Source == "Rotten Tomatoes" }?.Value, scale: 100, suffix: "%")
        let metascore = score(response.Metascore, scale: 100)
            ?? score(ratings.first { $0.Source == "Metacritic" }?.Value, scale: 100, suffix: "/100")
        return ReviewRatings(imdb: imdb, rottenTomatoes: tomatoes, metacritic: metascore)
    }

    private static func score(_ raw: String?, scale: Double, suffix: String = "") -> Double? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if !suffix.isEmpty {
            guard text.hasSuffix(suffix) else { return nil }
            text.removeLast(suffix.count)
        }
        guard let value = Double(text), value.isFinite, (0...scale).contains(value) else { return nil }
        return value
    }

    private struct Response: Decodable {
        let Response: String?
        let Error: String?
        let imdbRating: String?
        let Metascore: String?
        let Ratings: [Rating]?
    }
    private struct Rating: Decodable { let Source: String; let Value: String }
}
