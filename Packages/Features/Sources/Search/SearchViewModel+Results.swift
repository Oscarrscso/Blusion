import Foundation
import Observation
import StremioKit

extension SearchViewModel {
    // MARK: Results

    private var combinedResults: [MetaPreview] { groups.flatMap(\.items) + tmdbTitles + describedItems }

    /// Everything the ranking reads. The lists are ranked once for each state of these, however often the screen asks.
    struct RankInputs: Equatable {
        var query: String
        var filter: SearchResultFilter
        var resolvedGenres: [String: [String]]
        var requiredGenres: [String]
        var excludedGenres: [String]
        var sections: [Section]
        var titles: [MetaPreview]
        var described: [MetaPreview]
        var aliases: [String: String]
        var votes: [String: Int]
        var isDiscovery: Bool
        /// Set for Pick for me: the order's seed, and whether every pick has arrived.
        var pickSeed: Int?
        var pickIsReady: Bool
    }

    /// The titles to show: every source merged, each title once, filtered and best first. People are apart, in `people`.
    func results(in scope: SearchScope = .all) -> [MetaPreview] {
        guard scope != .people else { return [] }
        // The rating filter and the Rating sort read each title's scores, some arriving later, so their list is worked out on each read:
        // the view reading it draws again as each score arrives.
        guard filter.minimumRating == nil, filter.sort != .rating else {
            return scope == .all ? rankedTitles() : rankedTitles().filter(scope.includes)
        }
        let inputs = RankInputs(query: query, filter: filter, resolvedGenres: resolvedGenres,
                                requiredGenres: requiredGenres, excludedGenres: excludedGenres, sections: sections, titles: tmdbTitles, described: describedItems,
                                aliases: aliases, votes: votes, isDiscovery: isDiscovery, pickSeed: isPickSearch ? pickSeed : nil,
                                pickIsReady: !isPickSearch || (aiPhase == .done && !isResolvingGenres))
        if memo?.inputs != inputs { memo = (inputs, [:]) }
        if let cached = memo?.lists[scope] { return cached }
        let list = scope == .all ? rankedTitles() : results(in: .all).filter(scope.includes)
        memo?.lists[scope] = list
        return list
    }

    private func rankedTitles() -> [MetaPreview] {
        if isPickSearch {
            // Shown once they have all arrived, so the drawn order does not move cards about as batches come in. Each title's place
            // comes from the seed and its identity: a filter leaves the others where they were. A chosen sort takes the order's place.
            guard aiPhase == .done, !isResolvingGenres else { return [] }
            let items = SearchResults.ranked(genreChecked(describedItems), query: query, filter: filter, semantic: true, rating: ratingLookup)
            guard filter.sort == .relevance else { return items }
            let seed = pickSeed
            return items.map { item -> (place: Int, item: MetaPreview) in
                var hasher = Hasher()
                hasher.combine(seed)
                hasher.combine(item.identity)
                return (hasher.finalize(), item)
            }.sorted { $0.place < $1.place }.map(\.item)
        }
        let named = genreChecked(groups.flatMap(\.items) + tmdbTitles)
        let described = genreChecked(describedItems)
        guard isDiscovery else {
            return SearchResults.ranked(named + described, query: query, filter: filter, aliases: aliases, votes: votes, rating: ratingLookup)
        }
        // A description is answered by what was found for it, in the order found. A title whose own name holds the words keeps a
        // place: first when it is named outright, last otherwise. Titles that only came back for the words are left out.
        let literal = SearchResults.ranked(named, query: query, filter: SearchResultFilter(), aliases: aliases,
                                           minimumRelevance: SearchResults.wordMatch)
        let outright = literal.filter { SearchResults.relevance($0.name, query: query) >= 800 }
        let rest = literal.filter { item in !outright.contains { $0.identity == item.identity } }
        return SearchResults.ranked(outright + described + rest, query: query, filter: filter, semantic: true, rating: ratingLookup)
    }

    /// How the rating filter and the Rating sort rate a title: from the rating store, which looks up the scores a title lacks.
    private var ratingLookup: CatalogListFiltering.RatingLookup {
        guard filter.minimumRating != nil || filter.sort == .rating else { return JudgedRating.catalogue }
        let store = services.posterRatings
        return { item in store.judgedRating(for: item) ?? JudgedRating.catalogue(item) }
    }

    /// The people the search found: those TMDb has for the words as a name, best first, or those a described search names.
    var people: [TMDbTitlePerson] {
        isDiscovery ? namedPeople : SearchResults.ranked(tmdbPeople, query: query)
    }

