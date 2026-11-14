import Foundation
import Observation
import PlayerKit
import StremioKit

/// Library: saved titles and what has been watched. The filter narrows both sections at once.
@MainActor
@Observable
public final class LibraryViewModel {
    /// The sections as the view shows them: each already filtered and sorted. Watched has one card per movie and one per show.
    public private(set) var saved: [LibraryItem] = []
    public private(set) var watched: [WatchedCard] = []
    public private(set) var hasLoaded = false

    /// The filters and sort in use. Changing it re-filters the sections at once.
    public var filter = LibraryFilter() {
        didSet { applyFilter() }
    }
    /// True while the page shows the device's downloads in place of the Library's titles. Downloads keep their own filter (`downloadFilter`),
    /// so switching between the two never changes either selection.
    public var showsDownloads = false
    public var downloadFilter = DownloadFilter()

    private let services: AppServices
    /// Everything the Library knows, before any filter. The sections above are the visible part of these.
    private var savedEntries: [LibraryEntry] = []
    private var watchedEntries: [LibraryEntry] = []
    private var visibleSaved: [LibraryEntry] = []
    private var visibleWatched: [LibraryEntry] = []
    private var lastTraktPull = Date.distantPast
    /// Bumped by each load, so one that read before a later change can't overwrite what the later load shows.
    @ObservationIgnored private var loadGeneration = 0
    /// Where the scores from the rating sites other than IMDb come from. Nil until the view attaches it.
    @ObservationIgnored private var ratings: PosterRatingsStore?
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    /// The genres each title's own page lists, by the title's identity. Saved titles keep whatever their catalog said when they were
    /// saved, and a watched title that was never saved has none.
    @ObservationIgnored private var titleGenres: [String: [String]] = [:]
    @ObservationIgnored private var genreTask: Task<Void, Never>?

    public init(services: AppServices) {
        self.services = services
    }

    /// Lets the rating filter and the Rating sort look up Letterboxd, MyAnimeList and TMDb scores. Titles re-filter as each score arrives.
    public func attachRatings(_ store: PosterRatingsStore?) {
        ratings = store
        applyFilter()
    }

    /// True when the Library holds nothing at all, whatever the filter. A filter that matches nothing is not empty.
    public var isEmpty: Bool { savedEntries.isEmpty && watchedEntries.isEmpty }

    /// True when at least one section has a title to show under the current filter.
    public var hasMatches: Bool { !(saved.isEmpty && watched.isEmpty) }

    /// The genres and year span of everything in the Library, for the filter's pickers.
    public var availableGenres: [String] { LibraryFiltering.genres(in: savedEntries + watchedEntries) }
    public var availableYears: ClosedRange<Int>? { LibraryFiltering.yearRange(in: savedEntries + watchedEntries) }

