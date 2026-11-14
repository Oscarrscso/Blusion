import Foundation
import Observation
import StremioKit

/// Search, as one pipeline for every appearance of the screen. A query is answered in stages, none waiting for the next: what is
/// already known gives suggestions at once; after a debounce every searchable addon and TMDb (titles and people) are asked
/// together; and a query that describes what to watch is read into a plan, on device where that needs language understanding, and
/// answered from real TMDb data. An addon failure never hides results from the other sources.
@MainActor
@Observable
public final class SearchViewModel {
    public struct Section: Identifiable, Equatable {
        public let addon: AddonSummary
        public var items: [MetaPreview]
        public var id: UUID { addon.id }
    }

    /// The results of one content type across every addon: one row on the Search screen.
    public struct Group: Identifiable, Equatable {
        public let type: String
        public let title: String
        public var items: [MetaPreview]
        public var id: String { type }
    }

    public struct Failure: Identifiable, Equatable {
        public let addon: AddonSummary
        public let error: AddonError
        public var id: UUID { addon.id }
        public var text: String { "\(addon.name): \(error.shortDescription)" }
    }

    public enum Phase: Equatable {
        case idle
        case searching
        case done
    }

    /// Independent of the addon and TMDb search: the described search keeps its spinner until its own work ends.
    public private(set) var aiPhase: Phase = .idle
    public private(set) var aiStage: AISearchUpdate.Stage = .interpreting
    public private(set) var aiIssue: AISearchUpdate.Issue?
    private var aiRequestID = UUID()

    /// A category on the idle Search page. `sources` are the movie and series catalogs filtered to the genre, merged when it opens.
    public struct GenreShortcut: Identifiable, Hashable, Sendable {
        public let name: String
        public let sources: [WidgetSource]
        /// Movie/TV still for recognised genres; nil keeps the coloured tile for other addon genres.
        public var imageURL: URL?
        public var id: String { name.lowercased() }

        public init(name: String, sources: [WidgetSource], imageURL: URL? = nil) {
            self.name = name
            self.sources = sources
            self.imageURL = imageURL
        }
    }

    public var query = ""
    /// Which results show: everything, one kind of title, or people.
    public var scope = SearchScope.all
    /// The words of the last Pick for me, and the plan they stand for.
    private var pickQuery: String?
    private var pickPlan: AISearchPlan?
    /// Draws the order the picks show in. Changed by each pick.
    private var pickSeed = 0
    /// Whether the results are Pick for me's: the titles its choices allow, in an order drawn for each pick.
    public var isPickSearch: Bool { pickQuery != nil && term == pickQuery }

