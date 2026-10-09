import Foundation
import Observation
import PlayerKit
import StremioKit

/// Home: the user's widgets, or the automatic layout, as sections. Each hero and row loads on its own and fills in as its addon answers.
@MainActor
@Observable
public final class HomeViewModel {
    public enum Phase: Equatable {
        case loading
        /// Nothing installed: the empty state explains how to add an addon by URL.
        case noAddons
        /// Addons are installed, nothing is saved, and none offers a browsable catalog for the automatic layout.
        case noCatalogs
        case ready
    }

    public struct Section: Identifiable, Equatable {
        public let widget: HomeWidget
        /// Items of a `.hero` or `.row` widget. `.collection` and `.continueWatching` sections stay `.loaded([])`.
        public var state: Loadable<[MetaPreview]>
        /// Why a row has nothing to show (addon missing, Trakt client ID needed, unsupported source). nil when fine or still loading.
        public var issue: WidgetSourceError?
        /// True while the section shows items from before (this launch or the last) and a fresh load is on its way.
        public var isRefreshing = false
        public var id: String { widget.id }
    }

    public private(set) var phase: Phase = .loading
    public private(set) var sections: [Section] = []
    /// In-progress titles, newest first (`LibraryViewModel.continueWatching(from:)`).
    public private(set) var continueWatching: [WatchProgress] = []
    public enum ContinueState: Equatable { case loading, disconnected, ready, failed(String) }
    public private(set) var continueState: ContinueState = .loading
    public private(set) var continueEntries: [ContinueWatchingEntry] = []
    /// True when the user has saved their own widget list; false for the automatic layout.
    public private(set) var isCustomised = false

    private let services: AppServices
    private var generation = 0
    private var traktPlayback: [TraktPlaybackItem] = []
    private var refreshingPlayback = false
    private var lastPlaybackRefresh = Date.distantPast

    public init(services: AppServices) {
        self.services = services
    }

    /// Every hero/row section failed and every failure was "offline": show one banner instead of an error on every row.
    public var isOffline: Bool {
        let rows = sections.filter { loadingConfiguration($0.widget.content) != nil }
        let errors = rows.compactMap(\.state.error)
        return phase == .ready && !rows.isEmpty && errors.count == rows.count && Connectivity.isOffline(errors)
    }

    /// Rebuilds the sections from the saved widgets (or `DefaultWidgets.make(for:)` when none are saved) and loads every row concurrently.
    public func load() async {
        generation += 1
        let current = generation
        let addons = await services.registry.addons
        let saved = await services.widgets.load()
        let inProgress = LibraryViewModel.continueWatching(from: await services.progress.all())
        guard current == generation, !Task.isCancelled else { return }
        continueWatching = inProgress
        continueEntries = ContinueWatchingEntry.merge(local: await services.progress.all(), remote: traktPlayback)
        isCustomised = saved != nil
        guard !addons.isEmpty else {
            sections = []
            phase = .noAddons
            return
        }
        let widgets = saved ?? DefaultWidgets.make(for: addons)
        let known = await lastKnownItems(for: widgets)
        guard current == generation, !Task.isCancelled else { return }
        let previous = sections
        sections = widgets.map { HomeViewModel.startingSection(for: $0, previous: previous, known: known) }
        phase = (saved == nil && widgets.isEmpty) ? .noCatalogs : .ready
        await loadRows(generation: current)
    }

    /// Pull to refresh: forgets every cached page, then loads again. The rows keep what they show until the new items arrive.
    public func refresh() async {
        await services.posterRatings.refresh()
        await services.widgetContent.invalidate()
        await refreshContinueWatching(force: true)
        await load()
    }

