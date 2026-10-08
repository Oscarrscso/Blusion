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

    /// IMDb scores of one season's episodes, by episode number. Empty when OMDb does not know the season or has no scores in it.
    /// Cinemeta sends `"0"` for the episodes of most shows, so this is where per-episode IMDb scores come from.
    public func episodeRatings(imdbID: String, season: Int) async throws -> [Int: Double] {
        guard LetterboxdRatings.isIMDbID(imdbID), season >= 0, !apiKey.isEmpty else { return [:] }
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "apikey", value: apiKey), URLQueryItem(name: "i", value: imdbID),
                             URLQueryItem(name: "Season", value: String(season))]
        guard let url = parts?.url else { throw AddonError.invalidURL }
        let result = try await client.get(url, limits: FetchLimits(maxBytes: 256 * 1024), timeout: 8)
        return try Self.parseSeason(result.data)
    }

    /// `Episodes` of a season answer, as episode number to score. Episodes without a score (`"N/A"`) are left out.
    public static func parseSeason(_ data: Data) throws -> [Int: Double] {
        let response: SeasonResponse
        do { response = try JSONDecoder().decode(SeasonResponse.self, from: data) } catch { throw AddonError.invalidJSON }
        if response.Response == "False" {
            if isMissingTitle(response.Error) { return [:] }
            throw failure(for: response.Error)
        }
        guard response.Response == "True" else { throw AddonError.invalidJSON }
        var scores: [Int: Double] = [:]
        for episode in response.Episodes ?? [] {
            guard let number = episode.Episode.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), number >= 0,
                  let value = score(episode.imdbRating, scale: 10), value > 0 else { continue }
            scores[number] = value
        }
        return scores
    }

    public static func parse(_ data: Data) throws -> ReviewRatings {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw AddonError.invalidJSON }
        if response.Response == "False" {
            if isMissingTitle(response.Error) { return ReviewRatings() }
            throw failure(for: response.Error)
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

    /// "Movie not found!", "Series or season not found!" and "Incorrect IMDb ID." mean OMDb has no such title: a real answer.
    private static func isMissingTitle(_ error: String?) -> Bool {
        guard let error = error?.lowercased() else { return false }
        return error.contains("not found") || error.contains("incorrect imdb id")
    }

    /// Invalid keys and exhausted quotas are failures, so they do not become cached "no rating" answers.
    private static func failure(for error: String?) -> AddonError {
        .http(status: error?.lowercased().contains("limit") == true ? 429 : 401)
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

    private struct SeasonResponse: Decodable {
        let Response: String?
        let Error: String?
        let Episodes: [SeasonEpisode]?
    }
    private struct SeasonEpisode: Decodable {
        let Episode: String?
        let imdbRating: String?
    }
}
