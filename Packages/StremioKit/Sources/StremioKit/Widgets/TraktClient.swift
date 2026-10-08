import Foundation

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
        guard let url = listURL(list, page: page, limit: limit) else { throw AddonError.invalidURL }
        let headers = ["trakt-api-version": "2", "trakt-api-key": clientID, "Content-Type": "application/json"]
        let result = try await client.get(url, headers: headers)
        return try Self.previews(from: result.data)
    }

    private func listURL(_ list: TraktListReference, page: Int, limit: Int) -> URL? {
        guard let user = Self.segment(list.username), let slug = Self.segment(list.listSlug) else { return nil }
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let query = "page=\(max(page, 1))&limit=\(min(max(limit, 1), 100))&extended=full"
        return URL(string: "\(base)/users/\(user)/lists/\(slug)/items?\(query)")
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
