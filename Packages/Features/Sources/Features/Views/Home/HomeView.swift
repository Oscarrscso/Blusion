#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Home: the spotlight, then one section per widget of the user's layout (or the automatic one). Each section fills in as its addon
/// answers, and every state (loading, nothing installed, nothing to browse, an issue, offline) has a look of its own.
struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var isScrolling = false
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLandscape) private var isLandscape
    @Environment(TitleActions.self) private var actions: TitleActions?
    init(services: AppServices) {
        _model = State(initialValue: HomeViewModel(services: services))
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .environment(\.heroContainerHeight, geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                .environment(\.isHomeScrolling, isScrolling)
        }
            .navigationTitle(heroIsFirst ? "" : "Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(heroIsFirst || isLandscape ? .hidden : .automatic, for: .navigationBar)
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
            .refreshable { await model.refresh() }
            .onChange(of: actions?.watchedIdentities) { Task { await model.refreshContinueWatching() } }
            .onChange(of: router.userStateRevision) { _, _ in Task { await model.refreshContinueWatching() } }
            // Coming back from Settings: addons or widgets may have changed.
            .onChange(of: router.tab) { old, _ in
                if old == .settings { Task { await model.load() } }
            }
    }

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
        case .noAddons:
            ScrollView { VStack(spacing: Theme.rowSpacing) { continueRow; EmptyAddonsView(onOpenAddons: { router.showAddons() }) } }
                .screenBackground()
        case .noCatalogs:
            ScrollView { VStack(spacing: Theme.rowSpacing) {
                continueRow
                EmptyStateView("Nothing to browse", systemImage: "rectangle.stack",
                           message: "None of your addons offers catalogs. Install one that does, or search by title.",
                           actionTitle: "Open Addons", action: { router.showAddons() })
                .accessibilityIdentifier("board.noCatalogs")
            } }
                .screenBackground()
        case .ready:
            ready
        }
    }

    private var ready: some View {
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
                customizeButton
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .accessibilityIdentifier("board.rows")
        .onScrollPhaseChange { _, phase in isScrolling = phase.isScrolling }
        .onDisappear { isScrolling = false }
        .contentMargins(.top, 0, for: .scrollContent)
        .screenBackground()
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(heroIsFirst || isLandscape, for: .top)
        .ignoresSafeArea(.container, edges: heroIsFirst ? .top : [])
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
                // The next shelf starts directly below the hero, without the normal gap between shelves.
                .padding(.bottom, -metrics.shelfSpacing)
        case .row(let row):
            WidgetRow(section: section, row: row, onRetry: { retry(section) })
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

    private func refreshPlayback() { Task { await model.refreshContinueWatching(force: true) } }

    private func removeContinue(_ item: ContinueWatchingEntry) { Task { await model.removeFromContinueWatching(item) } }

    private func retry(_ section: HomeViewModel.Section) {
        Task { await model.retry(sectionID: section.id) }
    }

    private var customizeButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                router.showWidgets()
            } label: {
                Label("Customize Home", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.glassCapsule)
            .accessibilityIdentifier("home.customize")
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.s)
    }
}

#endif
