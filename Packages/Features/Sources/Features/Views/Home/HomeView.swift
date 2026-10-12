#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Home: the spotlight, then one section per widget of the user's layout (or the automatic one). Each section fills in as its addon
/// answers, and every state (loading, nothing installed, nothing to browse, an issue, offline) has a look of its own.
struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var isScrolling = false
    /// How far Home has been pulled down past its top; the spotlight stretches by this much (see `HeroCarousel`).
    @State private var heroPull: CGFloat = 0
    /// The status bar's height, the top safe area Home's content starts beneath. The navigation bar sits below it, not included.
    @State private var topInset: CGFloat = 0
    /// The page's own side safe-area inset, as its geometry reports it: the notch's inset on a phone held in landscape, zero elsewhere.
    /// In landscape the page runs under it, so the spotlight reaches the screen's edges, and it is added to the page margin, so the
    /// headings and each shelf's first card stay clear of the notch where they were.
    @State private var sideInset: CGFloat = 0
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLandscape) private var isLandscape
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape
    @Environment(TitleActions.self) private var actions: TitleActions?
    init(services: AppServices) {
        _model = State(initialValue: HomeViewModel(services: services))
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .environment(\.heroContainerHeight, geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                // In landscape the page runs under its side insets, so the spotlight is that much wider than the safe width.
                .environment(\.heroContainerWidth, geometry.size.width
                    + (isLandscape ? geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing : 0))
                .environment(\.isHomeScrolling, isScrolling)
                .environment(\.layoutMetrics, homeMetrics)
        }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
            .onGeometryChange(for: CGFloat.self) { max($0.safeAreaInsets.leading, $0.safeAreaInsets.trailing) } action: { sideInset = $0 }
            .navigationTitle(heroIsFirst ? "" : "Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(heroIsFirst || isPhoneLandscape ? .hidden : .automatic, for: .navigationBar)
            .task { await model.observeAddons() }
            .task(id: scenePhase == .active && router.tab == .home) {
                guard scenePhase == .active, router.tab == .home else { return }
                while !Task.isCancelled {
                    await model.refreshContinueWatching()
                    let interval = await model.continueWatchingRefreshInterval()
                    guard interval > 0 else { return }
                    do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                }
            }
            .onChange(of: actions?.watchedIdentities) { Task { await model.refreshContinueWatching() } }
            .onChange(of: router.userStateRevision) { _, _ in Task { await model.refreshContinueWatching() } }
            // Command-R on Mac reloads everything Home shows (see `HomeViewModel.refresh()`).
            .onChange(of: router.homeRefreshRevision) { _, _ in Task { await model.refresh() } }
            // Coming back from Settings: addons or widgets may have changed.
            .onChange(of: router.tab) { old, _ in
                if old == .settings { Task { await model.load() } }
            }
            // The path shrinks when a title opened from the spotlight pops. Such a title opens and closes with no animation (see
            // `instantDestination()`), so the pop starts and ends together, and nothing is left to finish before Home resets. Resetting
            // during a zoom or a swipe that may still be cancelled would move the spotlight under the screen.
            .onChange(of: router.homePath.count) { _, count in
                guard let depth = router.spotlightDepth, count < depth else { return }
                router.spotlightDepth = nil
                router.spotlightRevision += 1
            }
    }

    /// Home's page margin is the title page's content margin, so its headings, the Continue selector and the shelves line up with it.
    /// Shelves still scroll edge to edge; only their first and last cards are inset. In landscape the page runs under its side insets
    /// (see `ignoredEdges`), so the margin grows by that inset and everything but the spotlight's picture stays where it was.
    private var homeMetrics: LayoutMetrics {
        var homeMetrics = metrics
        homeMetrics.pageMargin = metrics.contentMargin + (isLandscape ? sideInset : 0)
        return homeMetrics
    }

    /// The edges the page runs under: the top when the spotlight leads, and in landscape the sides, so the spotlight's picture reaches
    /// the screen's edges instead of stopping at the notch's inset with a black bar beside it.
    private var ignoredEdges: Edge.Set {
        heroIsFirst ? sideEdges.union(.top) : sideEdges
    }

    /// The sides, in landscape: every state of Home runs under them, since the page margin already keeps its content clear of the notch.
    private var sideEdges: Edge.Set { isLandscape ? .horizontal : [] }

    /// A spotlight without a heading extends beneath the navigation bar, which is then clear and has no title; a visible heading stays
    /// below it, under an ordinary bar. This used to follow the scroll position too (the bar took a background and a title once the
    /// content moved past 160 pt), but changing the bar changes the insets the offset is measured against, so the offset crossed the
    /// threshold again and the bar changed again, without end: the Home freeze. Nothing about the bar depends on scrolling now.
    private var heroIsFirst: Bool {
        guard let first = model.sections.first, case .hero = first.widget.content else { return false }
        return first.widget.hideTitle
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ScrollView { VStack(spacing: Theme.rowSpacing) { continueRow; ProgressView() }.padding(.top, Theme.Spacing.m) }
                .screenBackground()
                .ignoresSafeArea(.container, edges: sideEdges)
        case .noAddons:
            ScrollView { VStack(spacing: Theme.rowSpacing) { continueRow; EmptyAddonsView(onOpenAddons: { router.showAddons() }) } }
                .screenBackground()
                .ignoresSafeArea(.container, edges: sideEdges)
        case .noCatalogs:
            ScrollView { VStack(spacing: Theme.rowSpacing) {
                continueRow
                EmptyStateView("Nothing to browse", systemImage: "rectangle.stack",
                           message: "None of your addons offers catalogs. Install one that does, or search by title.",
                           actionTitle: "Open Addons", action: { router.showAddons() })
                .accessibilityIdentifier("board.noCatalogs")
            } }
                .screenBackground()
                .ignoresSafeArea(.container, edges: sideEdges)
        case .ready:
            ready
        }
    }

    /// The id of Home's content, which its scroll goes back to when a title opened from the spotlight is popped.
    private static let topID = "home.top"

    private var ready: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: metrics.shelfSpacing) {
                    if !model.sections.contains(where: { if case .continueWatching = $0.widget.content { true } else { false } }) {
                        continueRow
                    }
                    if model.isOffline {
                        ForEach(model.sections) { section in
                            if case .continueWatching = section.widget.content { sectionView(section) }
                        }
                        OfflineBanner()
                    } else {
                        ForEach(model.sections) { section in
                            if model.isCustomised || !isEmptyRow(section) { sectionView(section) }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xxl)
                // In the content, not the navigation bar: it scrolls away with the page instead of staying pinned, and it is one glass
                // circle instead of a glass button inside the bar's own glass.
                .overlay(alignment: .topTrailing) { customizeButton }
                .id(Self.topID)
            }
            .accessibilityIdentifier("board.rows")
            .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, value in
                heroPull = value
            }
            .environment(\.heroPull, heroIsFirst ? heroPull : 0)
            .onScrollPhaseChange { _, phase in isScrolling = phase.isScrolling }
            .onDisappear { isScrolling = false }
            .contentMargins(.top, 0, for: .scrollContent)
            .screenBackground()
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(heroIsFirst || isPhoneLandscape, for: .top)
            .ignoresSafeArea(.container, edges: ignoredEdges)
            .onChange(of: router.spotlightRevision) { _, _ in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
            // A tap on Home's tab item goes back to its first page, and scrolls it to the top.
            .onChange(of: router.tabTapRevisions[.home, default: 0]) { _, _ in
                withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    /// One round glass button that opens the widgets page, where widgets are added and edited: the navigation bar's button, in the
    /// page so that it scrolls away with it.
    private var customizeButton: some View {
        Button {
            router.showWidgets()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .fontWeight(.semibold)
                .frame(width: Theme.barButtonDiameter, height: Theme.barButtonDiameter)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
                .pointerFeedback()
        }
        .buttonStyle(.plain)
        .padding(.trailing, homeMetrics.pageMargin)
        // With the spotlight first, the content starts at the top of the screen, so `topInset` (the status bar's height, which the navigation
        // bar starts beneath) puts the button's top where the title page's back button's top sits. Otherwise the bar is above the content.
        .padding(.top, heroIsFirst ? topInset : Theme.Spacing.s)
        .accessibilityLabel("Widgets")
        .help("Widgets")
        .accessibilityIdentifier("home.customize")
    }

    private func isEmptyRow(_ section: HomeViewModel.Section) -> Bool {
        guard case .row = section.widget.content, case .loaded(let items) = section.state else { return false }
        return items.isEmpty && section.issue == nil
    }

    @ViewBuilder
    private func sectionView(_ section: HomeViewModel.Section) -> some View {
        switch section.widget.content {
        case .hero:
            HeroSection(section: section, onRetry: { retry(section) })
                // The next shelf starts 20 pt below the hero: the shelf spacing that follows it, less the 20 pt gap wanted here.
                .padding(.bottom, 20 - metrics.shelfSpacing)
        case .banner(let row):
            HeroBannerSection(section: section, row: row, onRetry: { retry(section) })
        case .row(let row):
            WidgetRow(section: section, row: row, onRetry: { retry(section) }, onSetBetterPosters: betterPostersSetter(for: section))
        case .collection(let items):
            CollectionRow(widget: section.widget, items: items)
        case .continueWatching:
            ContinueWatchingRow(items: model.continueEntries, state: model.continueState, retry: refreshPlayback, onRemove: removeContinue,
                                title: section.widget.title, hideTitle: section.widget.hideTitle)
        case .unsupported:
            UnsupportedWidgetRow(widget: section.widget)
        }
    }

    private var continueRow: some View {
        ContinueWatchingRow(items: model.continueEntries, state: model.continueState, retry: refreshPlayback, onRemove: removeContinue)
    }

    /// The Better Posters menu of a row, offered only once the layout is saved: the automatic layout is not saved by a change.
    private func betterPostersSetter(for section: HomeViewModel.Section) -> ((Bool) -> Void)? {
        guard model.isCustomised else { return nil }
        return { on in Task { await model.setBetterPosters(on, sectionID: section.id) } }
    }

    private func refreshPlayback() { Task { await model.refreshContinueWatching(force: true) } }

    private func removeContinue(_ item: ContinueWatchingEntry) { Task { await model.removeFromContinueWatching(item) } }

    private func retry(_ section: HomeViewModel.Section) {
        Task { await model.retry(sectionID: section.id) }
    }
}

#endif
