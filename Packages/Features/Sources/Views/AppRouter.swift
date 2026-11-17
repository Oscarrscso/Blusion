#if canImport(UIKit)
import Persistence
import SwiftUI
import StremioKit

/// The Settings pages, in the order of its list: pushed on iPhone, shown beside the list on Mac.
enum SettingsDestination: Hashable {
    case addons, server
    case streams, player, downloads
    case appearance, widgets, haptics
    case trakt, ratings, syncFolder
    case performance, data
    case about
}

/// App-level navigation state, shared through the environment so any screen can switch tab or open Settings.
@MainActor
@Observable
final class AppRouter {
    var tab: LaunchRoute.Tab
    var homePath = NavigationPath()
    var searchPath = NavigationPath()
    var discoverPath = NavigationPath()
    var libraryPath = NavigationPath()
    /// Set by a long press on a Download button: Library opens its Downloads page, from its top (see `LibraryView`).
    var opensDownloads = false
    var searchBrowseRevision = 0
    var searchFocusRevision = 0
    /// Counts the titles opened from Search, so the Search screen reads its recent searches again.
    var recentSearchRevision = 0
    /// True while the editorial Search shows its results, which are laid on the accent: the editorial pill bar fills to match.
    var showsAccentPage = false
    /// Untyped, because screens inside Settings push values of their own (an addon's id, a widget).
    var settingsPath = NavigationPath()
    /// The page Settings shows beside its list in Mac and landscape iPhone layouts. `settingsPath` holds deeper pushes.
    var settingsSelection: SettingsDestination? = .addons
    /// The subpage opened from the chosen Settings page in iPhone landscape (`SettingsSidePage`).
    var settingsSidePage = SettingsSidePage()

    /// True when landscape Settings has a subpage or pushed page to step back from.
    var settingsCanGoBack: Bool { !settingsPath.isEmpty || settingsSidePage.page != nil }
    /// The Mac Widgets tab's stack. The widgets manager registers its own editor destinations, so the stack holds nothing else.
    var widgetsPath = NavigationPath()
    var demoPlan: PlaybackPlan?
    var addonInstallText: String?
    var userStateRevision = 0
    /// The depth of `homePath` once a title opened from Home's spotlight is on it. When the path falls below that depth, the spotlight's
    /// title has been popped and Home is back, see `HomeView`.
    var spotlightDepth: Int?
    /// Counts the returns to Home from a spotlight title. Home's scroll goes back to its top on each; the spotlight keeps the title it was on.
    var spotlightRevision = 0
    /// Counts the taps on each tab's item, the selected tab's included. The tab's first page scrolls to its top on each, see `tapTab(_:)`.
    private(set) var tabTapRevisions: [LaunchRoute.Tab: Int] = [:]
    /// The depths at which a title's page sits in each stack, by its path. A title's page has no tab bar and no Continue Watching bar
    /// while it is on top, and both start coming back the moment it is left, as its path shrinks (see `titlePage(on:)`).
    var titlePageDepths: [ReferenceWritableKeyPath<AppRouter, NavigationPath>: Set<Int>] = [:]

    /// The stack each tab shows.
    func pathKey(for tab: LaunchRoute.Tab) -> ReferenceWritableKeyPath<AppRouter, NavigationPath> {
        switch tab {
        case .home: \.homePath
        case .search: \.searchPath
        case .discover: \.discoverPath
        case .library: \.libraryPath
        case .settings: \.settingsPath
        case .widgets: \.widgetsPath
        }
    }

    /// True while the selected tab has a title's page on top.
    var showsTitlePage: Bool {
        let path = pathKey(for: tab)
        return titlePageDepths[path]?.contains(self[keyPath: path].count) ?? false
    }
    /// Navigation values must wait until their stacks and destinations have appeared.
    private var pendingLaunchRoute: LaunchRoute?

    init(route: LaunchRoute = .home) {
        tab = route.tab
        pendingLaunchRoute = route
    }