    var availableGenres: [String] {
        MediaGenres.normalised(combinedResults.flatMap { resolvedGenres[$0.identity] ?? $0.genres })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var availableYears: [Int] { Array(Set(combinedResults.compactMap { SearchResults.year(of: $0) })).sorted(by: >) }

    func clearFilters() { filter = SearchResultFilter() }

    /// A typed genre is a requirement for the whole results grid, including literal addon/TMDb matches.
    private var requiredGenres: [String] {
        guard isDiscovery else { return [] }
        return discovery?.filters.genres ?? DescribedSearch.reading(term).genres
    }

    private var excludedGenres: [String] {
        guard isDiscovery else { return [] }
        return discovery?.filters.excludedGenres ?? DescribedSearch.reading(term).excludedGenres
    }

    private var needsGenreMetadata: Bool {
        !filter.genres.isEmpty || !requiredGenres.isEmpty || !excludedGenres.isEmpty
    }

    /// Ordinary title searches still publish immediately. Genre searches publish checked batches as they finish.
    func resolveGenreFilters() {
        genreTask?.cancel()
        isResolvingGenres = false
        guard needsGenreMetadata else { return }
        let current = term
        let candidates = SearchResults.merged(combinedResults).filter { resolvedGenres[$0.identity] == nil }
        guard !candidates.isEmpty else { return }
        isResolvingGenres = true
        genreTask = Task { [weak self] in
            guard let self else { return }
            for start in stride(from: 0, to: candidates.count, by: 12) {
                let batch = Array(candidates[start..<min(start + 12, candidates.count)])
                let items = await self.services.browse.resolvingGenres(in: batch)
                guard !Task.isCancelled, self.term == current else { return }
                for item in items { self.resolvedGenres[item.identity] = item.genres }
            }
            self.isResolvingGenres = false
        }
    }

    private func genreChecked(_ items: [MetaPreview]) -> [MetaPreview] {
        let required = requiredGenres
        let excluded = excludedGenres
        // A title shown for a genre leads with it on its card and its page.
        let shownFor = filter.genres + required
        return items.compactMap { item in
            guard let genres = resolvedGenres[item.identity] else { return needsGenreMetadata ? nil : item }
            guard required.allSatisfy({ MediaGenres.contains($0, in: genres) }),
                  !excluded.contains(where: { MediaGenres.contains($0, in: genres) }) else { return nil }
            var copy = item
            copy.genres = MediaGenres.leading(shownFor, in: genres)
            return copy
        }
    }

    // MARK: Suggestions and corrections

    /// True while the field holds words the full results were not asked for: the screen may show `suggestions` instead.
    var showsSuggestions: Bool { !term.isEmpty && submittedTerm != term }

    /// What the words may be heading for, at most ten rows: recent searches, people, then titles, each matching the words by name.
    /// Before the network answers they come from what this screen found earlier. Empty for words that match no name, such as a
    /// description, which goes straight to its results.
    var suggestions: [SearchSuggestion] {
        let term = self.term
        guard !term.isEmpty else { return [] }
        let waiting = phase == .searching
        let found = groups.flatMap(\.items) + tmdbTitles
        let titles = SearchResults.ranked(found.isEmpty && waiting ? knownTitles : found, query: term, filter: SearchResultFilter(),
                                          aliases: aliases, minimumRelevance: found.isEmpty ? SearchResults.wordMatch : 100)
        let persons = SearchResults.ranked(tmdbPeople.isEmpty && waiting ? knownPeople : tmdbPeople, query: term)
        let shown = Array(titles.prefix(6))
        // A recent search that is one of the titles is that title's row.
        let recents = recentQueries.filter { recent in
            Self.key(recent) != Self.key(term) && SearchResults.relevance(recent, query: term) >= SearchResults.wordMatch
                && !shown.contains { Self.key($0.name) == Self.key(recent) }
        }
        return recents.prefix(2).map(SearchSuggestion.recent) + persons.prefix(2).map(SearchSuggestion.person)
            + shown.map(SearchSuggestion.media)
    }

    /// The name the words were likely meant as, once the search is done and nothing matches them as typed. Nil for a search that
    /// found what it named, and for a description.
    var correction: String? {
        guard phase == .done, !isDiscovery else { return nil }
        let names = (groups.flatMap(\.items) + tmdbTitles).map(\.name) + tmdbPeople.map(\.name)
        return SearchResults.correction(for: term, among: names)
    }

    /// Searches for the corrected name instead.
    func applyCorrection() async {
        guard let correction else { return }
        query = correction
        await submit()
    }

    // MARK: Filter chips

    /// What a described search was read as asking for, each requirement one chip.
    var chips: [SearchChip] { isDiscovery ? discovery?.chips ?? [] : [] }

    func options(for chip: SearchChip) -> [SearchChipOption] { discovery?.options(for: chip.kind) ?? [] }

    func remove(_ chip: SearchChip) {
        if let discovery { applyDiscovery(discovery.removing(chip.kind)) }
    }

    /// Searches the edited plan. The words are not read again, so no model interprets anything: only the database is asked, and
    /// a check of candidates already made is reused.
    func applyDiscovery(_ plan: AISearchPlan) {
        let term = self.term
        guard !term.isEmpty, plan != discovery else { return }
        discovery = plan
        editedPlan = plan
        namedPeople.removeAll { person in !plan.people.contains { $0.name == person.name } }
        describedItems = []
        aiPhase = .searching
        searchAI(term, plan: plan)
    }
}
