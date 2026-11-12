import Foundation

/// MyAnimeList's score and page for an anime, from the site's own search (the JSON its search box reads). It needs no account.
public struct MyAnimeListRatings: Sendable {
    /// `https://myanimelist.net`. The literal always parses; the fallback only avoids a force unwrap.
    public static let defaultBaseURL = URL(string: "https://myanimelist.net") ?? URL(fileURLWithPath: "/")

    private let client: AddonClient
    private let baseURL: URL

    public init(client: AddonClient, baseURL: URL = MyAnimeListRatings.defaultBaseURL) {
        self.client = client
        self.baseURL = baseURL
    }

    /// The title's MyAnimeList score (out of 10) and page, or empty when the search finds no match. Throws `AddonError` when the request
    /// fails.
    public func ratings(for item: MetaPreview) async throws -> ReviewRatings {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return ReviewRatings() }
        var parts = URLComponents(url: baseURL.appendingPathComponent("search/prefix.json"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "type", value: "anime"), URLQueryItem(name: "keyword", value: String(name.prefix(100))),
                             URLQueryItem(name: "v", value: "1")]
        guard let url = parts?.url else { throw AddonError.invalidURL }
        let result = try await client.get(url, headers: ["Accept": "application/json"], limits: FetchLimits(maxBytes: 256 * 1024), timeout: 6)
        return try Self.parse(result.data, for: item)
    }

    /// The best match in a search answer: the first of the title's kind (a film is a "Movie", a series is on TV or the web) from its first
    /// year, else the first of its kind, else the first. Throws `invalidJSON` for an answer that is not a search result.
    public static func parse(_ data: Data, for item: MetaPreview) throws -> ReviewRatings {
        let response: SearchResponse
        do { response = try JSONDecoder().decode(SearchResponse.self, from: data) } catch { throw AddonError.invalidJSON }
        let items = response.categories.filter { $0.type == "anime" }.flatMap(\.items)
        let kinds: Set<String>? = switch item.type {
        case "movie": ["movie"]
        case "series": ["tv", "ona"]
        default: nil
        }
        let year = item.releaseInfo?.firstMatch(of: /[0-9]{4}/).flatMap { Int($0.output) }
        let ofKind = items.filter { kinds?.contains(($0.payload?.media_type ?? "").lowercased()) ?? true }
        guard let match = ofKind.first(where: { year != nil && $0.payload?.start_year == year }) ?? ofKind.first ?? (kinds == nil ? items.first : nil),
              let page = URL(string: match.url), page.host?.hasSuffix("myanimelist.net") == true else { return ReviewRatings() }
        let score = match.payload?.score.flatMap(Double.init).flatMap { (0.01...10).contains($0) ? $0 : nil }
        return ReviewRatings(myAnimeList: score, myAnimeListURL: page)
    }

    private struct SearchResponse: Decodable { let categories: [Category] }
    private struct Category: Decodable { let type: String; let items: [Item] }
    private struct Item: Decodable { let url: String; let payload: Payload? }
    private struct Payload: Decodable {
        let media_type: String?
        let start_year: Int?
        let score: String?
    }
}
