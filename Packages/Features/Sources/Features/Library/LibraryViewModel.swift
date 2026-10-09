import Foundation
import Observation
import PlayerKit
import StremioKit

/// Library: continue watching, saved titles, and what has been watched. The filter narrows all three sections at once.
@MainActor
@Observable
public final class LibraryViewModel {
    /// The sections as the view shows them: each already filtered and sorted.
    public private(set) var continueWatching: [WatchProgress] = []
    public private(set) var saved: [LibraryItem] = []
    public private(set) var watched: [WatchProgress] = []
    public private(set) var hasLoaded = false

    /// The filters and sort in use. Changing it re-filters the sections at once.
    public var filter = LibraryFilter() {
        didSet { applyFilter() }
    }

    private let services: AppServices
    /// Everything the Library knows, before any filter. The sections above are the visible part of these.
    private var savedEntries: [LibraryEntry] = []
    private var continueEntries: [LibraryEntry] = []
    private var watchedEntries: [LibraryEntry] = []
    private var visibleSaved: [LibraryEntry] = []
    private var visibleContinue: [LibraryEntry] = []
    private var visibleWatched: [LibraryEntry] = []
    private var lastTraktPull = Date.distantPast

    public init(services: AppServices) {
        self.services = services
    }

    /// True when the Library holds nothing at all, whatever the filter. A filter that matches nothing is not empty.
    public var isEmpty: Bool { savedEntries.isEmpty && continueEntries.isEmpty && watchedEntries.isEmpty }

    /// True when at least one section has a title to show under the current filter.
    public var hasMatches: Bool { !(continueWatching.isEmpty && saved.isEmpty && watched.isEmpty) }

    /// The genres and year span of everything in the Library, for the filter's pickers.
    public var availableGenres: [String] { LibraryFiltering.genres(in: savedEntries + continueEntries + watchedEntries) }
    public var availableYears: ClosedRange<Int>? { LibraryFiltering.yearRange(in: savedEntries + continueEntries + watchedEntries) }

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
        continueEntries = Self.continueWatching(from: all).map { record in
            LibraryEntry(record: record, saved: savedByID[Self.titleKey(of: record)])
        }
        watchedEntries = all.filter(\.isWatched).map { record in
            LibraryEntry(record: record, saved: savedByID[Self.titleKey(of: record)])
        }
        hasLoaded = true
        applyFilter()
    }

    /// In-progress items worth resuming, newest first, one per series (the latest episode).
    public static func continueWatching(from all: [WatchProgress]) -> [WatchProgress] {
        var seenSeries = Set<String>()
        return all.filter { !$0.isWatched && ProgressRecorder.resumePosition(for: $0) > 0 }
            .filter { item in
                guard let series = item.seriesID else { return true }
                return seenSeries.insert(series).inserted
            }
    }

    public func removeFromContinueWatching(_ item: WatchProgress) async {
        await services.progress.remove(item.id)
        await load()
    }

    public func markWatched(_ item: WatchProgress) async {
        var updated = item
        updated.isWatched = true
        updated.updatedAt = Date()
        await services.progress.save(updated)
        await load()
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
        // Continue Watching is a list of where the viewer left off, so "recently added" there means "recently watched".
        var continueFilter = filter
        if continueFilter.sort == .recentlyAdded { continueFilter.sort = .recentlyWatched }
        visibleSaved = LibraryFiltering.apply(filter, to: savedEntries, now: now)
        visibleContinue = LibraryFiltering.apply(continueFilter, to: continueEntries, now: now)
        visibleWatched = LibraryFiltering.apply(filter, to: watchedEntries, now: now)
        saved = visibleSaved.compactMap(\.item)
        continueWatching = visibleContinue.compactMap(\.progress)
        watched = visibleWatched.compactMap(\.progress)
    }
}
