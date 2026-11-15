import Foundation
import StremioKit

/// Which results the Search screen shows. People are a kind of their own: they are never mixed into the titles.
enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, movies, series, people

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .movies: "Movies"
        case .series: "Series"
        case .people: "People"
        }
    }

    func includes(_ item: MetaPreview) -> Bool {
        switch self {
        case .all: true
        case .movies: item.type.lowercased() == "movie"
        case .series: item.type.lowercased() == "series"
        case .people: false
        }
    }
}

/// One row of the suggestions shown while typing: a recent search, a title or a person.
enum SearchSuggestion: Identifiable, Hashable, Sendable {
    case recent(String)
    case media(MetaPreview)
    case person(TMDbTitlePerson)

    var id: String {
        switch self {
        case .recent(let term): "recent/\(term.lowercased())"
        case .media(let item): "media/\(item.identity)"
        case .person(let person): "person/\(person.id)"
        }
    }
}

struct SearchResultFilter: Equatable, Sendable {
    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case relevance, rating, newest
        var id: Self { self }
        var title: String {
            switch self {
            case .relevance: "Relevance"
            case .rating: "Rating"
            case .newest: "Newest"
            }
        }
    }
    /// The genres the results are narrowed to, in the order they were added. A result with any of them shows.
    var genres: [String] = []
    var year: Int?
    var minimumRating: Int?
    var sort = Sort.relevance
    var isActive: Bool { !genres.isEmpty || year != nil || minimumRating != nil }
    init() {}

    /// The one genre of a single-choice menu.
    var genre: String? {
        get { genres.first }
        set { genres = newValue.map { [$0] } ?? [] }
    }

    func matches(_ item: MetaPreview, rating: CatalogListFiltering.RatingLookup = JudgedRating.catalogue) -> Bool {
        if !genres.isEmpty, !genres.contains(where: { genre in
            MediaGenres.contains(genre, in: item.genres)
        }) { return false }
        if let year, SearchResults.year(of: item) != year { return false }
        if let minimumRating, (rating(item)?.score ?? -1) < Double(minimumRating) { return false }
        return true
    }
}

/// Search's one relevance, spelling and de-duplication: the results, the suggestions, the people and the described search use it.
enum SearchResults {
    static func year(of item: MetaPreview) -> Int? {
        guard let text = item.releaseInfo else { return nil }
        return text.split(whereSeparator: { !$0.isNumber }).first(where: { $0.count == 4 }).flatMap { Int($0) }
    }

    /// Lower case, accents and apostrophes dropped, everything but letters and digits a single space.
    static func normalised(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0 != "'" && $0 != "’" }
        return folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    // MARK: Relevance

    /// The lowest relevance of a name that holds every word typed, whole or begun.
    static let wordMatch = 500
    /// The lowest relevance of a name that holds the words as typed, in any way. Below it a match is a likely misspelling.
    static let literalMatch = 400

    /// How well a name answers the words typed, 0 to 1000: the name itself, the name without its article or spaces, a name that
    /// starts with the words, one that holds each word, one that holds each word begun, one that holds the text, then a likely
    /// misspelling (a letter wrong, missing, added or swapped in a word). 0 when nothing ties them.
    static func relevance(_ name: String, query: String) -> Int {
        let query = normalised(query)
        return score(normalised(name), query: query, words: query.split(separator: " ").map(String.init))
    }

    /// How much a title's TMDb ratings lift it, 0 to 320: a well-known title that starts with the words outranks an obscure one
    /// named exactly like them, while among equally known titles the closer name still leads.
    static func likelihood(_ votes: Int?) -> Int {
        guard let votes, votes > 0 else { return 0 }
        return min(320, Int(80 * log10(Double(votes) + 1)))
    }

