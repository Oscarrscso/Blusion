#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Home: the spotlight, then one section per widget of the user's layout (or the automatic one). Each section fills in as its addon
/// answers, and every state (loading, nothing installed, nothing to browse, an issue, offline) has a look of its own.
struct HomeView: View {
    @State private var model: HomeViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TitleActions.self) private var actions: TitleActions?
    init(services: AppServices) {
        _model = State(initialValue: HomeViewModel(services: services))
    }

    var body: some View {
        content
            .navigationTitle(heroIsFirst ? "" : "Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(heroIsFirst ? .hidden : .automatic, for: .navigationBar)
            .task { await model.observeAddons() }
            .onAppear { Task { await model.refreshContinueWatching() } }
            .refreshable { await model.refresh() }
            .onChange(of: actions?.watchedIdentities) { Task { await model.refreshContinueWatching() } }
            .onChange(of: router.userStateRevision) { _, _ in Task { await model.refreshContinueWatching() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refreshContinueWatching() } }
            }
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
            HomeLoadingView()
        case .noAddons:
            EmptyAddonsView(onOpenAddons: { router.showAddons() })
                .screenBackground()
        case .noCatalogs:
            EmptyStateView("Nothing to browse", systemImage: "rectangle.stack",
                           message: "None of your addons offers catalogs. Install one that does, or search by title.",
                           actionTitle: "Open Addons", action: { router.showAddons() })
                .accessibilityIdentifier("board.noCatalogs")
                .screenBackground()
        case .ready:
            ready
        }
    }

    private var ready: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.shelfSpacing) {
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
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(heroIsFirst, for: .top)
        .screenBackground()
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
        case .row(let row):
            WidgetRow(section: section, row: row, onRetry: { retry(section) })
        case .collection(let items):
            CollectionRow(widget: section.widget, items: items)
        case .continueWatching:
            ContinueWatchingRow(items: model.continueWatching, title: section.widget.title, hideTitle: section.widget.hideTitle)
        }
    }

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

/// What Home shows before its layout is known: the spotlight and two rows of placeholders, where the real sections will go.
private struct HomeLoadingView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.rowSpacing) {
                HeroPlaceholder()
                RowPlaceholder(header: .bar, aspect: .poster, size: .medium)
                RowPlaceholder(header: .bar, aspect: .wide, size: .large)
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDisabled(true)
        .scrollEdgeEffectHidden(true, for: .top)
        .screenBackground()
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
#endif
