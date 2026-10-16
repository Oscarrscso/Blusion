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
}
