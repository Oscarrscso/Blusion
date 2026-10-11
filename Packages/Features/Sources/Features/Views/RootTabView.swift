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
    /// Per tab, how deep in its stack an actor's page sits while it is on screen (see `enterTitleOrPerson`).
    private var actorDepths: [LaunchRoute.Tab: Int] = [:]
    var searchBrowseRevision = 0
    var searchFocusRevision = 0
    /// Untyped, because screens inside Settings push values of their own (an addon's id, a widget).
    var settingsPath = NavigationPath()
    var demoPlan: PlaybackPlan?
    var addonInstallText: String?
    var userStateRevision = 0
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

    private func path(for tab: LaunchRoute.Tab) -> NavigationPath {
        switch tab {
        case .home: homePath
        case .discover: discoverPath
        case .library: libraryPath
        case .search: searchPath
        case .settings: settingsPath
        }
    }

    private func setPath(_ path: NavigationPath, for tab: LaunchRoute.Tab) {
        switch tab {
        case .home: homePath = path
        case .discover: discoverPath = path
        case .library: libraryPath = path
        case .search: searchPath = path
        case .settings: settingsPath = path
        }
    }

    /// How many screens the current tab's stack holds above its first.
    var depth: Int { path(for: tab).count }

    /// An actor's page has appeared in the current tab's stack: remember how deep it is.
    func actorPageAppeared() {
        actorDepths[tab] = path(for: tab).count
    }

    /// The actor's page is gone from the stack (popped, not just covered): forget it.
    func actorPageDisappeared(depth: Int) {
        guard path(for: tab).count < depth, actorDepths[tab] == depth else { return }
        actorDepths[tab] = nil
    }

    /// A title or actor page has appeared as the stack's top. When it was opened from a title that an actor's page opened, the back
    /// queue starts over: the stack becomes just this page, so back goes to the tab's first screen. Returns whether it did.
    @discardableResult
    func enterTitleOrPerson(_ destination: some Hashable) -> Bool {
        let tab = tab
        guard let actorDepth = actorDepths[tab], path(for: tab).count == actorDepth + 2 else { return false }
        actorDepths[tab] = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { setPath(NavigationPath([destination]), for: tab) }
        return true
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
                        .appDestinations(services: services)
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
                        .appDestinations(services: services)
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
                            .appDestinations(services: services)
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
                        .appDestinations(services: services)
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
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscape = $0 }
        .focusedSceneValue(router)
        .preferredColorScheme(.dark)
        // Screens run edge to edge, including the sides of a landscape iPhone. Only the navigation bar and tab bar keep their safe area.
        .ignoresSafeArea(.container, edges: .horizontal)
    }

    private func refreshUserState() async {
        let progress = await services.progress.all()
        resume.update(from: progress)
        await titleActions.refresh(progress: progress)
        let settings = await services.settings.load()
        services.posterRatings.isEnabled = settings.showsPosterRatings
        services.posterRatings.showsColouredLogos = settings.showsColouredRatingLogos
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
