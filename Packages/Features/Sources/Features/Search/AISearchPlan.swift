import Foundation
import StremioKit

/// A bounded set of database searches, not titles invented by the language model.
public struct AISearchPlan: Sendable, Equatable {
    public struct Person: Sendable, Equatable {
        public enum Role: String, Sendable { case cast, director, writer, creator }
        public var name: String
        public var role: Role
        public init(name: String, role: Role) { self.name = name; self.role = role }
    }

    public var filters: DescribedSearch
    public var titleQueries: [String]
    public var referenceTitles: [String]
    public var people: [Person]
    public var companies: [String]
    public var language: String?
    public var excludedTopics: [String]
    public var requiresSemanticRanking: Bool
    public var unwatchedOnly: Bool
    /// The lexical fallback can still find factual matches, but an inference failure must remain retryable.
    var interpretationFailed = false

    public init(filters: DescribedSearch, titleQueries: [String] = [], referenceTitles: [String] = [], people: [Person] = [],
                companies: [String] = [], language: String? = nil, excludedTopics: [String] = [], unwatchedOnly: Bool = false,
                requiresSemanticRanking: Bool = true) {
        self.filters = filters
        self.titleQueries = Array(titleQueries.prefix(2))
        self.referenceTitles = Array(referenceTitles.prefix(2))
        self.people = Array(people.prefix(3))
        self.companies = Array(companies.prefix(2))
        let code = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.language = code?.count == 2 && code?.allSatisfy(\.isLetter) == true ? code : nil
        self.excludedTopics = Array(excludedTopics.prefix(2))
        self.requiresSemanticRanking = requiresSemanticRanking
        self.unwatchedOnly = unwatchedOnly
    }

    /// Separate movie and TV queries map genres to each medium's IDs (878 versus 10765, for example).
    func queries(keywords: [TMDbDiscoverQuery.Named], excluded: [TMDbDiscoverQuery.Named] = [],
                 companies: [TMDbDiscoverQuery.Named] = []) -> [TMDbDiscoverQuery] {
        let kinds = filters.kind.map { [$0] } ?? [.movie, .series]
        return kinds.map { kind in
            var search = filters
            search.kind = kind
            var query = search.query(keywords: keywords)
            query.language = language
            query.excludedKeywords = excluded
            query.companies = companies
            return query
        }
    }

    /// Words inside a named film are not genre, score or runtime constraints ("War of the Worlds", "Best in Show", "Short Term 12").
    static func explicitFilters(in text: String, namedTitles: [String]) -> DescribedSearch {
        var constraints = text
        for title in namedTitles where !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pattern = "(?<![[:alnum:]])" + NSRegularExpression.escapedPattern(for: title) + "(?![[:alnum:]])"
            constraints = constraints.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        // A translated or corrected name may not occur verbatim. Let the model's parsed constraints stand in that case.
        if !namedTitles.isEmpty, constraints == text { return DescribedSearch() }
        return .reading(constraints)
    }
}

/// Facts attached only to search candidates; never written into a title's synopsis or saved metadata.
public struct AISearchCandidate: Sendable {
    public let item: MetaPreview
    public let evidence: String
    public let metadata: TMDbSearchMetadata?
    public init(item: MetaPreview, evidence: String, metadata: TMDbSearchMetadata? = nil) {
        self.item = item; self.evidence = evidence; self.metadata = metadata
    }
}

public struct AISearchUpdate: Sendable {
    public enum Issue: Sendable, Equatable {
        case needsTMDbToken, database, ranking

        public var text: String {
            switch self {
            case .needsTMDbToken: "Add a TMDB Read Access Token in Settings to use AI Search."
            case .database: "Some search data couldn't load. Try again."
            case .ranking: "On-device AI couldn't check some matches. Try again."
            }
        }
    }

    public enum Stage: Sendable, Equatable {
        case interpreting, filters, titles, people, similar, themes, ranking, complete
        public var text: String {
            switch self {
            case .interpreting: "Understanding your search…"
            case .filters: "Finding matches for your filters…"
            case .titles: "Checking titles…"
            case .people: "Checking cast, crew and studios…"
            case .similar: "Finding related films and series…"
            case .themes: "Searching themes, settings and tone…"
            case .ranking: "Checking more matches on your device…"
            case .complete: "Search complete"
            }
        }
    }
    public let items: [MetaPreview]
    public let stage: Stage
    public let issue: Issue?

    public init(items: [MetaPreview], stage: Stage, issue: Issue? = nil) {
        self.items = items
        self.stage = stage
        self.issue = issue
    }
}
