#if canImport(UIKit)
import Persistence
import SwiftUI
import StremioKit

public struct RootTabView: View {
    @Environment(\.layoutMetrics) private var metrics
    private let services: AppServices
    private let initialQuery: String?
    private let initialRoute: LaunchRoute
    private let userStateRevision: Int
    @Binding private var addonLink: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    /// The app-level holder of the playback session on the air, so backgrounding or a rebuild of the player's screen never ends
    /// playback (see `LivePlaybackSession`).
    @State private var livePlayback = LivePlaybackSession()
    @State private var landscapeTabs = LandscapeTabBarState()
    @State private var resume: ContinueWatchingModel
    @State private var titleActions: TitleActions
    @State private var failedHandoff: PlaybackHandoffReceipt?
    @State private var isLandscape = false
    @State private var windowSafeArea = EdgeInsets()
    @State private var windowWidth: CGFloat = 0
    #if targetEnvironment(macCatalyst)
    @State private var macNavigation = MacNavigationScrollState()
    #endif
    /// Settings → Appearance, read here for the tab bar, which sits outside `appliesAppearance()`.
    @AppStorage(AppearancePreferences.defaultsKey) private var appearance = AppearancePreferences()
    /// A phone turned sideways. A Mac window is never a phone, so `isPhoneLandscape` never governs its navigation bar, at any window shape.
    private var isPhoneLandscape: Bool { isLandscape && !Self.isMacCatalyst }
    private var isPhoneInLandscape: Bool { isPhoneLandscape && UIDevice.current.userInterfaceIdiom == .phone }
    private static var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
    /// Home, the landscape panel, Search and Back keep this distance from the screen's sides: the corner gap plus 1.5% of the width, so
    /// they sit a little in from the far edges rather than against them. Their distance from the top and bottom stays the corner gap.
    private var landscapeEdgeInset: CGFloat { LandscapeTabBarState.edgeInset(for: windowWidth) }
    /// Only category pages put a heading above the landscape controls. Root tabs and other pushed pages need no repeated context label.
    private var landscapeTitle: String { landscapeTabs.pageTitle ?? "" }
    /// A page pushed on a browsing tab's stack, other than a title's page, in phone landscape: its navigation bar is hidden there and
    /// Back is drawn above Home instead.
    private var showsLandscapeBack: Bool {
        guard isPhoneInLandscape else { return false }
        switch router.tab {
        case .home, .discover, .library, .search: return !router[keyPath: router.pathKey(for: router.tab)].isEmpty
        case .settings, .widgets: return false
        }
    }
    /// The editorial pages' pill bar stands in for the tab bar on a phone held upright (see `EditorialTabBar`); a phone turned sideways
    /// keeps its landscape controls.
    private var usesEditorialTabBar: Bool { appearance.showsEditorialPages && !isPhoneInLandscape }
    /// Phones show each tab's icon alone (see `tabItem`) unless Appearance names them. The iPad and the Mac keep the titles, as their
    /// sidebar rows need them.
    private var showsTabTitles: Bool { UIDevice.current.userInterfaceIdiom != .phone || appearance.phoneTabTitles }

    private var failedHandoffTitle: String {
        if failedHandoff?.handoff.action == .download { return "Couldn’t start download in Infuse" }
        if failedHandoff?.handoff.action == .save { return "Couldn’t save to Infuse" }
        return "Infuse couldn’t play this stream"
    }

    private var showsFailedHandoff: Binding<Bool> {
        Binding<Bool>(get: { failedHandoff != nil }, set: { isPresented in
            if !isPresented { failedHandoff = nil }
        })
    }