    private static func score(_ name: String, query: String, words: [String]) -> Int {
        guard !query.isEmpty, !name.isEmpty else { return 0 }
        if name == query { return 1000 }
        let bareName = bare(name), bareQuery = bare(query)
        if bareName == bareQuery { return 950 }
        if name.replacingOccurrences(of: " ", with: "") == query.replacingOccurrences(of: " ", with: "") { return 900 }
        if name.hasPrefix(query + " ") || bareName.hasPrefix(bareQuery + " ") { return 800 }
        let tokens = name.split(separator: " ").map(String.init)
        if words.allSatisfy({ tokens.contains($0) }) { return 600 }
        if words.allSatisfy({ word in tokens.contains(where: { $0.hasPrefix(word) }) }) { return wordMatch }
        if name.contains(query) { return literalMatch }
        var slips = 0
        for (index, word) in words.enumerated() {
            let allowed = allowance(word)
            var best = allowed + 1
            for token in tokens {
                best = min(best, distance(word, token, limit: allowed))
                // The last word may still be being typed: it is compared with the start of each word too.
                if index == words.count - 1, token.count > word.count {
                    best = min(best, distance(word, String(token.prefix(word.count)), limit: allowed))
                }
            }
            guard best <= allowed else { return 0 }
            slips += best
        }
        return max(300 - 40 * slips, 100)
    }

    /// The letters a word may be off by: none in a short word, one up to seven letters, two beyond.
    private static func allowance(_ word: String) -> Int {
        word.count < 4 ? 0 : word.count < 8 ? 1 : 2
    }

    private static func bare(_ name: String) -> String {
        for article in ["the ", "a ", "an "] where name.hasPrefix(article) && name.count > article.count {
            return String(name.dropFirst(article.count))
        }
        return name
    }

    /// Whether two names are one, spelling slips aside: none in a short name, one from eight letters, two from fourteen.
    static func isSameName(_ a: String, _ b: String) -> Bool {
        let a = normalised(a), b = normalised(b)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let shorter = min(a.count, b.count)
        let allowed = shorter < 8 ? 0 : shorter < 14 ? 1 : 2
        return allowed > 0 && distance(a, b, limit: allowed) <= allowed
    }

