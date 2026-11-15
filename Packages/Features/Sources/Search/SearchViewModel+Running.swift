import Foundation
import Observation
import StremioKit

extension SearchViewModel {
    // MARK: Running a search

    func stopWork() {
        task?.cancel()
        genreTask?.cancel()
        isResolvingGenres = false
        tmdbTask?.cancel()
        aiTask?.cancel()
        peopleTask?.cancel()
        aiRequestID = UUID()
        activeTerm = nil
    }

    func cancel() {
        stopWork()
        if phase == .searching { phase = .idle }
        if aiPhase == .searching { aiPhase = .idle }
    }

    /// Marks both searches as running. `keepingResults` leaves what the last words found on screen, each source's results replaced
    /// when it answers the new words, so typing never blanks the page; a change between a name and a description clears at once.
    func begin(_ term: String, keepingResults: Bool = false) {
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
    var groups: [Group] {
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
    func refreshAvailability() async {
        recentQueries = Self.normalised(history.load())
        let addons = await services.browse.searchableAddons()
        hasSearchableAddons = !addons.isEmpty
        if includesAISearch, await services.settings.load().tmdbReadToken != nil { hasTMDb = true }
        let sources = await services.browse.catalogSources()
        categories = Self.categories(in: sources)
        availabilityLoaded = true
    }

    /// Forgets one recent search. Case-insensitive, like the de-duplication.
    func removeRecent(_ query: String) {
        let key = Self.key(query)
        recentQueries.removeAll { Self.key($0) == key }
        history.save(recentQueries)
    }

    func clearRecents() {
        recentQueries = []
        history.save([])
    }

    /// Call whenever the query changes. Old work is cancelled at once, stale answers are dropped, and the new search is debounced.
    func queryDidChange() {
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
    func submit() async {
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
    func waitUntilDone() async {
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
    func prewarmAI() {
        guard aiAvailable else { return }
        Task.detached(priority: .utility) { OnDeviceDescriptionInterpreter.prewarm() }
    }

    /// Retries only the described search, keeping the other results. An edited plan is searched again as edited.
    func retryAI() {
        let term = self.term
        guard !term.isEmpty else { return }
        aiPhase = .searching
        searchAI(term, plan: editedPlan)
    }

    /// The described search beside the others. It reads words that could be a title, and plain filters, without the on-device model
    /// (see `DescribedSearchService.titles`); a plan given here is searched as it stands.
    func searchAI(_ term: String, plan: AISearchPlan? = nil) {
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

    func run(_ term: String) async {
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
        let fresh = titles.filter { !SearchResults.isExcludedAddonItem($0) }
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
    func reloadRecents() {
        recentQueries = Self.normalised(history.load())
    }

    /// The recents with a title added at the top, in place of an older copy of it. A title opened from Search is what is recorded, not
    /// the letters typed on the way to it.
    static func recording(_ title: String, into queries: [String]) -> [String] {
        normalised([title] + queries)
    }

    /// Keeps sections in the user's addon order, whatever order the addons answer in.
    private func insert(_ section: Section, order: [UUID]) {
        // Addon library entries and synthetic Easynews search placeholders are not playable titles, so keep them out of Search.
        let section = Section(addon: section.addon, items: section.items.filter { !SearchResults.isExcludedAddonItem($0) })
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
    static func normalised(_ queries: [String]) -> [String] {
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
    static func key(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
