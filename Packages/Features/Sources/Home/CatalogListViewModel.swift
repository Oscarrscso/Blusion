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

/// The grid behind "See All", a collection tile or a genre. One source pages 50 at a time; several sources load once, merged.
@MainActor
@Observable
final class CatalogListViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case loadingMore
        case failed(WidgetSourceError)
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
    /// Raw items received so far: the protocol's `skip` counts what the addon sent, not what is left after de-duplication.
    private var receivedCount = 0

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

    /// Loads the first page, or the merged list for several sources. Items already on screen stay until the new ones arrive.
    func load() async {
        genreTask?.cancel()
        genreResolved = []
        generation += 1
        let current = generation
        let sources = request.sources
        receivedCount = 0
        canLoadMore = false
        state = .loading
        guard !sources.isEmpty else {
            items = []
            visibleItems = []
            state = .loaded
            return
        }
        do {
            let page: [MetaPreview]
            let nextSkip: Int
            let hasMore: Bool
            if sources.count == 1 {
                let loaded = try await services.widgetContent.page(for: sources[0], limit: CatalogListViewModel.pageSize, skip: 0)
                page = loaded.items
                nextSkip = loaded.nextSkip
                hasMore = loaded.hasMore
            } else {
                page = try await services.widgetContent.items(for: sources, limit: CatalogListViewModel.mergedLimit)
                nextSkip = 0
                hasMore = false
            }
            guard current == generation else { return }
            items = CatalogListViewModel.appending(page, to: [])
            shuffleRank = [:]
            rankNewItems()
            refreshVisible()
            receivedCount = nextSkip
            canLoadMore = hasMore
            resolveGenres()
            state = .loaded
        } catch {
            guard current == generation else { return }
            state = .failed(CatalogListViewModel.widgetError(error))
        }
    }

    /// Call when the last item scrolls into view. Does nothing while a load runs, after an empty page, or for several sources.
    func loadMore() async {
        let sources = request.sources
        guard canLoadMore, state == .loaded, sources.count == 1, let source = sources.first else { return }
        let current = generation
        state = .loadingMore
        do {
            let page = try await services.widgetContent.page(for: source, limit: CatalogListViewModel.pageSize, skip: receivedCount)
            guard current == generation else { return }
            receivedCount = page.nextSkip
            let before = items.count
            items = CatalogListViewModel.appending(page.items, to: items)
            rankNewItems()
            refreshVisible()
            canLoadMore = page.hasMore && items.count > before
            resolveGenres()
            state = .loaded
        } catch {
            guard current == generation else { return }
            // Keeps what is there; scrolling to the end again tries the page once more.
            state = .loaded
        }
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

    /// Keeps each title once across pages.
    private static func appending(_ page: [MetaPreview], to list: [MetaPreview]) -> [MetaPreview] {
        var seen = Set(list.map(\.identity))
        return list + page.filter { seen.insert($0.identity).inserted }
    }

    private static func widgetError(_ error: Error) -> WidgetSourceError {
        (error as? WidgetSourceError) ?? .addon(AddonError.from(error))
    }
}
