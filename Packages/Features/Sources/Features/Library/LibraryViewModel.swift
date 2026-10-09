import Foundation
import Observation
import PlayerKit
import StremioKit

/// Library: saved titles and what has been watched. The filter narrows both sections at once. In-progress titles live on Home.
@MainActor
@Observable
public final class LibraryViewModel {
    /// How many titles a grid adds each time the viewer scrolls near its end, and how close to the end that has to be.
    static let pageSize = 60
    private static let prefetchDistance = 12

    /// The sections as the view shows them: each already filtered, sorted and cut to the pages loaded so far.
    public private(set) var saved: [LibraryItem] = []
    public private(set) var watched: [WatchProgress] = []
    public private(set) var hasLoaded = false

    /// The filters and sort in use. Changing it re-filters the sections at once and starts each grid from its first page.
    public var filter = LibraryFilter() {
        didSet {
            savedLimit = Self.pageSize
            watchedLimit = Self.pageSize
            applyFilter()
        }
    }

    private let services: AppServices
    /// Everything the Library knows, before any filter. The sections above are the visible part of these.
    private var savedEntries: [LibraryEntry] = []
    private var watchedEntries: [LibraryEntry] = []
    private var visibleSaved: [LibraryEntry] = []
    private var visibleWatched: [LibraryEntry] = []
    /// How many of each grid's filtered titles are shown.
    private var savedLimit = LibraryViewModel.pageSize
    private var watchedLimit = LibraryViewModel.pageSize
    private var lastTraktPull = Date.distantPast
    /// Where the scores from the rating sites other than IMDb come from. Nil until the view attaches it.
    @ObservationIgnored private var ratings: PosterRatingsStore?

    public init(services: AppServices) {
        self.services = services
    }

    /// Lets the rating filter look up Letterboxd, Rotten Tomatoes and Metacritic scores. Titles re-filter as each score arrives.
    public func attachRatings(_ store: PosterRatingsStore?) {
        ratings = store
        applyFilter()
    }

    /// True when the Library holds nothing at all, whatever the filter. A filter that matches nothing is not empty.
    public var isEmpty: Bool { savedEntries.isEmpty && watchedEntries.isEmpty }

    /// True when at least one section has a title to show under the current filter.
    public var hasMatches: Bool { !(saved.isEmpty && watched.isEmpty) }

    /// Whether each grid has titles past the pages on screen.
    public var hasMoreSaved: Bool { visibleSaved.count > savedLimit }
    public var hasMoreWatched: Bool { visibleWatched.count > watchedLimit }

    /// The genres and year span of everything in the Library, for the filter's pickers.
    public var availableGenres: [String] { LibraryFiltering.genres(in: savedEntries + watchedEntries) }

    /// An empty library can recover from a missed Trakt import without signing in again.
    public func refresh(now: Date = Date()) async {
        await load()
        guard isEmpty, await services.traktAccount.isSignedIn(), now.timeIntervalSince(lastTraktPull) >= 300 else { return }
        lastTraktPull = now
        await TraktAccountViewModel(services: services).importFromTrakt()
        await load()
    }

    public func load() async {
        let all = await services.progress.all()
        let savedItems = await services.library.all()
        let savedByID = Dictionary(savedItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recordsByTitle = Dictionary(grouping: all, by: Self.titleKey(of:))

        savedEntries = savedItems.map { LibraryEntry(item: $0, records: recordsByTitle[$0.id] ?? []) }
        watchedEntries = all.filter(\.isWatched).map { record in
            LibraryEntry(record: record, saved: savedByID[Self.titleKey(of: record)])
        }
        hasLoaded = true
        applyFilter()
    }

    /// In-progress items worth resuming, newest first, one per series (the latest episode). Home's Continue Watching uses this.
    public static func continueWatching(from all: [WatchProgress]) -> [WatchProgress] {
        var seenSeries = Set<String>()
        return all.filter { !$0.isWatched && ProgressRecorder.resumePosition(for: $0) > 0 }
            .filter { item in
                guard let series = item.seriesID else { return true }
                return seenSeries.insert(series).inserted
            }
    }

    /// Called as a Saved card appears. Near the end of the loaded page, the next page is shown.
    public func savedCardAppeared(_ id: String) {
        guard hasMoreSaved, Self.isNearEnd(id, of: saved.map(\.id)) else { return }
        savedLimit += Self.pageSize
        publishSections()
    }

    /// Called as a Watched card appears. Near the end of the loaded page, the next page is shown.
    public func watchedCardAppeared(_ id: String) {
        guard hasMoreWatched, Self.isNearEnd(id, of: watched.map(\.id)) else { return }
        watchedLimit += Self.pageSize
        publishSections()
    }

    public func markUnwatched(_ item: WatchProgress) async {
        await services.progress.remove(item.id)
        await load()
    }

    public func removeSaved(_ item: LibraryItem) async {
        await services.library.remove(item.id)
        await load()
    }

    /// Clears every filter, keeping the sort.
    public func clearFilters() {
        filter.clearFilters()
    }

    /// Clears the filter one chip stands for.
    public func removeFilter(_ chip: FilterChip) {
        filter.remove(chip.target)
    }

    /// What tapping an in-progress item plays; the player resumes from the saved position.
    nonisolated public static func request(for progress: WatchProgress) -> StreamRequest {
        StreamRequest(type: progress.type, id: progress.contentID, title: progress.title, poster: progress.poster,
                      season: progress.season, episode: progress.episode)
    }

    /// The saved title a progress record belongs to: its type and series id (the episode's series for a series).
    private static func titleKey(of record: WatchProgress) -> String {
        LibraryItem.identity(type: record.type, contentID: record.seriesID ?? record.contentID)
    }

    private func applyFilter() {
        let now = Date()
        let filter = filter
        let (savedEntries, watchedEntries) = (self.savedEntries, self.watchedEntries)
        let score = scoreLookup(for: filter)
        // Reading each title's score inside the tracking block means a score that arrives later re-runs the filter on its own.
        let (visibleSaved, visibleWatched) = withObservationTracking {
            (LibraryFiltering.apply(filter, to: savedEntries, now: now, score: score),
             LibraryFiltering.apply(filter, to: watchedEntries, now: now, score: score))
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyFilter() }
        }
        self.visibleSaved = visibleSaved
        self.visibleWatched = visibleWatched
        publishSections()
    }

    /// Cuts each filtered list to the pages loaded so far.
    private func publishSections() {
        saved = visibleSaved.prefix(savedLimit).compactMap(\.item)
        watched = visibleWatched.prefix(watchedLimit).compactMap(\.progress)
    }

    /// True when the card is one of the last few on the loaded page, so the next page should load.
    private static func isNearEnd(_ id: String, of ids: [String]) -> Bool {
        guard let index = ids.firstIndex(of: id) else { return false }
        return index >= ids.count - prefetchDistance
    }

    /// Every site's score for a title comes from the rating store, which starts a lookup for it if it has none yet. Without a
    /// threshold no score is needed, so nothing is looked up.
    private func scoreLookup(for filter: LibraryFilter) -> LibraryFiltering.ScoreLookup {
        guard filter.minimumRating != nil, let store = ratings else { return LibraryFiltering.catalogueScores }
        return { entry, source in store.ratings(for: entry.preview).score(for: source) }
    }
}