    /// The root selects the launch tab; Home consumes its navigation values only after its stack appears.
    func presentLaunchRoute(includeHomeDestinations: Bool = true) {
        guard let route = pendingLaunchRoute else { return }
        guard !includeHomeDestinations || route.tab == .home else { return }
        guard !includeHomeDestinations || route.detail != nil || route.streams != nil || route.showsGallery else { return }
        tab = route.tab
        guard includeHomeDestinations || (route.detail == nil && route.streams == nil && !route.showsGallery) else { return }
        pendingLaunchRoute = nil
        if let detail = route.detail { homePath.append(detail) }
        if let streams = route.streams { homePath.append(streams) }
        if route.showsGallery { homePath.append(GalleryDestination(section: route.gallerySection)) }
        if route.showsPlayerDemo { demoPlan = .demo }
        if let screen = route.sheet { showSettings(screen) }
    }

    func open(_ tab: LaunchRoute.Tab) { self.tab = tab }

    /// A tap on a tab's item. Browsing tabs scroll to their top (see `tabTapRevisions`). Settings keeps its scroll position,
    /// and Widgets restarts its stack instead. Tapping the tab that is showing
    /// also takes it back to its first page; switching to another tab keeps its stack, so a title or a draft on it is still there when
    /// it returns. Widgets is the exception: its stack restarts on each selection, so a draft on it does not survive a return. Search starts afresh on every tap: its browse page, or with its field focused when it was already showing.
    func tapTab(_ tab: LaunchRoute.Tab) {
        let isShowing = self.tab == tab
        switch tab {
        // A title opened from the spotlight closes with no animation, as Back closes it (see `goBack`).
        case .home: if isShowing { popToRoot(\.homePath, instantly: spotlightDepth != nil) }
        case .discover: if isShowing { popToRoot(\.discoverPath) }
        case .library: if isShowing { popToRoot(\.libraryPath) }
        case .settings: if isShowing {
            popToRoot(\.settingsPath)
            if settingsSidePage.page != nil { settingsSidePage.close() }
        }
        // Widgets restarts on each selection, not only on a tap of the showing tab: an editor parked on its stack can hold a copy from
        // before a change made on another tab, so it is not kept.
        case .widgets: popToRoot(\.widgetsPath, instantly: true)
        case .search:
            // Every tap on Search brings the keyboard up. Coming from another tab it also starts afresh, on an empty field.
            popToRoot(\.searchPath)
            if !isShowing { searchBrowseRevision += 1 }
            searchFocusRevision += 1
        }
        tabTapRevisions[tab, default: 0] += 1
        self.tab = tab
    }

