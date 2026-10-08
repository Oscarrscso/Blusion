#if canImport(UIKit)
import SwiftUI
import StremioKit

/// Screens reachable from the Settings sheet's stack.
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
    var isShowingSettings = false
    /// Untyped, because screens inside Settings push values of their own (an addon's id, a widget).
    var settingsPath = NavigationPath()
    var demoPlan: PlaybackPlan?
    /// What the launch route asked to present. Presented once the tabs are on screen: a sheet whose flag is already true
    /// when its presenter first appears is not shown.
    private var pendingSheet: LaunchRoute.Sheet?
    private var pendingPlayerDemo = false

    public init(route: LaunchRoute = .home) {
        tab = route.tab
        if let detail = route.detail { homePath.append(detail) }
        if let streams = route.streams { homePath.append(streams) }
        if route.showsGallery { homePath.append(GalleryDestination(section: route.gallerySection)) }
        pendingPlayerDemo = route.showsPlayerDemo
        pendingSheet = route.sheet
    }

    /// Presents whatever the launch route asked for. Call once, after the first frame.
    func presentLaunchRoute() {
        if pendingPlayerDemo { demoPlan = .demo }
        switch pendingSheet {
        case .settings: showSettings()
        case .addons: showAddons()
        case .widgets: showWidgets()
        case nil: break
        }
        pendingPlayerDemo = false
        pendingSheet = nil
    }

    public func open(_ tab: LaunchRoute.Tab) { self.tab = tab }

    public func showSettings() {
        settingsPath = NavigationPath()
        isShowingSettings = true
    }

    /// Settings, opened on the addons list.
    public func showAddons() {
        settingsPath = NavigationPath([SettingsDestination.addons])
        isShowingSettings = true
    }

    /// Settings, opened on the Home widgets manager.
    public func showWidgets() {
        settingsPath = NavigationPath([SettingsDestination.widgets])
        isShowingSettings = true
    }

    public func dismissSettings() { isShowingSettings = false }
}

/// The component gallery's place in a navigation stack (debug aid, see `DesignGalleryView`).
struct GalleryDestination: Hashable {
    var section: String?
}

public struct RootTabView: View {
    private let services: AppServices
    private let initialQuery: String?
    @State private var router: AppRouter
    @State private var resume: ContinueWatchingModel

    public init(services: AppServices, route: LaunchRoute = .home) {
        self.services = services
        initialQuery = route.searchQuery
        _router = State(initialValue: AppRouter(route: route))
        _resume = State(initialValue: ContinueWatchingModel(services: services))
    }

    public var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house.fill", value: LaunchRoute.Tab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(services: services)
                        .appDestinations(services: services)
                        .navigationDestination(for: GalleryDestination.self) { DesignGalleryView(section: $0.section) }
                        .settingsButton()
                }
                .zoomTransitions()
            }
            Tab("Discover", systemImage: "square.grid.2x2.fill", value: LaunchRoute.Tab.discover) {
                NavigationStack {
                    DiscoverView(services: services) { router.showAddons() }
                        .appDestinations(services: services)
                }
                .zoomTransitions()
            }
            Tab("Library", systemImage: "books.vertical.fill", value: LaunchRoute.Tab.library) {
                NavigationStack {
                    LibraryView(services: services) { router.open(.discover) }
                        .appDestinations(services: services)
                        .settingsButton()
                }
                .zoomTransitions()
            }
            Tab(value: LaunchRoute.Tab.search, role: .search) {
                NavigationStack {
                    SearchView(services: services, initialQuery: initialQuery)
                        .appDestinations(services: services)
                }
                .zoomTransitions()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(ResumeAccessoryModifier(model: resume))
        .task(id: router.tab) { await resume.refresh() }
        .sheet(isPresented: $router.isShowingSettings) {
            NavigationStack(path: $router.settingsPath) {
                SettingsView(services: services)
                    .navigationDestination(for: SettingsDestination.self) { destination in
                        switch destination {
                        case .addons: AddonsView(services: services)
                        case .widgets: WidgetsManagerView(services: services)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { router.dismissSettings() }.accessibilityIdentifier("settings.done")
                        }
                    }
            }
        }
        .fullScreenCover(item: $router.demoPlan) { PlayerScreen(plan: $0, services: services) }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            router.presentLaunchRoute()
        }
        .environment(router)
        .environment(services.posterRatings)
        .preferredColorScheme(.dark)
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

/// The gear that opens Settings as a sheet. The sheet itself is presented once, by `RootTabView`.
private struct SettingsButton: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.showSettings() } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("settings.open")
            }
        }
    }
}

extension View {
    func settingsButton() -> some View {
        modifier(SettingsButton())
    }
}
#endif
