import Foundation
import StremioKit

/// What Pick for me is asked for. Every choice is optional: with none made it picks from well-liked titles of either kind. The choices
/// become a search plan as they stand, so no words are read and no model is asked.
public struct SearchPick: Equatable, Sendable {
    public enum Mood: String, CaseIterable, Identifiable, Sendable {
        case funny = "Funny"
        case feelGood = "Feel-good"
        case romantic = "Romantic"
        case exciting = "Exciting"
        case tense = "Tense"
        case scary = "Scary"
        case mindBending = "Mind-bending"
        case emotional = "Emotional"
        case inspiring = "Inspiring"
        case thoughtProvoking = "Thought-provoking"

        public var id: Self { self }
        public var title: String { rawValue }

        /// The genre that is the mood, for the moods that are one.
        var genre: String? {
            switch self {
            case .funny: "Comedy"
            case .romantic: "Romance"
            case .exciting: "Action"
            case .scary: "Horror"
            default: nil
            }
        }

        /// TMDb's keywords for the mood, each one a keyword of that very name. A mood that is a genre has them for the kind TMDb
        /// gives no such genre: series have no romance or horror genre.
        var topics: [String] {
            switch self {
            case .funny, .exciting: []
            case .feelGood: ["feel good", "heartwarming"]
            case .romantic: ["romance"]
            case .tense: ["suspenseful"]
            case .scary: ["horror"]
            case .mindBending: ["mind-bending", "plot twist"]
            case .emotional: ["tearjerker"]
            case .inspiring: ["inspirational"]
            case .thoughtProvoking: ["thought provoking"]
            }
        }
    }

    public var kind: TMDbDiscoverQuery.Kind?
    public var mood: Mood?
    public var genre: String?
    /// The first year of the decade.
    public var decade: Int?
    public var maximumRuntime: Int?
    /// TMDb's score, 0 to 10.
    public var minimumScore: Double?

    public init() {}

    /// The genres offered for a kind: series are not offered the genres TMDb has for films alone.
    public static func genres(for kind: TMDbDiscoverQuery.Kind?) -> [String] {
        guard let kind else { return allGenres }
        return allGenres.filter { TMDbDiscoverQuery.genre(named: $0, kind: kind) != nil }
    }

    private static let allGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "History", "Horror",
        "Mystery", "Romance", "Science Fiction", "Thriller", "War", "Western",
    ]

    /// This decade back to the 1950s.
    public static func decades(now: Date = Date()) -> [Int] {
        let current = Calendar(identifier: .gregorian).component(.year, from: now) / 10 * 10
        return Array(stride(from: current, through: 1950, by: -10))
    }

    public static let runtimes = [30, 60, 90, 120, 150]
    public static let scores = [6.0, 7.0, 7.5, 8.0]

    public static func runtimeTitle(_ minutes: Int) -> String { "Under \(minutes) min" }
    public static func scoreTitle(_ score: Double) -> String { AISearchPlan.scoreTitle(score) }

    /// The choices in words, as the search field shows them: "Funny movies from the 1990s under 120 minutes".
    public var title: String {
        let lead = [mood?.title, genre?.lowercased()].compactMap { $0 }.joined(separator: " ")
        var text: String
        switch (lead.isEmpty, kind) {
        case (true, nil): text = "Something to watch"
        case (true, let kind?): text = "\(kind.title) to watch"
        case (false, nil): text = "\(lead) movies and series"
        case (false, let kind?): text = "\(lead) \(kind.title.lowercased())"
        }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if let decade { text += " from the \(decade)s" }
        if let maximumRuntime { text += " under \(maximumRuntime) minutes" }
        if let minimumScore { text += " rated \(String(format: "%g", minimumScore))+" }
        return text
    }

    /// The choices as the plan the search runs. A mood that is a genre asks for that genre, or for its keywords where the chosen
    /// kind has no such genre; the other moods ask for their keywords. With nothing to go on, the plan asks for well-liked titles.
    var plan: AISearchPlan {
        var filters = DescribedSearch(kind: kind, genres: [genre].compactMap { $0 }, maximumRuntime: maximumRuntime)
        filters.minimumScore = minimumScore
        if let decade { (filters.earliestYear, filters.latestYear) = (decade, decade + 9) }
        if let mood {
            if let moodGenre = mood.genre, kind.map({ TMDbDiscoverQuery.genre(named: moodGenre, kind: $0) != nil }) ?? true {
                if !filters.genres.contains(moodGenre) { filters.genres.append(moodGenre) }
            } else {
                filters.moods = mood.topics
            }
        }
        if filters.isEmpty { filters.minimumScore = DescribedSearchService.crowdPleaserScore }
        var plan = AISearchPlan(filters: filters, requiresSemanticRanking: false)
        // The keywords are TMDb's own: titles tagged with them need no further check.
        plan.trustsTopicMatches = true
        return plan
    }
}
