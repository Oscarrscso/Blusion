import Foundation
import Observation
import StremioKit

/// What a grid screen shows: a title, the sources its items come from and how its cards look. A navigation value.
struct CatalogListRequest: Hashable, Sendable {
    var title: String
    var sources: [WidgetSource]
    var presentation: WidgetPresentation

    init(title: String, sources: [WidgetSource], presentation: WidgetPresentation = WidgetPresentation()) {
        self.title = title
        self.sources = sources
        self.presentation = presentation
    }
}

/// The grid behind "See All", a collection tile, a genre or a search category. Pages each source 50 items at a time, interleaving and
/// deduplicating across sources as the user scrolls.
@MainActor
@Observable
final class CatalogListViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case loadingMore
        case failed(WidgetSourceError)
    }

    private struct SourceCursor {
        let source: WidgetSource
        var nextSkip = 0
        var hasMore = true
        var emptyRounds = 0
    }

    let request: CatalogListRequest
    private(set) var items: [MetaPreview] = []
    private(set) var state: State = .loading
    private(set) var canLoadMore = false
    /// Loaded, and nothing to show. A failed load is not empty.
    var isEmpty: Bool { state == .loaded && items.isEmpty }

    /// The order and narrowing the grid shows. The order is remembered for this list's title; the narrowing starts clear each visit.
    var filter = CatalogListFilter() {
        didSet {
            if filter.sort != oldValue.sort {
                if filter.sort == .shuffle { reshuffle() }
                defaults.set(filter.sort.rawValue, forKey: sortKey)
            }
            refreshVisible()
        }
    }
    /// The loaded titles that pass `filter`, in its order. The grid draws these.
    private(set) var visibleItems: [MetaPreview] = []
    /// The types among the loaded titles, so the type selector shows only when there is a choice to make.
    var loadedTypes: Set<String> { Set(items.map { $0.type.lowercased() }) }
    /// Whether the sources hold movies and series together, so the type selector is in place while the first page loads.
    var expectsMixedTypes: Bool {
        var types = Set<String>()
        for source in request.sources {
            switch source {
            case .addonCatalog(let reference): types.insert(reference.catalogType.lowercased())
            case .tmdbDiscover(let query):
                if query.spansBothKinds { return true }
                types.insert(query.kind == .movie ? "movie" : "series")
            case .traktList, .traktFeed, .unsupported: break
            }
        }
        return types.isSuperset(of: ["movie", "series"])
    }
    /// The Genre menu's choices: the genres the loaded titles' own pages list, one of each, A to Z, with the chosen one always among
    /// them. Years and orders are left out.
    var loadedGenres: [String] {
        let listed = items.flatMap(\.genres).filter { !DiscoverViewModel.isYear($0) && !DiscoverViewModel.isOrder($0) }
        return MediaGenres.choices(in: listed + (filter.genre.map { [$0] } ?? []))
    }
    private var shuffleRank: [String: Int] = [:]
    @ObservationIgnored private var ratingsTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private var sortKey: String { "catalogList.sort.\(request.title)" }

    nonisolated static let pageSize = 50
    nonisolated static let mergedLimit = 100

    private let services: AppServices
    private var generation = 0
    private var genreTask: Task<Void, Never>?
    /// The loaded titles whose genres are already the ones their pages list.
    private var genreResolved: Set<String> = []
    /// Per-source pagination state: each source tracks its own raw `skip` cursor, exhaustion, and consecutive duplicate-only rounds.
    private var cursors: [SourceCursor] = []

    init(request: CatalogListRequest, services: AppServices, defaults: UserDefaults = .standard) {
        self.request = request
        self.services = services
        self.defaults = defaults
        // Shuffle is no longer offered, so a list remembered as shuffled opens in its own order.
        if let saved = defaults.string(forKey: "catalogList.sort.\(request.title)").flatMap(CatalogListSort.init(rawValue:)), saved != .shuffle {
            filter.sort = saved
        }
    }

    /// A new random order of everything loaded. Choosing Shuffle again, or its button, calls this.
    func reshuffle() {
        var generator = SystemRandomNumberGenerator()
        shuffleRank = CatalogListFiltering.shuffleRanks(for: items, using: &generator)
        refreshVisible()
    }

    /// When the filter leaves fewer titles than fill a screen, pages are fetched until it does or the source runs out, a few at most, so a
    /// narrow filter over a long list still shows what the list holds.
    func fillForFilter() async {
        var fetched = 0
        while filter.isFiltering, visibleItems.count < 24, canLoadMore, state == .loaded, fetched < 5 {
            fetched += 1
            await loadMore()
        }
    }

    private func refreshVisible() {
        let (filter, items, shuffleRank) = (filter, items, shuffleRank)
        let rating = ratingLookup(for: filter)
        // Reading each title's score inside the tracking block means a score that arrives later re-runs the filter on its own.
        visibleItems = withObservationTracking {
            CatalogListFiltering.apply(filter, to: items, shuffleRank: shuffleRank, rating: rating)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ratingsTask?.cancel()
                self.ratingsTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    self?.refreshVisible()
                }
            }
        }
    }

    /// Scores come from the rating store, which looks up the ones a title lacks. Without a threshold or Top Rated no score is needed.
    private func ratingLookup(for filter: CatalogListFilter) -> CatalogListFiltering.RatingLookup {
        guard filter.minimumRating != nil || filter.sort == .rating else { return JudgedRating.catalogue }
        let store = services.posterRatings
        return { item in store.judgedRating(for: item) ?? JudgedRating.catalogue(item) }
    }

    /// New titles join the shuffle after the ones already placed, shuffled among themselves, so the grid never reorders under the reader.
    private func rankNewItems() {
        guard filter.sort == .shuffle else { return }
        let fresh = items.filter { shuffleRank[$0.identity] == nil }
        guard !fresh.isEmpty else { return }
        var generator = SystemRandomNumberGenerator()
        shuffleRank.merge(CatalogListFiltering.shuffleRanks(for: fresh, from: shuffleRank.count, using: &generator)) { old, _ in old }
    }

    /// Refresh must ask the sources again, even when their cached page has not expired.
    func refresh() async {
        await services.posterRatings.refresh()
        await services.widgetContent.invalidate()
        await load()
    }

    /// Loads the first page across all sources. Items already on screen stay until the new ones arrive.
    func load() async {
        genreTask?.cancel()
        genreResolved = []
        generation += 1
        let current = generation
        let sources = request.sources
        cursors = sources.map { SourceCursor(source: $0) }
        canLoadMore = false
        state = .loading
        guard !sources.isEmpty else {
            items = []
            visibleItems = []
            state = .loaded
            return
        }
        do {
            let fetched = try await fetchNextRound(initial: true)
            guard current == generation else { return }
            items = Self.appending(fetched, to: [])
            shuffleRank = [:]
            rankNewItems()
            refreshVisible()
            canLoadMore = cursors.contains(where: \.hasMore)
            resolveGenres()
            state = .loaded
        } catch {
            guard current == generation else { return }
            state = .failed(Self.widgetError(error))
        }
    }

    /// Call when the last item scrolls into view. Does nothing while a load runs or once all sources are exhausted.
    func loadMore() async {
        guard canLoadMore, state == .loaded, !cursors.isEmpty else { return }
        let current = generation
        state = .loadingMore
        let before = items.count
        do {
            while cursors.contains(where: \.hasMore) {
                let fetched = try await fetchNextRound(initial: false)
                guard current == generation else { return }
                items = Self.appending(fetched, to: items)
                if items.count > before || !cursors.contains(where: \.hasMore) {
                    break
                }
            }
            guard current == generation else { return }
            rankNewItems()
            refreshVisible()
            canLoadMore = cursors.contains(where: \.hasMore)
            resolveGenres()
            state = .loaded
        } catch {
            guard current == generation else { return }
            // Keeps what is there; scrolling to the end again tries the page once more.
            if items.count > before {
                rankNewItems()
                refreshVisible()
                resolveGenres()
            }
            canLoadMore = cursors.contains(where: \.hasMore)
            state = .loaded
        }
    }

    /// Fetches one page concurrently from each source whose cursor still has more, updates cursor state, and interleaves the results.
    private func fetchNextRound(initial: Bool) async throws -> [MetaPreview] {
        let current = generation
        let active = cursors.enumerated().filter { $0.element.hasMore }.map { ($0.offset, $0.element) }
        guard !active.isEmpty else { return [] }
        let content = services.widgetContent
        let limit = Self.pageSize
        let outcomes = await withTaskGroup(
            of: (Int, Result<WidgetContentService.Page, WidgetSourceError>).self,
            returning: [(Int, Result<WidgetContentService.Page, WidgetSourceError>)].self
        ) { group in
            for (index, cursor) in active {
                let source = cursor.source
                let skip = cursor.nextSkip
                group.addTask {
                    do {
                        let page = try await content.page(for: source, limit: limit, skip: skip)
                        return (index, .success(page))
                    } catch {
                        return (index, .failure(CatalogListViewModel.widgetError(error)))
                    }
                }
            }
            var collected: [(Int, Result<WidgetContentService.Page, WidgetSourceError>)] = []
            for await outcome in group { collected.append(outcome) }
            return collected.sorted { $0.0 < $1.0 }
        }
        guard current == generation else { return [] }

        var nextCursors = cursors
        var seen = initial ? Set<String>() : Set(items.map(\.identity))
        var lists: [[MetaPreview]] = []
        var firstError: WidgetSourceError?

        for (index, outcome) in outcomes {
            switch outcome {
            case .failure(let error):
                firstError = firstError ?? error
                nextCursors[index].hasMore = false
            case .success(let page):
                let previousSkip = nextCursors[index].nextSkip
                nextCursors[index].nextSkip = page.nextSkip
                var contributedNew = false
                for item in page.items {
                    if seen.insert(item.identity).inserted {
                        contributedNew = true
                    }
                }
                if page.items.isEmpty || !page.hasMore || page.nextSkip <= previousSkip {
                    nextCursors[index].hasMore = false
                } else if !contributedNew {
                    nextCursors[index].emptyRounds += 1
                    if nextCursors.count == 1 || nextCursors[index].emptyRounds >= 2 {
                        nextCursors[index].hasMore = false
                    }
                } else {
                    nextCursors[index].emptyRounds = 0
                    nextCursors[index].hasMore = true
                }
                lists.append(page.items)
            }
        }

        if lists.isEmpty, let firstError {
            throw firstError
        }

        cursors = nextCursors
        return Self.interleave(lists)
    }

    /// Gives the loaded titles the genres their own pages list, the same facts as Discover and Detail, so the Genre menu and its filter
    /// agree with a title's Information.
    private func resolveGenres() {
        genreTask?.cancel()
        let pending = items.filter { !genreResolved.contains($0.identity) }
        guard !pending.isEmpty else { return }
        let current = generation
        genreTask = Task { [weak self] in
            guard let browse = self?.services.browse else { return }
            let resolved = await browse.resolvingGenres(in: pending)
            guard let self, !Task.isCancelled, self.generation == current else { return }
            let genres = Dictionary(resolved.map { ($0.identity, $0.genres) }, uniquingKeysWith: { first, _ in first })
            // A title whose page could not be read comes back without genres, and is asked again with the next page.
            self.genreResolved.formUnion(genres.filter { !$0.value.isEmpty }.keys)
            self.items = self.items.map { item in
                var copy = item
                if let value = genres[item.identity] { copy.genres = value }
                return copy
            }
            self.refreshVisible()
        }
    }

    /// Interleaves source lists round-robin (position 0 of each list, then position 1, etc.), keeping the first occurrence of each identity.
    private static func interleave(_ lists: [[MetaPreview]]) -> [MetaPreview] {
        var seen = Set<String>()
        var merged: [MetaPreview] = []
        let longest = lists.map(\.count).max() ?? 0
        for position in 0..<longest {
            for list in lists where position < list.count {
                let item = list[position]
                guard seen.insert(item.identity).inserted else { continue }
                merged.append(item)
            }
        }
        return merged
    }

    /// Keeps each title once across pages.
    private static func appending(_ page: [MetaPreview], to list: [MetaPreview]) -> [MetaPreview] {
        var seen = Set(list.map(\.identity))
        return list + page.filter { seen.insert($0.identity).inserted }
    }

    nonisolated private static func widgetError(_ error: Error) -> WidgetSourceError {
        (error as? WidgetSourceError) ?? .addon(AddonError.from(error))
    }
}