    /// The edits between two words, a swap of neighbouring letters counting as one. Stops at `limit + 1` once it is passed.
    static func distance(_ first: String, _ second: String, limit: Int) -> Int {
        let a = Array(first), b = Array(second)
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var beforePrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            current[0] = i
            var lowest = i
            for j in 1...b.count {
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { value = min(value, beforePrevious[j - 2] + 1) }
                current[j] = value
                lowest = min(lowest, value)
            }
            if lowest > limit { return limit + 1 }
            beforePrevious = previous
            previous = current
        }
        return previous[b.count]
    }

    /// The name the words were likely meant as: the closest of `names` when none of them holds the words as typed and one is the
    /// same number of words, a letter or two off. Nil for a search that already matches something, so a valid one is never corrected.
    static func correction(for query: String, among names: [String]) -> String? {
        let typed = normalised(query)
        guard typed.count >= 4 else { return nil }
        let wordCount = typed.split(separator: " ").count
        var best: (name: String, score: Int)?
        for name in names {
            let score = relevance(name, query: typed)
            if score >= literalMatch { return nil }
            guard score >= 220, normalised(name).split(separator: " ").count == wordCount, score > (best?.score ?? 0) else { continue }
            best = (name, score)
        }
        return best?.name
    }

    // MARK: Ranking

    /// The titles once each, filtered, best first. By relevance: how well the name (or its original name, from `aliases` by
    /// identity) answers the words, lifted by how many TMDb ratings it has (`votes`, by identity), then the order given. `semantic` keeps the order
    /// given, for titles found by what they are about and not by their names.
    /// `rating` rates each title for the rating filter and the Rating sort (see `RatingSource.order(isAnime:)`).
    static func ranked(_ items: [MetaPreview], query: String, filter: SearchResultFilter, semantic: Bool = false,
                       aliases: [String: String] = [:], votes: [String: Int] = [:], minimumRelevance: Int = 0,
                       rating: CatalogListFiltering.RatingLookup = JudgedRating.catalogue) -> [MetaPreview] {
        let query = normalised(query)
        let words = query.split(separator: " ").map(String.init)
        let scored = merged(items).filter { filter.matches($0, rating: rating) }.enumerated()
            .compactMap { index, item -> (index: Int, item: MetaPreview, rank: Int, rating: Double)? in
                var relevance = score(normalised(item.name), query: query, words: words)
                if let alias = aliases[item.identity] { relevance = max(relevance, score(normalised(alias), query: query, words: words)) }
                guard relevance >= minimumRelevance else { return nil }
                return (index: index, item: item, rank: relevance + likelihood(votes[item.identity]),
                        rating: filter.sort == .rating ? rating(item)?.score ?? -1 : -1)
            }
        return scored.sorted { a, b in
            switch filter.sort {
            case .relevance:
                if !semantic, a.rank != b.rank { return a.rank > b.rank }
            case .rating:
                if a.rating != b.rating { return a.rating > b.rating }
            case .newest:
                let left = year(of: a.item) ?? 0, right = year(of: b.item) ?? 0
                if left != right { return left > right }
            }
            return a.index < b.index
        }.map(\.item)
    }

    /// People whose names answer the words, best first, then in the order given.
    static func ranked(_ people: [TMDbTitlePerson], query: String) -> [TMDbTitlePerson] {
        let scored: [(index: Int, person: TMDbTitlePerson, relevance: Int)] = people.enumerated().map { index, person in
            (index: index, person: person, relevance: relevance(person.name, query: query))
        }
        return scored
            .filter { $0.relevance > 0 }
            .sorted { $0.relevance != $1.relevance ? $0.relevance > $1.relevance : $0.index < $1.index }
            .map(\.person)
    }

    // MARK: De-duplication

    /// Excludes raw addon library entries and synthetic Easynews search placeholder rows that carry the addon logo instead of a title.
    static func isExcludedAddonItem(_ item: MetaPreview) -> Bool {
        let lowerType = item.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerType == "library" { return true }
        let lowerID = item.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerID.hasPrefix("easynews:")
            || lowerID.hasPrefix("easynews-plus:")
            || lowerID.hasPrefix("easynews_plus:")
            || lowerID.hasPrefix("easynews.")
            || lowerID == "easynews"
            || lowerID == "easynews-plus" {
            return true
        }
        if item.description?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .hasPrefix("provides search results from easynews") == true {
            return true
        }
        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "easynews",
           lowerType == "tv" {
            return true
        }
        return false
    }

    /// Each title once, in the order first seen. Two entries are one title when they share an identity, or when one names it by IMDb
    /// id and the other by TMDb id with the same type, name and year: the IMDb identity, which addons can play, is the one kept.
    /// Either way the entry kept takes what only the other knew (a poster, a synopsis, genres). A remake, another year or another
    /// type is never merged.
    static func merged(_ items: [MetaPreview]) -> [MetaPreview] {
        var positions: [String: Int] = [:]
        var aliases: [String: (index: Int, namespace: String)] = [:]
        var result: [MetaPreview] = []
        for item in items where !isExcludedAddonItem(item) {
            if let position = positions[item.identity] {
                result[position] = filling(result[position], from: item)
                continue
            }
            let namespace: String? = item.id.hasPrefix("tmdb:") ? "tmdb" : (LetterboxdRatings.isIMDbID(item.id) ? "imdb" : nil)
            if let namespace, let year = year(of: item) {
                let key = "\(item.type.lowercased())/\(normalised(item.name))/\(year)"
                if let existing = aliases[key], existing.namespace != namespace {
                    let kept = result[existing.index]
                    if namespace == "imdb" {
                        result[existing.index] = filling(item, from: kept)
                        aliases[key] = (existing.index, namespace)
                    } else {
                        result[existing.index] = filling(kept, from: item)
                    }
                    positions[item.identity] = existing.index
                    continue
                }
                aliases[key] = (result.count, namespace)
            }
            positions[item.identity] = result.count
            result.append(item)
        }
        return result
    }

    /// `item` with what it lacks taken from another entry for the same title.
    private static func filling(_ item: MetaPreview, from other: MetaPreview) -> MetaPreview {
        var filled = item
        filled.poster = item.poster ?? other.poster
        filled.background = item.background ?? other.background
        filled.logo = item.logo ?? other.logo
        filled.description = item.description ?? other.description
        filled.releaseInfo = item.releaseInfo ?? other.releaseInfo
        filled.imdbRating = item.imdbRating ?? other.imdbRating
        filled.runtime = item.runtime ?? other.runtime
        if filled.genres.isEmpty { filled.genres = other.genres }
        return filled
    }
}
