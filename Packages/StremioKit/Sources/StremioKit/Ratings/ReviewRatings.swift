import Foundation

/// Scores found by the review lookups. TMDb's score is out of 10. IMDb and Letterboxd scores come from the catalog or the
/// Letterboxd page and are not stored here.
public struct ReviewRatings: Sendable, Codable, Equatable {
    public var tmdb: Double?
    public var tmdbURL: URL?

    public init(tmdb: Double? = nil, tmdbURL: URL? = nil) {
        self.tmdb = tmdb
        self.tmdbURL = tmdbURL
    }

    public var isEmpty: Bool { tmdb == nil && tmdbURL == nil }
}

/// Links never guess a review-page slug from the title. A search link says so in the UI. Rotten Tomatoes and Metacritic have no
/// keyless score source, so for them the app offers search links only.
public enum ReviewSite: String, CaseIterable, Sendable, Identifiable {
    case imdb, letterboxd, rottenTomatoes, metacritic, tmdb
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .imdb: "IMDb"
        case .letterboxd: "Letterboxd"
        case .rottenTomatoes: "Rotten Tomatoes"
        case .metacritic: "Metacritic"
        case .tmdb: "TMDB"
        }
    }

    public func isSearch(for item: MetaPreview, tmdbURL: URL? = nil) -> Bool {
        switch self {
        case .imdb: !LetterboxdRatings.isIMDbID(item.id)
        case .letterboxd: item.type != "movie" || !LetterboxdRatings.isIMDbID(item.id)
        case .tmdb: tmdbURL == nil
        case .rottenTomatoes, .metacritic: true
        }
    }

    public func url(for item: MetaPreview, tmdbURL: URL? = nil) -> URL? {
        if self == .imdb, LetterboxdRatings.isIMDbID(item.id) { return URL(string: "https://www.imdb.com/title/\(item.id)/") }
        if self == .letterboxd, item.type == "movie", LetterboxdRatings.isIMDbID(item.id) {
            return URL(string: "https://letterboxd.com/imdb/\(item.id)/")
        }
        if self == .tmdb, let tmdbURL { return tmdbURL }
        let base: String
        let parameter: String
        switch self {
        case .imdb: base = "https://www.imdb.com/find/"; parameter = "q"
        case .letterboxd: base = "https://letterboxd.com/search/"; parameter = "q"
        case .rottenTomatoes: base = "https://www.rottentomatoes.com/search"; parameter = "search"
        case .metacritic:
            let title = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            return title.flatMap { URL(string: "https://www.metacritic.com/search/\($0)/") }
        case .tmdb: base = "https://www.themoviedb.org/search"; parameter = "query"
        }
        var parts = URLComponents(string: base)
        parts?.queryItems = [URLQueryItem(name: parameter, value: item.name)]
        return parts?.url
    }
}