    private func popToRoot(_ path: ReferenceWritableKeyPath<AppRouter, NavigationPath>, instantly: Bool = false) {
        guard !self[keyPath: path].isEmpty else { return }
        guard instantly else {
            self[keyPath: path] = NavigationPath()
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { self[keyPath: path] = NavigationPath() }
    }

    /// The one way back in a stack: the back swipe and Back (`RoundBackButton`) both pop here, so one gesture never pops twice. A title
    /// opened from Home's spotlight with no animation (`TitleDestination.opensInstantly`) closes with none; every other screen closes
    /// with its own transition. True when a screen was popped, so the caller knows that screen is on its way out; false when
    /// there was nothing to pop.
    @discardableResult
    func goBack(in path: ReferenceWritableKeyPath<AppRouter, NavigationPath>) -> Bool {
        if path == \AppRouter.settingsPath, self[keyPath: path].isEmpty {
            guard settingsSidePage.page != nil else { return false }
            settingsSidePage.close()
            return true
        }
        guard !self[keyPath: path].isEmpty else { return false }
        guard path == \AppRouter.homePath, spotlightDepth == homePath.count else {
            self[keyPath: path].removeLast()
            return true
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { homePath.removeLast() }
        return true
    }

    /// Back on the tab that is showing: pops its stack by one screen, as the back swipe does. False when there was nothing to pop.
    @discardableResult
    func goBackOnTab() -> Bool {
        switch tab {
        case .home: return goBack(in: \.homePath)
        case .discover: return goBack(in: \.discoverPath)
        case .library: return goBack(in: \.libraryPath)
        case .settings: return goBack(in: \.settingsPath)
        case .widgets: return goBack(in: \.widgetsPath)
        case .search: return goBack(in: \.searchPath)
        }
    }

    /// Home reloads everything it shows, as a pull from the top would (see `HomeView`).
    var homeRefreshRevision = 0

    func refreshHome() { homeRefreshRevision += 1 }

    /// The Search tab on its category browser, as if the tab had been tapped from another tab.
    func showSearchBrowse() {
        searchPath = NavigationPath()
        searchBrowseRevision += 1
        tab = .search
    }

    /// A query a shortcut asked Search to run. Search reads it once, so a later visit keeps whatever the person typed.
    var shortcutQuery: String?
    private(set) var shortcutQueryRevision = 0

    func takeShortcutQuery() -> String? {
        let query = shortcutQuery
        shortcutQuery = nil
        return query
    }

    /// Search from a shortcut. An empty query opens the field; a query is submitted by Search when it appears.
    func showShortcutSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchPath = NavigationPath()
        tab = .search
        guard !trimmed.isEmpty else {
            shortcutQuery = nil
            searchBrowseRevision += 1
            searchFocusRevision += 1
            return
        }
        shortcutQuery = trimmed
        shortcutQueryRevision += 1
    }

    /// Library at its first page.
    func showLibraryRoot() {
        libraryPath = NavigationPath()
        tab = .library
    }

    /// The stream picker for the item Resume chose, on Home.
    func showResume(_ candidate: ResumeCandidate) {
        let request = StreamRequest(type: candidate.type, id: candidate.contentID, title: candidate.title, poster: candidate.poster,
                                    season: candidate.season, episode: candidate.episode)
        homePath = NavigationPath([request])
        tab = .home
    }

    /// Blusion TV's guide, pushed on Home.
    func showBlusionTV() {
        homePath = NavigationPath([BlusionTVRoute()])
        tab = .home
    }

    /// A title opened from Spotlight, on Home. Detail loads the rest of the metadata.
    func showDetail(type: String, contentID: String) {
        homePath = NavigationPath([MetaPreview(id: contentID, type: type)])
        tab = .home
    }

    /// The Settings tab, on its first screen.
    func showSettings() { showSettings(.settings) }

    /// The Settings tab, opened on the addons list.
    func showAddons() { showSettings(.addons) }

    /// The Settings tab, opened on the Home widgets manager.
    func showWidgets() { showSettings(.widgets) }

    private func showSettings(_ screen: LaunchRoute.Sheet) {
        let page: SettingsDestination? = switch screen {
        case .settings: nil
        case .addons: .addons
        case .widgets: .widgets
        }
        #if targetEnvironment(macCatalyst)
        // The page is chosen in the list beside it rather than pushed.
        if let page { settingsSelection = page }
        settingsPath = NavigationPath()
        #else
        settingsPath = page.map { NavigationPath([$0]) } ?? NavigationPath()
        #endif
        tab = .settings
    }
}

/// The component gallery's place in a navigation stack (debug aid, see `DesignGalleryView`).
struct GalleryDestination: Hashable {
    var section: String?
}

private extension PlaybackPlan {
    /// Apple's public HLS test stream as an episode, for the launch route `player`.
    static var demo: PlaybackPlan? {
        guard let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8") else { return nil }
        return PlaybackPlan(request: StreamRequest(type: "series", id: "demo:1:2", title: "Sample Show · Test Pattern", season: 1, episode: 2),
                            candidates: [PlaybackCandidate(id: "demo", title: "Sample stream", addonName: "Demo", route: .native(url))])
    }
}
#endif