    /// Loads one hero or row again, after it failed.
    public func retry(sectionID: String) async {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }),
              let row = loadingConfiguration(sections[index].widget.content) else { return }
        let current = generation
        sections[index].state = .loading
        sections[index].isRefreshing = false
        sections[index].issue = nil
        let result = await HomeViewModel.fetch(id: sectionID, row: row, from: services.widgetContent)
        guard current == generation, !Task.isCancelled else { return }
        apply(result)
    }

    /// Cheap refresh for when Home reappears after something was watched: only Continue Watching changes.
    public func continueWatchingRefreshInterval() async -> Int {
        let settings = await services.settings.load()
        return max(0, settings.continueWatchingRefreshSeconds ?? 300)
    }

    public func refreshContinueWatching(force: Bool = false) async {
        let local = await services.progress.all()
        continueWatching = LibraryViewModel.continueWatching(from: local)
        continueEntries = ContinueWatchingEntry.merge(local: local, remote: traktPlayback)
        guard !refreshingPlayback else { return }
        refreshingPlayback = true
        defer { refreshingPlayback = false }
        guard await services.traktAccount.isSignedIn() else {
            traktPlayback = []
            continueEntries = ContinueWatchingEntry.merge(local: local, remote: [])
            continueState = .disconnected
            lastPlaybackRefresh = .distantPast
            return
        }
        let interval = await continueWatchingRefreshInterval()
        guard force || lastPlaybackRefresh == .distantPast
                || (interval > 0 && Date().timeIntervalSince(lastPlaybackRefresh) >= Double(interval)) else { return }
        let previousState = continueState
        lastPlaybackRefresh = Date()
        continueState = .loading
        do {
            let playback = try await services.traktAccount.playback()
            try Task.checkCancellation()
            guard await services.traktAccount.isSignedIn() else {
                traktPlayback = []
                continueState = .disconnected
                continueEntries = ContinueWatchingEntry.merge(local: await services.progress.all(), remote: [])
                return
            }
            traktPlayback = playback
            // Only a real runtime can turn Trakt's percentage into a resume position for Infuse.
            for item in playback {
                guard let duration = item.duration else { continue }
                let previous = await services.progress.progress(for: item.id)
                if let previous, previous.updatedAt >= item.pausedAt { continue }
                await services.progress.save(WatchProgress(id: item.id, type: item.preview.type, contentID: item.contentID,
                    title: item.request.title, poster: item.preview.poster, position: duration * item.progress / 100,
                    duration: duration, isWatched: false, updatedAt: item.pausedAt, season: item.season, episode: item.episode))
            }
            continueState = .ready
        } catch {
            if Task.isCancelled {
                continueState = previousState
                lastPlaybackRefresh = .distantPast
                return
            }
            continueState = .failed((error as? TraktAccountError)?.message ?? "Couldn’t load Trakt playback. Try again.")
        }
        let updated = await services.progress.all()
        continueWatching = LibraryViewModel.continueWatching(from: updated)
        continueEntries = ContinueWatchingEntry.merge(local: updated, remote: traktPlayback)
    }

    /// Reloads whenever the set, order or enabled state of addons changes. Run from a view's `.task`; cancelling stops it.
    public func observeAddons() async {
        // A returning view starts fresh even when its previous observation was cancelled during a row load.
        var signature: [String]?
        for await addons in await services.registry.updates() {
            guard !Task.isCancelled else { break }
            let newSignature = addons.map { "\($0.id.uuidString):\($0.isEnabled)" }
            guard newSignature != signature else { continue }
            signature = newSignature
            await load()
        }
    }

    // MARK: Loading

    /// Loads every hero and row at once; each one fills in as its answer arrives. Answers to an older `load()` are dropped.
    private func loadRows(generation current: Int) async {
        let content = services.widgetContent
        var rows: [(id: String, row: RowConfiguration)] = []
        for section in sections {
            if let row = loadingConfiguration(section.widget.content) { rows.append((section.id, row)) }
        }
        await withTaskGroup(of: RowResult.self) { group in
            for (id, row) in rows {
                group.addTask { await HomeViewModel.fetch(id: id, row: row, from: content) }
            }
            for await result in group where current == generation {
                apply(result)
            }
        }
    }

    /// The last items of every hero and row, looked up concurrently before any network load starts. Rows with nothing known are left out.
    private func lastKnownItems(for widgets: [HomeWidget]) async -> [String: [MetaPreview]] {
        let content = services.widgetContent
        var rows: [(id: String, row: RowConfiguration)] = []
        for widget in widgets {
            if let row = loadingConfiguration(widget.content) { rows.append((widget.id, row)) }
        }
        return await withTaskGroup(of: (String, [MetaPreview]?).self, returning: [String: [MetaPreview]].self) { group in
            for (id, row) in rows {
                group.addTask { (id, await HomeViewModel.knownItems(for: row, from: content)) }
            }
            var known: [String: [MetaPreview]] = [:]
            for await (id, items) in group {
                if let items, !items.isEmpty { known[id] = items }
            }
            return known
        }
    }

    /// Applies a finished row load. A failure keeps the items the row already shows (stale content beats an error), but an issue
    /// (the source cannot load at all) always replaces them, so a removed addon's items do not linger.
    private func apply(_ result: RowResult) {
        guard !Task.isCancelled, result.state.error != .cancelled,
              let index = sections.firstIndex(where: { $0.id == result.id }) else { return }
        sections[index].isRefreshing = false
        if result.issue == nil, result.state.error != nil, let shown = sections[index].state.value, !shown.isEmpty { return }
        sections[index].state = result.state
        sections[index].issue = result.issue
    }

    /// The items of one row. The issue is checked first, so a source that cannot load (say, a removed addon) never answers from the cache.
    nonisolated private static func fetch(id: String, row: RowConfiguration, from content: WidgetContentService) async -> RowResult {
        if let issue = await content.issue(with: row.source) {
            return RowResult(id: id, state: .loaded([]), issue: issue)
        }
        do {
            let items = try await content.items(for: row.source, limit: row.limit, cacheTTL: row.cacheTTL)
            return RowResult(id: id, state: .loaded(items), issue: nil)
        } catch let error as WidgetSourceError {
            guard case .addon(let addonError) = error else { return RowResult(id: id, state: .loaded([]), issue: error) }
            return RowResult(id: id, state: .failed(addonError), issue: nil)
        } catch {
            return RowResult(id: id, state: .failed(AddonError.from(error)), issue: nil)
        }
    }

    /// The items a row can show before its fresh load. A source that cannot load shows nothing, so a removed addon's items never linger.
    nonisolated private static func knownItems(for row: RowConfiguration, from content: WidgetContentService) async -> [MetaPreview]? {
        guard await content.issue(with: row.source) == nil else { return nil }
        return await content.lastKnownItems(for: row.source, limit: row.limit)
    }

    /// What a hero or row shows before its fresh load: the items already on screen for the same widget, else its last-known items,
    /// both while refreshing; otherwise nothing yet, so it is loading. Other widgets have no items to load.
    private static func startingSection(for widget: HomeWidget, previous: [Section], known: [String: [MetaPreview]]) -> Section {
        guard loadingConfiguration(widget.content) != nil else { return Section(widget: widget, state: .loaded([]), issue: nil) }
        if let kept = previous.first(where: { $0.id == widget.id && $0.widget.content == widget.content })?.state.value, !kept.isEmpty {
            return Section(widget: widget, state: .loaded(kept), issue: nil, isRefreshing: true)
        }
        if let items = known[widget.id] {
            return Section(widget: widget, state: .loaded(items), issue: nil, isRefreshing: true)
        }
        return Section(widget: widget, state: .loading, issue: nil)
    }
}

/// What one row's load produced.
private struct RowResult: Sendable {
    let id: String
    let state: Loadable<[MetaPreview]>
    let issue: WidgetSourceError?
}

/// The configuration of a `.hero` or `.row`, the widgets that load items; nil for the others.
private func loadingConfiguration(_ content: HomeWidget.Content) -> RowConfiguration? {
    switch content {
    case .hero(let row), .row(let row): return row
    case .collection, .continueWatching: return nil
    }
}
