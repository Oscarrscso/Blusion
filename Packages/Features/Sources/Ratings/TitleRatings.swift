import Foundation
import Observation
import StremioKit

/// Observable per title, so a score arriving late redraws only its own poster or review row.
@MainActor
@Observable
public final class TitleRatings: Identifiable {
    public nonisolated let id: String
    /// IMDb's score out of 10: from IMDb's own dataset on the device when it has the title, else the one the catalog carries.
    public internal(set) var imdb: Double?
    /// The votes behind `imdb`, known only when the score comes from the dataset.
    public internal(set) var imdbVotes: Int?
    /// Letterboxd's average out of 5, for films only.
    public internal(set) var letterboxd: Double?
    public internal(set) var rottenTomatoes: Double?
    public internal(set) var metacritic: Double?
    public internal(set) var tmdb: Double?
    public internal(set) var tmdbURL: URL?
    /// MyAnimeList's score out of 10, and the title's page there, for anime only.
    public internal(set) var myAnimeList: Double?
    public internal(set) var myAnimeListURL: URL?
    /// Whether the title is anime: as the addon marks it (`ReviewSite.isAnime`), or as TMDb says.
    public internal(set) var isAnime: Bool
    /// The film's best disc by Best Blurays, for the poster's disc mark. Nil until the site has answered, and when it names none.
    public internal(set) var bestDisc: BestDiscFormat?
    /// The first service the title streams on in the viewer's region, the mark shown when there is no disc. From TMDb.
    public internal(set) var streamer: TMDbWatchService?
    /// True once Best Blurays has answered for the film, so a film with no disc can ask for its streamer instead.
    @ObservationIgnored var discChecked = false
    @ObservationIgnored var catalogIMDb: Double?
    @ObservationIgnored var datasetIMDb: Double?

    nonisolated init(id: String, imdb: Double? = nil, letterboxd: Double? = nil, isAnime: Bool = false) {
        self.id = id
        self._imdb = imdb
        self._letterboxd = letterboxd
        self._isAnime = isAnime
        self.catalogIMDb = imdb
    }

    /// The site's own score, on its own scale; nil until that site has answered for this title.
    public func score(for source: RatingSource) -> Double? {
        switch source {
        case .letterboxd: letterboxd
        case .imdb: imdb
        case .myAnimeList: myAnimeList
        case .tmdb: tmdb
        }
    }

    /// The title as the rating filters and the Rating sorts judge it (see `RatingSource.order(isAnime:)`); nil until a site has scored it.
    public var judgedRating: JudgedRating? {
        RatingSource.judge(isAnime: isAnime || myAnimeList != nil) { score(for: $0) }
    }

    /// Whole numbers out of 100, never a decimal: IMDb and TMDb are out of 10 and Letterboxd out of 5, so each is scaled to 100 first
    /// ("8.6" is 86, "4.2" is 84). Rotten Tomatoes and Metacritic already are.
    public var imdbText: String? { imdb.map { String(Int(($0 * 10).rounded())) } }
    public var letterboxdText: String? { letterboxd.map { String(Int(($0 * 20).rounded())) } }
    /// The sites a poster prefers: MyAnimeList and Letterboxd for anime (IMDb standing in for Letterboxd, which has films only), else
    /// Letterboxd and IMDb.
    public var preferredPosterSites: [ReviewSite] {
        isAnime || myAnimeList != nil ? [.myAnimeList, .letterboxd, .imdb] : [.letterboxd, .imdb]
    }
    /// The preferred sites, then fill either missing score from the other available sites.
    public var posterSites: [ReviewSite] {
        let preferred = preferredPosterSites
        let order = preferred + ReviewSite.allCases.filter { !preferred.contains($0) }
        return Array(order.filter { shortText(for: $0) != nil }.prefix(2))
    }
    public var isEmpty: Bool { posterSites.isEmpty }

    /// The score alone, for a small button that already shows the site's icon: "8.7", "91%", "82".
    public func shortText(for site: ReviewSite) -> String? {
        switch site {
        case .imdb: imdbText
        case .letterboxd: letterboxdText
        case .rottenTomatoes: rottenTomatoes.map { String(format: "%.0f", $0) }
        case .metacritic: metacritic.map { String(format: "%.0f", $0) }
        case .tmdb: tmdb.map { String(Int(($0 * 10).rounded())) }
        case .myAnimeList: myAnimeList.map { String(Int(($0 * 10).rounded())) }
        }
    }

    /// The site's score out of 100, unrounded: IMDb and TMDb are out of 10 and Letterboxd out of 5, as `shortText` scales them.
    public func scoreOutOf100(for site: ReviewSite) -> Double? {
        switch site {
        case .imdb: imdb.map { $0 * 10 }
        case .letterboxd: letterboxd.map { $0 * 20 }
        case .rottenTomatoes: rottenTomatoes
        case .metacritic: metacritic
        case .tmdb: tmdb.map { $0 * 10 }
        case .myAnimeList: myAnimeList.map { $0 * 10 }
        }
    }

    /// The average of the scores the title page's ratings row shows (each site's own score, TMDb's included, never the ratings on single
    /// reviews), each out of 100 first, as a whole number out of 100. Nil until at least two sites have a score.
    public var averageScore: Int? {
        Self.average(of: ReviewSite.allCases.map { scoreOutOf100(for: $0) })
    }

    /// The rounded mean of the known scores, all out of 100; nil for fewer than two.
    nonisolated static func average(of scores: [Double?]) -> Int? {
        let known = scores.compactMap { $0 }
        guard known.count >= 2 else { return nil }
        return Int((known.reduce(0, +) / Double(known.count)).rounded())
    }

    public func text(for site: ReviewSite) -> String? {
        switch site {
        case .imdb: imdbText.map { "\($0)/100" }
        case .letterboxd: letterboxdText.map { "\($0)/100" }
        case .rottenTomatoes: rottenTomatoes.map { String(format: "%.0f%%", $0) }
        case .metacritic: metacritic.map { String(format: "%.0f/100", $0) }
        case .tmdb: tmdb.map { "\(Int(($0 * 10).rounded()))/100" }
        case .myAnimeList: myAnimeList.map { "\(Int(($0 * 10).rounded()))/100" }
        }
    }
}
