import Foundation
import StremioKit

public struct SearchResultFilter: Equatable, Sendable {
    public enum Sort: String, CaseIterable, Identifiable, Sendable {
        case relevance, rating, newest
        public var id: Self { self }
        public var title: String {
            switch self {
            case .relevance: "Relevance"
            case .rating: "Rating"
            case .newest: "Newest"
            }
        }
    }
    public var genre: String?
    public var year: Int?
    public var minimumRating: Int?
    public var sort = Sort.relevance
    public var isActive: Bool { genre != nil || year != nil || minimumRating != nil }
    public init() {}

    func matches(_ item: MetaPreview) -> Bool {
        if let genre, !item.genres.contains(where: { $0.localizedCaseInsensitiveCompare(genre) == .orderedSame }) { return false }
        if let year, SearchResults.year(of: item) != year { return false }
        if let minimumRating, (item.imdbRating ?? -1) < Double(minimumRating) { return false }
        return true
    }
}

enum SearchResults {
    static func year(of item: MetaPreview) -> Int? {
        guard let text = item.releaseInfo else { return nil }
        return text.split(whereSeparator: { !$0.isNumber }).first(where: { $0.count == 4 }).flatMap { Int($0) }
    }

    static func normalised(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0 != "'" && $0 != "’" }
        return folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    static func ranked(_ items: [MetaPreview], query: String, filter: SearchResultFilter, semantic: Bool = false) -> [MetaPreview] {
        let query = normalised(query)
        let words = query.split(separator: " ").map(String.init)
        let ranked = unique(items).filter(filter.matches).enumerated().map { index, item in
            (index: index, item: item, relevance: score(item.name, query: query, words: words))
        }
        return ranked.sorted { a, b in
            switch filter.sort {
            case .relevance:
                if !semantic, a.relevance != b.relevance { return a.relevance > b.relevance }
            case .rating:
                let left = a.item.imdbRating ?? -1, right = b.item.imdbRating ?? -1
                if left != right { return left > right }
            case .newest:
                let left = year(of: a.item) ?? 0, right = year(of: b.item) ?? 0
                if left != right { return left > right }
            }
            return a.index < b.index
        }.map(\.item)
    }

    static func unique(_ items: [MetaPreview]) -> [MetaPreview] {
        var identities = Set<String>()
        var aliases: [String: (index: Int, namespace: String)] = [:]
        var result: [MetaPreview] = []
        for item in items where identities.insert(item.identity).inserted {
            let namespace: String? = item.id.hasPrefix("tmdb:") ? "tmdb" : (LetterboxdRatings.isIMDbID(item.id) ? "imdb" : nil)
            if let namespace, let year = year(of: item) {
                let key = "\(item.type.lowercased())/\(normalised(item.name))/\(year)"
                if let existing = aliases[key], existing.namespace != namespace {
                    // Keep the addon-playable IMDb identity when the AI source names the same title by TMDb ID.
                    if namespace == "imdb" {
                        result[existing.index] = item
                        aliases[key] = (existing.index, namespace)
                    }
                    continue
                }
                aliases[key] = (result.count, namespace)
            }
            result.append(item)
        }
        return result
    }

    private static func score(_ name: String, query: String, words: [String]) -> Int {
        guard !query.isEmpty else { return 0 }
        let name = normalised(name)
        if name == query { return 500 }
        if name.hasPrefix(query + " ") { return 400 }
        let tokens = name.split(separator: " ").map(String.init)
        if words.allSatisfy({ tokens.contains($0) }) { return 300 }
        if words.allSatisfy({ word in tokens.contains(where: { $0.hasPrefix(word) }) }) { return 250 }
        if name.contains(query) { return 200 }
        return 0
    }
}
