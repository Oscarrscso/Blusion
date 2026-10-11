#if canImport(UIKit)
import SwiftUI
import StremioKit

/// Screens reachable from the Settings tab's stack.
enum SettingsDestination: Hashable {
    case addons
    case widgets
}

/// App-level navigation state, shared through the environment so any screen can switch tab or open Settings.
@MainActor
@Observable
public final class AppRouter {
    public var tab: LaunchRoute.Tab
    public var homePath = NavigationPath()
    var searchPath = NavigationPath()
    var discoverPath = NavigationPath()
    var libraryPath = NavigationPath()
    var searchBrowseRevision = 0
    var searchFocusRevision = 0
    /// Untyped, because screens inside Settings push values of their own (an addon's id, a widget).
    var settingsPath = NavigationPath()
    var demoPlan: PlaybackPlan?
    var addonInstallText: String?
    var userStateRevision = 0
    /// The depth of `homePath` once a title opened from Home's spotlight is on it. When the path falls below that depth, the spotlight's
    /// title has been popped and Home is back, see `HomeView`.
    var spotlightDepth: Int?
    /// Counts the returns to Home from a spotlight title. The spotlight and Home's scroll reset to their first page and top on each.
    var spotlightRevision = 0
    /// Navigation values must wait until their stacks and destinations have appeared.
    private var pendingLaunchRoute: LaunchRoute?