    /// Searches for what was chosen, as a plan: no words are read, so no model is asked and the search starts at once. Asked again
    /// for the choices already showing, it draws them in a new order.
    public func pick(_ pick: SearchPick) {
        let text = pick.title
        if term == text, isPickSearch, aiPhase == .searching || !describedItems.isEmpty {
            shufflePick()
            return
        }
        stopWork()
        clearFilters()
        scope = .all
        pickSeed = Int.random(in: Int.min...Int.max)
        pickPlan = pick.plan
        pickQuery = text
        query = text
        begin(text)
        submittedTerm = text
        // Set now, so the field's change to these words does not start the search a second time.
        activeTerm = text
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(text)
        }
    }

    /// The picks showing, in a new order.
    public func shufflePick() { pickSeed = Int.random(in: Int.min...Int.max) }

    public var filter = SearchResultFilter() {
        didSet { if filter.genres != oldValue.genres { resolveGenreFilters() } }
    }
    public private(set) var sections: [Section] = [] { didSet { resolveGenreFilters() } }
    public private(set) var failures: [Failure] = []
    public private(set) var phase: Phase = .idle
    /// False when no enabled addon offers a searchable catalog. TMDb can still answer. See `refreshAvailability()`.
    public private(set) var hasSearchableAddons = true
    /// Whether TMDb can be searched: a token is set, or a search of it has answered.
    public private(set) var hasTMDb = false
    /// The categories of the idle Search page: each genre once, open on its movies and series together. Filled by `refreshAvailability()`.
    public private(set) var categories: [GenreShortcut] = []
    /// The last titles opened from Search, newest first, at most 4. Kept in the history store.
    public private(set) var recentQueries: [String]

    private static let maxRecents = 4

    private let services: AppServices
    private let debounce: Duration
    private let history: any SearchHistoryStore
    private var task: Task<Void, Never>?
    private var activeTerm: String?
    private var genreTask: Task<Void, Never>?
    public private(set) var isResolvingGenres = false
    private var resolvedGenres: [String: [String]] = [:]
    /// Search availability changes when returning from Settings, not on each new query.
    private var availabilityLoaded = false

    /// TMDb's titles for the words as a name, with IMDb identities. Being on TMDb says nothing about whether a stream exists.
    public private(set) var tmdbTitles: [MetaPreview] = [] { didSet { resolveGenreFilters() } }
    /// TMDb's original names for those titles, by identity: another name the words may match.
    private var aliases: [String: String] = [:]
    /// TMDb's rating counts for those titles, by identity: how likely each is to be the one meant.
    private var votes: [String: Int] = [:]
    private var tmdbPeople: [TMDbTitlePerson] = []
    /// The people a described search names ("Tom Hanks films from the 90s"), as TMDb has them.
    private var namedPeople: [TMDbTitlePerson] = []
    private let universal: @Sendable (String) async throws -> TMDbSearchHits?
    private var tmdbTask: Task<Void, Never>?
    private var peopleTask: Task<Void, Never>?

    /// Titles found for what the words describe, or for the words as a title or topic. Real TMDb titles, in the order found.
    public private(set) var describedItems: [MetaPreview] = [] { didSet { resolveGenreFilters() } }
    private let describer: DescribedSearchService
    private var aiTask: Task<Void, Never>?
    /// False limits the search to the addons: Blusion TV's show picker.
    private let includesAISearch: Bool
    /// Whether the words describe what to watch ("funny 90s movies") rather than name a title or a person ("Dune", "Tom Hanks").
    public private(set) var isDiscovery = false { didSet { resolveGenreFilters() } }
    /// What a described search was read as asking for: what the filter chips show and change.
    public private(set) var discovery: AISearchPlan? { didSet { resolveGenreFilters() } }
    /// Set once a chip was changed: the plan a retry searches again, without reading the words again.
    private var editedPlan: AISearchPlan?
    /// The words the full results were asked for, by Return, a recent search or a suggestion. While the field holds anything else
    /// the screen may show suggestions instead.
    private var submittedTerm: String?

    /// Titles and people found earlier on this screen, newest first: what suggestions are made from before the network answers.
    @ObservationIgnored private var knownTitles: [MetaPreview] = []
    @ObservationIgnored private var knownPeople: [TMDbTitlePerson] = []
    @ObservationIgnored private var memo: (inputs: RankInputs, lists: [SearchScope: [MetaPreview]])?

    /// Where the results come from. While typing, the last words' results stay on screen until each source answers the new ones.
    private enum ResultSource { case addons, tmdb, described }
    @ObservationIgnored private var stale: Set<ResultSource> = []

    /// Whether this device checks described searches with the on-device model.
    public var aiAvailable: Bool { includesAISearch && describer.ranker != nil }

    public var isUsingAI: Bool {
        aiAvailable && aiPhase == .searching && (aiStage == .ranking
            || (editedPlan == nil && !DescribedSearch.isFilterOnly(term) && !AISearchGrounding.mightBeTitle(term)))
    }

    /// `history` keeps the recent searches. Without one they live only as long as this model. `universal` answers TMDb's titles and
    /// people for a name, nil when TMDb cannot be asked.
    public init(services: AppServices, debounce: Duration = .milliseconds(250), history: (any SearchHistoryStore)? = nil,
                describer: DescribedSearchService? = nil, includesAISearch: Bool = true,
                universal: (@Sendable (String) async throws -> TMDbSearchHits?)? = nil) {
        let store = history ?? InMemorySearchHistoryStore()
        self.services = services
        self.includesAISearch = includesAISearch
        self.describer = describer ?? .live(services)
        let tmdb = TMDbSearch(services)
        if !includesAISearch {
            self.universal = { _ in nil }
        } else if let universal {
            self.universal = universal
        } else {
            self.universal = { text in try await tmdb.hits(for: text) }
        }
        self.debounce = debounce
        self.history = store
        self.recentQueries = Self.normalised(store.load())
    }

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var hasResults: Bool {
        sections.contains { !$0.items.isEmpty } || !tmdbTitles.isEmpty || !describedItems.isEmpty || !people.isEmpty
    }
    /// Nothing came back and every addon failed because the device is offline.
    public var isOffline: Bool { !hasResults && Connectivity.isOffline(failures.map(\.error)) }
    /// "No results" needs a source that could have answered; with none the screen says so instead.
    public var showsNoResults: Bool {
        phase == .done && aiPhase == .done && !isResolvingGenres && !hasResults && failures.isEmpty && aiIssue == nil && (hasSearchableAddons || hasTMDb)
    }
    public var showsNoSearchableAddons: Bool { !hasSearchableAddons && !hasTMDb }

    // MARK: Results

    private var combinedResults: [MetaPreview] { groups.flatMap(\.items) + tmdbTitles + describedItems }

    /// Everything the ranking reads. The lists are ranked once for each state of these, however often the screen asks.
    private struct RankInputs: Equatable {
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
    public func results(in scope: SearchScope = .all) -> [MetaPreview] {
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
    public var people: [TMDbTitlePerson] {
        isDiscovery ? namedPeople : SearchResults.ranked(tmdbPeople, query: query)
    }

    public var availableGenres: [String] {
        MediaGenres.normalised(combinedResults.flatMap { resolvedGenres[$0.identity] ?? $0.genres }).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public var availableYears: [Int] { Array(Set(combinedResults.compactMap { SearchResults.year(of: $0) })).sorted(by: >) }

    public func clearFilters() { filter = SearchResultFilter() }

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
    private func resolveGenreFilters() {
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
    public var showsSuggestions: Bool { !term.isEmpty && submittedTerm != term }

    /// What the words may be heading for, at most ten rows: recent searches, people, then titles, each matching the words by name.
    /// Before the network answers they come from what this screen found earlier. Empty for words that match no name, such as a
    /// description, which goes straight to its results.
    public var suggestions: [SearchSuggestion] {
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
    public var correction: String? {
        guard phase == .done, !isDiscovery else { return nil }
        let names = (groups.flatMap(\.items) + tmdbTitles).map(\.name) + tmdbPeople.map(\.name)
        return SearchResults.correction(for: term, among: names)
    }

    /// Searches for the corrected name instead.
    public func applyCorrection() async {
        guard let correction else { return }
        query = correction
        await submit()
    }

    // MARK: Filter chips

    /// What a described search was read as asking for, each requirement one chip.
    public var chips: [SearchChip] { isDiscovery ? discovery?.chips ?? [] : [] }

    public func options(for chip: SearchChip) -> [SearchChipOption] { discovery?.options(for: chip.kind) ?? [] }

    public func remove(_ chip: SearchChip) {
        if let discovery { applyDiscovery(discovery.removing(chip.kind)) }
    }

    /// Searches the edited plan. The words are not read again, so no model interprets anything: only the database is asked, and
    /// a check of candidates already made is reused.
    public func applyDiscovery(_ plan: AISearchPlan) {
        let term = self.term
        guard !term.isEmpty, plan != discovery else { return }
        discovery = plan
        editedPlan = plan
        namedPeople.removeAll { person in !plan.people.contains { $0.name == person.name } }
        describedItems = []
        aiPhase = .searching
        searchAI(term, plan: plan)
    }

    // MARK: Running a search

    private func stopWork() {
        task?.cancel()
        genreTask?.cancel()
        isResolvingGenres = false
        tmdbTask?.cancel()
        aiTask?.cancel()
        peopleTask?.cancel()
        aiRequestID = UUID()
        activeTerm = nil
    }

    public func cancel() {
        stopWork()
        if phase == .searching { phase = .idle }
        if aiPhase == .searching { aiPhase = .idle }
    }

    /// Marks both searches as running. `keepingResults` leaves what the last words found on screen, each source's results replaced
    /// when it answers the new words, so typing never blanks the page; a change between a name and a description clears at once.
    private func begin(_ term: String, keepingResults: Bool = false) {
        let pick = term == pickQuery ? pickPlan : nil
        let discovers = pick != nil || (includesAISearch && !AISearchGrounding.mightBeTitle(term))
        if keepingResults, pick == nil, discovers == isDiscovery, hasResults {
            stale = [.addons, .tmdb, .described]
        } else {
            stale = []
            resolvedGenres = [:]
            sections = []
            tmdbTitles = []
            aliases = [:]
            votes = [:]
            tmdbPeople = []
            namedPeople = []
            describedItems = []
            discovery = nil
        }
        failures = []
        editedPlan = nil
        isDiscovery = discovers
        if let pick {
            discovery = pick
            editedPlan = pick
        }
        phase = .searching
        aiPhase = .searching
        aiStage = .interpreting
        aiIssue = nil
    }

    /// Results across all addons, grouped by content type: movie first, then series, then other types in order of first appearance.
    /// Within a group items keep addon order (the user's order) then the addon's own order; duplicates (same `identity`) appear once.
    public var groups: [Group] {
        var seen = Set<String>()
        var order: [String] = []
        var itemsByType: [String: [MetaPreview]] = [:]
        for section in sections {
            for item in section.items where seen.insert(item.identity).inserted {
                let type = Self.groupType(item.type)
                if itemsByType[type] == nil { order.append(type) }
                itemsByType[type, default: []].append(item)
            }
        }
        let leading = ["movie", "series"]
        let types = leading.filter { itemsByType[$0] != nil } + order.filter { !leading.contains($0) }
        return types.map { Group(type: $0, title: ContentTypeName.plural($0), items: itemsByType[$0] ?? []) }
    }

    /// Asks whether any enabled addon can search and whether TMDb can, and reads the browse genres. Call when the Search screen
    /// appears; every search checks again.
    public func refreshAvailability() async {
        recentQueries = Self.normalised(history.load())
        let addons = await services.browse.searchableAddons()
        hasSearchableAddons = !addons.isEmpty
        if includesAISearch, await services.settings.load().tmdbReadToken != nil { hasTMDb = true }
        let sources = await services.browse.catalogSources()
        categories = Self.categories(in: sources)
        availabilityLoaded = true
    }

    /// Forgets one recent search. Case-insensitive, like the de-duplication.
    public func removeRecent(_ query: String) {
        let key = Self.key(query)
        recentQueries.removeAll { Self.key($0) == key }
        history.save(recentQueries)
    }

    public func clearRecents() {
        recentQueries = []
        history.save([])
    }

    /// Call whenever the query changes. Old work is cancelled at once, stale answers are dropped, and the new search is debounced.
    public func queryDidChange() {
        let term = self.term
        if !term.isEmpty, activeTerm == term, phase == .searching || aiPhase == .searching { return }
        stopWork()
        guard !term.isEmpty else { reset(); return }
        begin(term, keepingResults: true)
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.run(term)
        }
    }

    /// The keyboard's Search button skips the debounce and asks for the full results.
    public func submit() async {
        guard !Task.isCancelled else { return }
        let term = self.term
        guard !term.isEmpty else { stopWork(); reset(); return }
        submittedTerm = term
        recentQueries = Self.recording(term, into: recentQueries)
        history.save(recentQueries)
        // Submitting while the same debounced search is already running must not restart expensive on-device inference.
        if activeTerm == term, phase == .searching || aiPhase == .searching {
            await task?.value
            return
        }
        stopWork()
        begin(term, keepingResults: true)
        let search = Task { [weak self] in
            guard let self else { return }
            await self.run(term)
        }
        task = search
        await withTaskCancellationHandler {
            await search.value
        } onCancel: {
            search.cancel()
        }
    }

    /// Test and accessibility helper: the addon search can finish before the described search.
    public func waitUntilDone() async {
        await task?.value
        await tmdbTask?.value
        await aiTask?.value
        await peopleTask?.value
        await genreTask?.value
    }

    private func reset() {
        stale = []
        resolvedGenres = [:]
        filter = SearchResultFilter()
        scope = .all
        sections = []
        failures = []
        tmdbTitles = []
        aliases = [:]
        votes = [:]
        tmdbPeople = []
        namedPeople = []
        describedItems = []
        discovery = nil
        editedPlan = nil
        isDiscovery = false
        submittedTerm = nil
        phase = .idle
        aiPhase = .idle
        aiIssue = nil
        activeTerm = nil
    }

    /// Loads the on-device model while Search is on screen, so a first described search does not wait for it to load.
    public func prewarmAI() {
        guard aiAvailable else { return }
        Task.detached(priority: .utility) { OnDeviceDescriptionInterpreter.prewarm() }
    }

    /// Retries only the described search, keeping the other results. An edited plan is searched again as edited.
    public func retryAI() {
        let term = self.term
        guard !term.isEmpty else { return }
        aiPhase = .searching
        searchAI(term, plan: editedPlan)
    }

    /// The described search beside the others. It reads words that could be a title, and plain filters, without the on-device model
    /// (see `DescribedSearchService.titles`); a plan given here is searched as it stands.
    private func searchAI(_ term: String, plan: AISearchPlan? = nil) {
        aiTask?.cancel()
        guard includesAISearch else {
            if stale.remove(.described) != nil { describedItems = [] }
            aiPhase = .done
            return
        }
        let describer = describer
        let requestID = UUID()
        aiRequestID = requestID
        aiStage = .interpreting
        aiIssue = nil
        aiTask = Task { [weak self] in
            // Give title results a head start and avoid starting inference between keystrokes. A changed chip is searched at once.
            if plan == nil {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let items = await describer.titles(for: term, plan: plan) { [weak self] update in
                guard !Task.isCancelled else { return }
                await self?.applyAIUpdate(update, term: term, requestID: requestID)
            }
            guard !Task.isCancelled, let self, self.aiRequestID == requestID, self.term == term else { return }
            self.stale.remove(.described)
            self.describedItems = items
            self.remember(items, [])
            self.aiStage = .complete
            self.aiPhase = .done
        }
    }

    private func applyAIUpdate(_ update: AISearchUpdate, term: String, requestID: UUID) {
        guard aiRequestID == requestID, self.term == term else { return }
        // The service emits stage updates before and after a batch; avoid re-rendering identical result cards. The last words'
        // titles stay until this search has titles of its own, or has finished.
        if !stale.contains(.described) || !update.items.isEmpty || update.stage == .complete {
            stale.remove(.described)
            if describedItems != update.items { describedItems = update.items }
        }
        if aiStage != update.stage { aiStage = update.stage }
        if aiIssue != update.issue { aiIssue = update.issue }
        if let plan = update.plan, discovery != plan {
            discovery = plan
            namedPeople.removeAll { person in !plan.people.contains { $0.name == person.name } }
            findNamedPeople(plan.people.map(\.name), term: term)
        }
    }

    /// The people a described search names, as cards that open their pages. Three at most, as the plan holds.
    private func findNamedPeople(_ names: [String], term: String) {
        let missing = names.filter { name in !namedPeople.contains { $0.name == name } }
        guard isDiscovery, !missing.isEmpty else { return }
        peopleTask?.cancel()
        let universal = universal
        peopleTask = Task { [weak self] in
            for name in missing {
                let found = (try? await universal(name))?.people.first { SearchResults.isSameName($0.name, name) }
                guard !Task.isCancelled, let self, self.term == term else { return }
                if let found, !self.namedPeople.contains(where: { $0.id == found.id }),
                   self.discovery?.people.contains(where: { $0.name == name }) == true {
                    self.namedPeople.append(found)
                }
            }
        }
    }

    /// TMDb's titles and people for the words as a name, beside the addons. Without a token, offline or refused, the addons'
    /// results stand alone: nothing here is an error of its own.
    private func searchTMDb(_ term: String) -> Task<Void, Never> {
        tmdbTask?.cancel()
        let universal = universal
        let task = Task { [weak self] in
            let hits = try? await universal(term)
            guard !Task.isCancelled, let self, self.term == term else { return }
            self.stale.remove(.tmdb)
            guard let hits else {
                self.tmdbTitles = []
                self.aliases = [:]
                self.votes = [:]
                self.tmdbPeople = []
                return
            }
            self.hasTMDb = true
            self.tmdbTitles = hits.titles
            self.aliases = hits.originalNames
            self.votes = hits.votes
            self.tmdbPeople = hits.people
            self.remember(hits.titles, hits.people)
        }
        tmdbTask = task
        return task
    }

    private func run(_ term: String) async {
        guard !Task.isCancelled, self.term == term else { return }
        activeTerm = term
        if isPickSearch, let pickPlan {
            // Pick for me asks for what its choices describe, never for titles or people named like its words.
            searchAI(term, plan: pickPlan)
            if !availabilityLoaded { await refreshAvailability() }
            guard !Task.isCancelled else { return }
            phase = .done
            return
        }
        searchAI(term)
        let tmdb = searchTMDb(term)
        if !availabilityLoaded { await refreshAvailability() }
        guard !Task.isCancelled else { return }
        if hasSearchableAddons {
            let order = await services.registry.addons.map(\.id)
            let stream = await services.browse.search(term, incremental: true)
            for await response in stream {
                guard !Task.isCancelled else { return }
                switch response.result {
                case .success(let items):
                    if stale.remove(.addons) != nil { sections = [] }
                    insert(Section(addon: response.addon, items: items), order: order)
                    remember(items, [])
                case .failure(let error):
                    failures.append(Failure(addon: response.addon, error: error))
                }
            }
        }
        if stale.remove(.addons) != nil { sections = [] }
        await withTaskCancellationHandler {
            await tmdb.value
        } onCancel: {
            tmdb.cancel()
        }
        guard !Task.isCancelled else { return }
        phase = .done
    }

    /// Keeps what was found for the suggestions of later words: the newest first, each once, a bounded number.
    private func remember(_ titles: [MetaPreview], _ people: [TMDbTitlePerson]) {
        let fresh = titles.filter { Self.groupType($0.type) != "library" }
        if !fresh.isEmpty {
            let identities = Set(fresh.map(\.identity))
            knownTitles = Array((fresh + knownTitles.filter { !identities.contains($0.identity) }).prefix(240))
        }
        if !people.isEmpty {
            let ids = Set(people.map(\.id))
            knownPeople = Array((people + knownPeople.filter { !ids.contains($0.id) }).prefix(60))
        }
    }

    /// Reads the recents again, for when a title was opened from Search and its name was recorded (see `recording(_:into:)`).
    public func reloadRecents() {
        recentQueries = Self.normalised(history.load())
    }

    /// The recents with a title added at the top, in place of an older copy of it. A title opened from Search is what is recorded, not
    /// the letters typed on the way to it.
    public static func recording(_ title: String, into queries: [String]) -> [String] {
        normalised([title] + queries)
    }

    /// Keeps sections in the user's addon order, whatever order the addons answer in.
    private func insert(_ section: Section, order: [UUID]) {
        // Addon library entries are raw files, so keep them out of Search's title results.
        let section = Section(addon: section.addon, items: section.items.filter { Self.groupType($0.type) != "library" })
        if let index = sections.firstIndex(where: { $0.id == section.id }) {
            sections[index] = section
            return
        }
        func rank(_ id: UUID) -> Int { order.firstIndex(of: id) ?? Int.max }
        let index = sections.firstIndex { rank($0.addon.id) > rank(section.addon.id) } ?? sections.endIndex
        sections.insert(section, at: index)
    }

    /// The grouping key for an item's type: lower-case and trimmed, "other" when the addon sent no type.
    private static func groupType(_ type: String) -> String {
        let key = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? "other" : key
    }

    /// The same genres and candidate catalogs as Discover, with provider spellings preserved in each reference.
    static func categories(in sources: [CatalogSource]) -> [GenreShortcut] {
        let names = DiscoverViewModel.genres(of: sources.map(\.catalog))
        return names.map { name in
            let matching = sources.compactMap { source -> WidgetSource? in
                let options = MediaGenres.options(of: source.catalog)
                guard options.isEmpty || MediaGenres.option(name, in: source.catalog) != nil else { return nil }
                return .addonCatalog(AddonCatalogReference(manifestID: nil, host: source.addon.host,
                    catalogType: source.catalog.type, catalogID: source.catalog.id, genre: name))
            }
            return GenreShortcut(name: name, sources: matching, imageURL: GenreArtwork.imageURL(for: name))
        }
    }

    /// Recent searches as stored: trimmed, no blanks, one copy of each (the first one kept), at most 8.
    private static func normalised(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for query in queries {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, seen.insert(key(term)).inserted else { continue }
            result.append(term)
            if result.count == maxRecents { break }
        }
        return result
    }

    /// How two recent searches are compared: case-insensitively.
    private static func key(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