    public init(services: AppServices, route: LaunchRoute = .home, addonLink: Binding<String?> = .constant(nil), userStateRevision: Int = 0) {
        self.services = services
        self.userStateRevision = userStateRevision
        _addonLink = addonLink
        initialQuery = route.searchQuery
        // A plain launch opens on Appearance's start tab; a launch that asks for a screen (a test, a link) still opens on that screen.
        var route = route
        if route == .home { route.tab = AppearancePreferences.saved().startTab.tab }
        initialRoute = route
        _router = State(initialValue: AppRouter(route: route))
        _resume = State(initialValue: ContinueWatchingModel(services: services))
        _titleActions = State(initialValue: TitleActions(services: services))
    }

    /// The tabs and their bars and landscape controls.
    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: Binding(get: { router.tab }, set: {
            Haptics.play(.navigation)
            router.tapTab($0)
        })) {
            Tab(value: LaunchRoute.Tab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(services: services)
                        .appDestinations(services: services, path: \.homePath)
                        .navigationDestination(for: GalleryDestination.self) { DesignGalleryView(section: $0.section).browsingBackNavigation() }
                        .navigationDestination(for: BlusionTVRoute.self) { _ in
                            BlusionTVView(services: services).browsingBackNavigation()
                        }
                        .navigationDestination(for: PlayerRecovery.self) { recovery in
                            StreamPickerView(request: recovery.request, services: services,
                                             forcesAutomaticStart: recovery.resumesSession,
                                             allowsAutomaticStart: recovery.resumesSession)
                                .browsingBackNavigation()
                        }
                }
                .zoomTransitions()
                .task {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    router.presentLaunchRoute()
                }
            } label: {
                tabItem("Home", router.tab == .home ? "play.house.fill" : "play.house")
            }
            Tab(value: LaunchRoute.Tab.discover) {
                NavigationStack(path: $router.discoverPath) {
                    DiscoverView(services: services) { router.showAddons() }
                        .appDestinations(services: services, path: \.discoverPath)
                }
                .zoomTransitions()
            } label: {
                tabItem("Discover", router.tab == .discover ? "square.grid.2x2.fill" : "square.grid.2x2")
            }
            TabSection("Library") {
                Tab(value: LaunchRoute.Tab.library) {
                    NavigationStack(path: $router.libraryPath) {
                        LibraryView(services: services) { router.open(.discover) }
                            .appDestinations(services: services, path: \.libraryPath)
                    }
                    .zoomTransitions()
                } label: {
                    tabItem("Library", router.tab == .library ? "books.vertical.fill" : "books.vertical")
                }
            }
            // Settings is a tab like the rest, so there is no sheet to dismiss and no Done button.
            Tab(value: LaunchRoute.Tab.settings) {
                #if targetEnvironment(macCatalyst)
                // The list beside its pages, as Settings is on iPad (see `SettingsView`).
                SettingsView(services: services)
                #else
                NavigationStack(path: $router.settingsPath) {
                    SettingsView(services: services)
                }
                #endif
            } label: {
                tabItem("Settings", router.tab == .settings ? "gearshape.fill" : "gearshape")
            }
            #if targetEnvironment(macCatalyst)
            // The Mac sidebar's Widgets item, at its bottom. On iPhone the widgets manager stays in Settings and behind Home's button.
            Tab(value: LaunchRoute.Tab.widgets) {
                NavigationStack(path: $router.widgetsPath) {
                    // Selecting the tab rebuilds the manager, so it loads what is saved now, not a copy from before a Settings edit.
                    WidgetsManagerView(services: services)
                        .id(router.tabTapRevisions[.widgets, default: 0])
                }
                .zoomTransitions()
            } label: {
                Label {
                    Text("Widgets")
                } icon: {
                    Image(systemName: router.tab == .widgets ? "rectangle.3.group.fill" : "rectangle.3.group")
                        .environment(\.symbolVariants, .none)
                }
            }
            #endif
            // A tab like the rest, not the search role's separate bubble, so the tab bar is one connected bar. Search puts the cursor in its
            // field on every arrival itself (see `SearchView.focusField`).
            Tab(value: LaunchRoute.Tab.search) {
                NavigationStack(path: $router.searchPath) {
                    SearchView(services: services, initialQuery: initialQuery)
                        .appDestinations(services: services, path: \.searchPath)
                }
                .zoomTransitions()
            } label: {
                tabItem("Search", "magnifyingglass")
            }
        }
        .modifier(TabBarStyle())
        .background { appearance.pageBackground.ignoresSafeArea() }
        .scrollEdgeEffectHidden(isPhoneLandscape || Self.isMacCatalyst, for: .top)
        .scrollEdgeEffectHidden(isPhoneInLandscape, for: .bottom)
        .pageTopBar(hidden: isPhoneLandscape)
        .tabBarMinimizeBehavior(Self.isMacCatalyst || isPhoneInLandscape || !appearance.minimisesTabBar ? .never : .onScrollDown)
        .pageTabBar(hidden: isPhoneInLandscape)
        // The native Continue Watching bar goes with the native tab bar.
        .modifier(ResumeAccessoryModifier(model: resume, hidden: router.showsTitlePage || !appearance.showsContinueBar,
                                          isPhoneLandscape: isPhoneInLandscape || usesEditorialTabBar))
        // The editorial pill bar, below every page but a title's, which has the whole screen as it does without it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesEditorialTabBar && !router.showsTitlePage {
                EditorialTabBar(router: router,
                                onAccent: router.tab == .search && router.searchPath.isEmpty && router.showsAccentPage)
            }
        }
        // The native bar stays hidden for *all* landscape scroll states. Replacing it mid-scroll
        // changes safe-area geometry and is what made the old detached Home button jump.
        .overlay(alignment: .bottom) {
            // Category pages add their heading above the panel; root tabs and other pushed pages show the controls alone.
            if isPhoneInLandscape {
                HStack(alignment: .bottom) {
                    LandscapeTabControls(router: router, collapsed: landscapeTabs.collapsed, title: landscapeTitle,
                                         hidesPageHeader: landscapeTabs.pageTitle?.isEmpty != false,
                                         onHome: { landscapeTabs.reset(); router.tapTab(.home) },
                                         onReveal: { landscapeTabs.reset() })
                    Spacer(minLength: 0)
                    Button {
                        Haptics.play(.navigation)
                        router.tapTab(.search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 21, weight: .medium))
                    }
                    .buttonStyle(FixedGlassButtonStyle(size: 44))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Search")
                    .accessibilityIdentifier("landscape.search")
                    .opacity(landscapeTabs.collapsed ? 0 : 1)
                    .allowsHitTesting(!landscapeTabs.collapsed)
                    .accessibilityHidden(landscapeTabs.collapsed)
                    .animation(LandscapeTabControls.fade(collapsed: landscapeTabs.collapsed), value: landscapeTabs.collapsed)
                }
                .padding(.horizontal, landscapeEdgeInset)
                // Measured from the screen's bottom edge, not the home indicator's safe area, so Home and Search sit in the corners.
                .padding(.bottom, LandscapeTabBarState.cornerInset)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        // Back sits in the top corner, in the same column as Home in the bottom one, on every pushed page in phone landscape (title pages,
        // See All grids, categories and the stream picker), whose navigation bars are hidden there, so it is the same button everywhere.
        .overlay(alignment: .topLeading) {
            if showsLandscapeBack {
                RoundBackButton()
                    .accessibilityIdentifier("landscape.back")
                    .padding(.top, LandscapeTabBarState.cornerInset)
                    .padding(.leading, landscapeEdgeInset)
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.opacity)
            }
        }
    }

    /// The page's events, alerts and environment, split from `tabs` so the compiler type-checks each chain in reasonable time.
    public var body: some View {
        @Bindable var router = router
        tabs
        .onChange(of: router.tab) { _, _ in
            landscapeTabs.reset()
            landscapeTabs.clearPageTitle()
        }
        .onChange(of: router.showsTitlePage) { _, showsTitlePage in
            if showsTitlePage {
                landscapeTabs.prepareForDetailPage()
            } else {
                landscapeTabs.restoreAfterDetailPage()
            }
        }
        .onChange(of: isPhoneInLandscape) { _, landscape in
            if landscape, router.showsTitlePage {
                landscapeTabs.prepareForDetailPage()
            } else {
                landscapeTabs.reset()
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .playbackHandoffDidFinish)) { notification in
            guard let receipt = notification.object as? PlaybackHandoffReceipt else { return }
            if case .failed = receipt.result { failedHandoff = receipt }
        }
        .alert(failedHandoffTitle,
               isPresented: showsFailedHandoff,
               presenting: failedHandoff) { receipt in
            if receipt.handoff.isPlayback {
                Button("Choose another stream") {
                    router.tab = .home
                    router.homePath.append(PlayerRecovery(request: receipt.handoff.request))
                }
            }
            Button("OK", role: .cancel) {}
        } message: { receipt in
            if case .failed(_, let message) = receipt.result {
                Text(message ?? "Infuse reported an error. Try another stream.")
            }
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
            #if canImport(UIKit)
            // The reviews page's rules and WebKit's process start now, after the first frame, so the first reviews page waits for neither.
            ReviewPageRules.prewarm()
            #endif
        }
        #if targetEnvironment(macCatalyst)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            MacPageNavigationOverlay()
        }
        .environment(macNavigation)
        .buttonStyle(PointingHandButtonStyle(style: .automatic))
        .menuStyle(PointingHandMenuStyle())
        .toggleStyle(PointingHandToggleStyle())
        #endif
        .environment(router)
        .environment(livePlayback)
        .environment(landscapeTabs)
        .environment(services.posterRatings)
        .environment(services.heroMeta)
        .environment(titleActions)
        .environment(\.isLandscape, isLandscape)
        .environment(\.isPhoneLandscape, isPhoneLandscape)
        .environment(\.usesEditorialTabBar, usesEditorialTabBar)
        .environment(\.windowSafeArea, windowSafeArea)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscape = $0 }
        // The full screen width (this sits inside the edge-to-edge line below), for the landscape buttons' side gap.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .focusedSceneValue(router)
        .preferredColorScheme(.dark)
        // Screens run edge to edge, including the sides of a landscape iPhone. Only the navigation bar and tab bar keep their safe area.
        .ignoresSafeArea(.container, edges: .horizontal)
        // Read outside the line above: inside it, the sides are no longer a safe area to report. Screens that run under the notch or the
        // status bar take these from the environment (see `windowSafeArea`).
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { windowSafeArea = $0 }
        // Settings → Appearance: accent, text, font and the preferences every page and card reads, on iPhone and Mac alike.
        .appliesAppearance()
    }

    /// A tab's item. On a phone the tab bar shows the icon alone, and the title stays the item's accessibility label, which the UI tests
    /// find by. The sidebar shows the title beside the icon.
    private func tabItem(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        // Always a label, its title empty while hidden: the tab bar updates a title it is given, but keeps one it has once shown when the
        // label turns into an icon alone.
        Label { Text(showsTabTitles ? title : "") } icon: { Image(systemName: symbol) }
            .accessibilityLabel(Text(title))
            .environment(\.symbolVariants, .none)
    }

    private func refreshUserState() async {
        let progress = await services.progress.all()
        resume.update(from: progress)
        await titleActions.refresh(progress: progress)
        let settings = await services.settings.load()
        services.posterRatings.isEnabled = settings.showsPosterRatings
        services.posterRatings.showsColouredLogos = settings.showsColouredRatingLogos
        services.posterRatings.showsBestDisc = settings.showsBestDiscOnPosters
        services.posterRatings.markPlacement = settings.posterMarkPlacement
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

private struct PlayerRecovery: Hashable {
    let request: StreamRequest
    /// True when reopening the app's saved session: the picker starts that session's own stream again, as a held poster does.
    var resumesSession = false
}
#endif