    /// An empty library can recover from a missed Trakt import without signing in again.
    public func refresh(now: Date = Date()) async {
        await load()
        guard isEmpty, await services.traktAccount.isSignedIn(), now.timeIntervalSince(lastTraktPull) >= 300 else { return }
        lastTraktPull = now
        _ = try? await services.traktSync.sync(force: true)
        await load()
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let all = await services.progress.all()
        let savedItems = await services.library.all()
        guard generation == loadGeneration else { return }
        let savedByID = Dictionary(savedItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recordsByTitle = Dictionary(grouping: all, by: Self.titleKey(of:))

        savedEntries = savedItems.map { LibraryEntry(item: $0, records: recordsByTitle[$0.id] ?? []) }
        watchedEntries = all.filter(\.isWatched).map { record in
            LibraryEntry(record: record, saved: savedByID[Self.titleKey(of: record)])
        }
        applyTitleGenres()
        hasLoaded = true
        applyFilter()
        resolveGenres()
    }

    private func applyTitleGenres() {
        func updated(_ entries: [LibraryEntry]) -> [LibraryEntry] {
            entries.map { entry in
                guard let genres = titleGenres[entry.preview.identity], genres != entry.genres else { return entry }
                var copy = entry
                copy.genres = genres
                return copy
            }
        }
        savedEntries = updated(savedEntries)
        watchedEntries = updated(watchedEntries)
    }

    /// Looks up the genres of the titles not yet checked, the same facts as a title's Information, then filters again.
    private func resolveGenres() {
        genreTask?.cancel()
        var seen = Set(titleGenres.keys)
        let pending = (savedEntries + watchedEntries).map(\.preview).filter { seen.insert($0.identity).inserted }
        guard !pending.isEmpty else { return }
        genreTask = Task { [weak self] in
            guard let browse = self?.services.browse else { return }
            let resolved = await browse.resolvingGenres(in: pending)
            guard let self, !Task.isCancelled else { return }
            // A title without genres is asked again on the next load, in case its lookup failed.
            for item in resolved where !item.genres.isEmpty { self.titleGenres[item.identity] = item.genres }
            self.applyTitleGenres()
            self.applyFilter()
        }
    }

    /// In-progress items worth resuming, newest first, one per series (the latest episode).
    public static func continueWatching(from all: [WatchProgress]) -> [WatchProgress] {
        var seenSeries = Set<String>()
        return all.filter { item in
            guard let series = item.seriesID else { return true }
            return seenSeries.insert(series).inserted
        }
            .filter { !$0.isWatched && (itemIsQueued($0) || ProgressRecorder.resumePosition(for: $0) > 0) }
    }

    private static func itemIsQueued(_ item: WatchProgress) -> Bool { item.isQueuedForContinue == true }

    public func markWatched(_ item: WatchProgress) async {
        var updated = item
        updated.isWatched = true
        updated.updatedAt = Date()
        await services.progress.save(updated)
        await load()
    }

    /// Clears the watched mark from every watched record of the card's title as it is now, so an episode watched since the
    /// card was drawn is cleared too. In-progress records of the title are left alone.
    public func markUnwatched(_ card: WatchedCard) async {
        let current = await services.progress.all().filter { $0.isWatched && WatchedCards.titleKey(of: $0) == card.id }
        await services.progress.remove(current.map(\.id))
        await load()
    }

    public func removeSaved(_ item: LibraryItem) async {
        await services.library.remove(item.id)
        await load()
    }

    /// Clears every filter of the page in view, keeping the sort.
    public func clearFilters() {
        if showsDownloads { downloadFilter.clearFilters() } else { filter.clearFilters() }
    }

    /// Clears the filter one chip stands for.
    public func removeFilter(_ chip: FilterChip) {
        filter.remove(chip.target)
    }

    /// Clears the Downloads filter one chip stands for.
    public func removeDownloadFilter(_ chip: DownloadFilterChip) {
        downloadFilter.remove(chip.target)
    }

    /// What tapping an in-progress item plays; the player resumes from the saved position.
    nonisolated public static func request(for progress: WatchProgress) -> StreamRequest {
        StreamRequest(type: progress.type, id: progress.contentID, title: progress.title, poster: progress.poster,
                      season: progress.season, episode: progress.episode)
    }

    /// The saved title a progress record belongs to: its type and series id (the episode's series for a series).
    private static func titleKey(of record: WatchProgress) -> String {
        WatchedCards.titleKey(of: record)
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.filterTask?.cancel()
                self.filterTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    self?.applyFilter()
                }
            }
        }
        self.visibleSaved = visibleSaved
        self.visibleWatched = visibleWatched
        // A card carries the genres its title's page lists, the filter's own first, so the card and the page it opens show the genre
        // the title is there for rather than whatever its catalog said when it was saved.
        let selected = filter.genres.sorted()
        func shown(_ entry: LibraryEntry) -> LibraryEntry {
            var copy = entry
            copy.item?.genres = MediaGenres.leading(selected, in: entry.genres)
            return copy
        }
        saved = visibleSaved.compactMap { shown($0).item }
        watched = WatchedCards.cards(from: visibleWatched.map { shown($0) })
    }

    /// Every site's score for a title comes from the rating store, which starts a lookup for it if it has none yet. Without a
    /// threshold or the Rating sort no score is needed, so nothing is looked up.
    private func scoreLookup(for filter: LibraryFilter) -> LibraryFiltering.ScoreLookup {
        guard filter.minimumRating != nil || filter.sort == .rating, let store = ratings else { return LibraryFiltering.catalogueScores }
        return { entry in store.judgedRating(for: entry.preview) ?? LibraryFiltering.catalogueScores(entry) }
    }
}