    public init(route: LaunchRoute = .home) {
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

    public func open(_ tab: LaunchRoute.Tab) { self.tab = tab }

    /// The one way back in a stack: the back swipe and the spotlight title's own back button both pop here, so one gesture never pops
    /// twice. A title opened from Home's spotlight with no animation closes with none (see `instantDestination()`); every other screen
    /// closes with its own transition.
    func goBack(in path: ReferenceWritableKeyPath<AppRouter, NavigationPath>) {
        guard !self[keyPath: path].isEmpty else { return }
        guard path == \AppRouter.homePath, spotlightDepth == homePath.count else {
            self[keyPath: path].removeLast()
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { homePath.removeLast() }
    }

    /// The Search tab on its category browser, as if the tab had been tapped from another tab.
    func showSearchBrowse() {
        searchPath = NavigationPath()
        searchBrowseRevision += 1
        tab = .search
    }

    /// The Settings tab, on its first screen.
    public func showSettings() { showSettings(.settings) }

    /// The Settings tab, opened on the addons list.
    public func showAddons() { showSettings(.addons) }

    /// The Settings tab, opened on the Home widgets manager.
    public func showWidgets() { showSettings(.widgets) }

    private func showSettings(_ screen: LaunchRoute.Sheet) {
        switch screen {
        case .settings: settingsPath = NavigationPath()
        case .addons: settingsPath = NavigationPath([SettingsDestination.addons])
        case .widgets: settingsPath = NavigationPath([SettingsDestination.widgets])
        }
        tab = .settings
    }
}

/// The component gallery's place in a navigation stack (debug aid, see `DesignGalleryView`).
struct GalleryDestination: Hashable {
    var section: String?
}

public struct RootTabView: View {
    private let services: AppServices
    private let initialQuery: String?
    private let userStateRevision: Int
    @Binding private var addonLink: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    @State private var resume: ContinueWatchingModel
    @State private var titleActions: TitleActions
    @State private var isLandscape = false
    @State private var windowSafeArea = EdgeInsets()

    public init(services: AppServices, route: LaunchRoute = .home, addonLink: Binding<String?> = .constant(nil), userStateRevision: Int = 0) {
        self.services = services
        self.userStateRevision = userStateRevision
        _addonLink = addonLink
        initialQuery = route.searchQuery
        _router = State(initialValue: AppRouter(route: route))
        _resume = State(initialValue: ContinueWatchingModel(services: services))
        _titleActions = State(initialValue: TitleActions(services: services))
    }

    public var body: some View {
        @Bindable var router = router
        TabView(selection: Binding(get: { router.tab }, set: { tab in
            if tab == .search {
                router.searchPath = NavigationPath()
                if router.tab == .search {
                    router.searchFocusRevision += 1
                } else {
                    router.searchBrowseRevision += 1
                }
            }
            router.tab = tab
        })) {
            Tab(value: LaunchRoute.Tab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(services: services)
                        .appDestinations(services: services, path: \.homePath)
                        .navigationDestination(for: GalleryDestination.self) { DesignGalleryView(section: $0.section) }
                }
                .zoomTransitions()
                .task {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    router.presentLaunchRoute()
                }
            } label: {
                Label {
                    Text("Home")
                } icon: {
                    Image(systemName: router.tab == .home ? "play.house.fill" : "play.house")
                        .environment(\.symbolVariants, .none)
                }
            }
            Tab(value: LaunchRoute.Tab.discover) {
                NavigationStack(path: $router.discoverPath) {
                    DiscoverView(services: services) { router.showAddons() }
                        .appDestinations(services: services, path: \.discoverPath)
                }
                .zoomTransitions()
            } label: {
                Label {
                    Text("Discover")
                } icon: {
                    Image(systemName: router.tab == .discover ? "square.grid.2x2.fill" : "square.grid.2x2")
                        .environment(\.symbolVariants, .none)
                }
            }
            TabSection("Library") {
                Tab(value: LaunchRoute.Tab.library) {
                    NavigationStack(path: $router.libraryPath) {
                        LibraryView(services: services) { router.open(.discover) }
                            .appDestinations(services: services, path: \.libraryPath)
                    }
                    .zoomTransitions()
                } label: {
                    Label {
                        Text("Library")
                    } icon: {
                        Image(systemName: router.tab == .library ? "books.vertical.fill" : "books.vertical")
                            .environment(\.symbolVariants, .none)
                    }
                }
            }
            // Settings is a tab like the rest, so there is no sheet to dismiss and no Done button.
            Tab(value: LaunchRoute.Tab.settings) {
                NavigationStack(path: $router.settingsPath) {
                    SettingsView(services: services)
                        .navigationDestination(for: SettingsDestination.self) { destination in
                            Group {
                                switch destination {
                                case .addons: AddonsView(services: services)
                                case .widgets: WidgetsManagerView(services: services)
                                }
                            }
                        }
                }
            } label: {
                Label {
                    Text("Settings")
                } icon: {
                    Image(systemName: router.tab == .settings ? "gearshape.fill" : "gearshape")
                        .environment(\.symbolVariants, .none)
                }
            }
            Tab(value: LaunchRoute.Tab.search, role: .search) {
                NavigationStack(path: $router.searchPath) {
                    SearchView(services: services, initialQuery: initialQuery)
                        .appDestinations(services: services, path: \.searchPath)
                }
                .zoomTransitions()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSearchActivation(.automatic)
        .scrollEdgeEffectHidden(isLandscape, for: .top)
        .toolbarBackgroundVisibility(isLandscape ? .hidden : .automatic, for: .navigationBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(ResumeAccessoryModifier(model: resume))
        .task(id: "\(router.tab)-\(userStateRevision)") {
            router.userStateRevision = userStateRevision
            await refreshUserState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshUserState() } }
        }
        .onChange(of: titleActions.watchedIdentities) { _, _ in
            Task { await resume.refresh() }
        }
        .onChange(of: addonLink, initial: true) { _, link in
            guard let link else { return }
            router.addonInstallText = link
            router.showAddons()
            addonLink = nil
        }
        .fullScreenCover(item: $router.demoPlan) { PlayerScreen(plan: $0, services: services) }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            router.presentLaunchRoute(includeHomeDestinations: false)
        }
        .environment(router)
        .environment(services.posterRatings)
        .environment(titleActions)
        .environment(\.isLandscape, isLandscape)
        .environment(\.windowSafeArea, windowSafeArea)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscape = $0 }
        .focusedSceneValue(router)
        .preferredColorScheme(.dark)
        // Screens run edge to edge, including the sides of a landscape iPhone. Only the navigation bar and tab bar keep their safe area.
        .ignoresSafeArea(.container, edges: .horizontal)
        // Read outside the line above: inside it, the sides are no longer a safe area to report. Screens that run under the notch or the
        // status bar take these from the environment (see `windowSafeArea`).
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { windowSafeArea = $0 }
    }

    private func refreshUserState() async {
        let progress = await services.progress.all()
        resume.update(from: progress)
        await titleActions.refresh(progress: progress)
        let settings = await services.settings.load()
        services.posterRatings.isEnabled = settings.showsPosterRatings
        services.posterRatings.showsColouredLogos = settings.showsColouredRatingLogos
        // Trakt may hold newer saved titles and watched marks, from the other device or from the web. Whatever it changed here is read
        // again, and Home is told.
        if let summary = try? await services.traktSync.sync(), summary.changedLocalData {
            let progress = await services.progress.all()
            resume.update(from: progress)
            await titleActions.refresh(progress: progress)
            router.userStateRevision += 1
        }
    }
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
