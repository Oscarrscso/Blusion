#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

struct SearchView: View {
    @State private var model: SearchViewModel
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape
    @Environment(\.appAppearance) private var appearance
    private let services: AppServices
    private let initialQuery: String?
    /// The id of the page's content, which its scroll goes back to when its tab's item is tapped.
    private static let topID = "search.top"

    init(services: AppServices, initialQuery: String? = nil) {
        _model = State(initialValue: SearchViewModel(services: services, history: services.searchHistory))
        self.services = services
        self.initialQuery = initialQuery
    }

    /// The standard page, or the editorial one (the Arthouse preset), over the same search.
    var body: some View {
        Group {
            if appearance.showsEditorialPages {
                EditorialSearchPage(model: model, services: services, results: resultItems, isLoading: isLoadingResults)
            } else {
                // One side margin for everything on the page, in line with Back and the large title (see `LayoutMetrics.gridPage`).
                standardPage
                    .environment(\.layoutMetrics, metrics.gridPage)
            }
        }
        // Coming from another tab, Search starts on an empty field.
        .onChange(of: router.searchBrowseRevision) { model.query = "" }
        // A title opened from the results has just been recorded.
        .onChange(of: router.recentSearchRevision) { model.reloadRecents() }
        .onChange(of: model.query) { model.queryDidChange() }
        .task {
            await model.refreshAvailability()
            model.prewarmAI()
            if (model.phase == .idle || model.aiPhase == .idle), !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.queryDidChange()
            }
        }
        .onDisappear { model.cancel() }
        .onChange(of: router.tab) { old, _ in
            if old == .settings { Task { await model.refreshAvailability() } }
        }
        .task {
            guard let initialQuery, model.query.isEmpty else { return }
            model.query = initialQuery
            await model.submit()
        }
    }

    private var standardPage: some View {
        @Bindable var model = model
        return ScrollViewReader { proxy in
            ScrollView {
                // Spaced as Discover is: the row above the filters stands where Discover's title does, and the filters and grid follow
                // at the filter bar's own gaps.
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        #if targetEnvironment(macCatalyst)
                        TextField("Shows, Movies, and More", text: $model.query)
                            .textFieldStyle(.roundedBorder)
                            .focused($isSearchFocused)
                            .submitLabel(.search)
                            .onSubmit { Task { await model.submit() } }
                            .padding(.horizontal, metrics.gridPageMargin)
                        #endif
                        PickControls(model: model) { isSearchFocused = false }
                            .padding(.horizontal, metrics.gridPageMargin)
                        if model.isOffline {
                            OfflineBanner()
                        }
                    }
                    .padding(.bottom, Theme.Spacing.m)
                    if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if model.showsNoSearchableAddons {
                            EmptyStateView("No addon can search", systemImage: "magnifyingglass",
                                           actionTitle: "Open Addons", action: { router.showAddons() })
                                .accessibilityIdentifier("search.noSearchableAddons")
                        } else {
                            browse
                        }
                    } else {
                        results
                    }
                }
                #if targetEnvironment(macCatalyst)
                .padding(.top, Theme.Spacing.l)
                #else
                // The navigation bar's search field already stands clear of the page, so the first row needs less above it.
                .padding(.top, Theme.Spacing.s)
                #endif
                .padding(.bottom, Theme.Spacing.l)
                .id(Self.topID)
            }
            .scrollIndicators(.visible, axes: .vertical)
            .scrollIndicatorsFlash(onAppear: true)
            // Any scroll of the page puts the keyboard away, so a swipe down clears the view of the results. The search stays active:
            // ending it would empty the field and take the results with it.
            .trackLandscapeTabScroll()
            .scrollDismissesKeyboard(.immediately)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { isSearchFocused = false }
            }
            .screenBackground()
            .navigationTitle(isPhoneInLandscape ? "" : "Search")
            .macRootNavigation()
            .pageTabBar(hidden: isPhoneInLandscape)
            #if !targetEnvironment(macCatalyst)
            .searchable(text: $model.query, isPresented: $isSearchPresented,
                        placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Shows, Movies, and More")
            .searchFocused($isSearchFocused)
            #endif
            // Every arrival on Search, and every tap on its button, puts the cursor in the field and brings the keyboard up.
            .onChange(of: router.searchFocusRevision, initial: true) { focusField() }
            // Search's active toolbar must leave with its root page, rather than follow a pushed destination.
            .onChange(of: router.searchPath.count) { _, count in
                if count > 0 {
                    isSearchFocused = false
                    isSearchPresented = false
                }
            }
            .onSubmit(of: .search) { Task { await model.submit() } }
            .accessibilityIdentifier("search.results")
            // A tap on Search's tab item goes back to its first page, and scrolls it to the top.
            .onChange(of: router.tabTapRevisions[.search, default: 0]) { _, _ in
                withAnimation(Theme.Motion.snap) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    /// `isPhoneLandscape` is also true on an iPad turned sideways, so the device is checked as well. A phone in landscape shows the
    /// search field without a title above it.
    private var isPhoneInLandscape: Bool { isPhoneLandscape && UIDevice.current.userInterfaceIdiom == .phone }

    /// Puts the cursor in the field. The field is not there in the frame the tab changes, so the focus is asked for again a moment later.
    private func focusField() {
        guard router.tab == .search, router.searchPath.isEmpty else { return }
        isSearchPresented = true
        isSearchFocused = true
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard router.tab == .search, router.searchPath.isEmpty else { return }
            isSearchPresented = true
            isSearchFocused = true
        }
    }

    /// The idle page: the recent searches, the streaming services, each opening everything it streams, then the categories.
    private var browse: some View {
        VStack(alignment: .leading, spacing: metrics.shelfSpacing) {
            if !model.recentQueries.isEmpty { recentSearches }
            tileSection("Streaming Services") {
                ForEach(StreamProvider.browsable, id: \.self) { provider in
                    NavigationLink(value: CatalogListRequest(title: provider.name, sources: [provider.catalogSource])) {
                        CollectionTile(title: provider.name, provider: provider).stretched()
                    }
                    .buttonStyle(PressableCardStyle.poster)
                    .titleTapHaptic()
                    .accessibilityIdentifier("search.service.\(provider.rawValue)")
                }
            }
            if !model.categories.isEmpty {
                tileSection("Categories") {
                    // Picture tiles, as on Home's genre shelf. A genre without a picture shows its colour placeholder.
                    ForEach(model.categories) { genre in
                        NavigationLink(value: CatalogListRequest(title: genre.name, sources: genre.sources)) {
                            CollectionTile(title: genre.name, imageURL: genre.imageURL).stretched()
                        }
                        .buttonStyle(PressableCardStyle.poster)
                        .titleTapHaptic()
                        .accessibilityIdentifier("search.genre.\(genre.name)")
                    }
                }
            }
        }
    }

    /// The last titles opened from Search, newest first. A tap searches for one again, a hold removes it, and Clear removes them all.
    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Recent Searches")
                Button("Clear") {
                    Haptics.play(.buttons)
                    withAnimation(.snappy(duration: 0.3)) { model.clearRecents() }
                }
                .buttonStyle(.hoverPlain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("search.recents.clear")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.recentQueries, id: \.self) { term in
                    Button { searchAgain(term) } label: {
                        Label {
                            Text(term).foregroundStyle(.primary).lineLimit(1)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.hoverPlain)
                    .contextMenu {
                        Button("Remove", systemImage: "xmark", role: .destructive) {
                            withAnimation(.snappy(duration: 0.3)) { model.removeRecent(term) }
                        }
                    }
                    .accessibilityIdentifier("search.recent.\(term)")
                    if term != model.recentQueries.last { Divider() }
                }
            }
        }
        .padding(.horizontal, metrics.gridPageMargin)
        .accessibilityIdentifier("search.recents")
    }

    /// Searches for a recent search again, with the keyboard put away so the results show.
    private func searchAgain(_ term: String) {
        Haptics.play(.buttons)
        isSearchFocused = false
        model.query = term
        Task { await model.submit() }
    }

    private func tileSection(_ title: String, @ViewBuilder tiles: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title)
            LazyVGrid(columns: metrics.wideGridColumns, spacing: metrics.cardSpacing) { tiles() }
        }
        .padding(.horizontal, metrics.gridPageMargin)
    }

    private var resultItems: [MetaPreview] {
        model.results(in: model.scope)
    }

    private var isLoadingResults: Bool {
        model.phase == .searching || model.aiPhase == .searching || model.isResolvingGenres
    }

    /// The scope selector and the menus in Discover's filter bar, then the grid at the bar's own gap, as on Discover.
    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchRefinements(model: model)
            VStack(alignment: .leading, spacing: metrics.shelfSpacing) { resultsContent }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let correction = model.correction {
            Button("Did you mean \(correction)?") {
                Haptics.play(.buttons)
                Task { await model.applyCorrection() }
            }
            .buttonStyle(PointingHandButtonStyle(style: .bordered))
            .padding(.horizontal, metrics.gridPageMargin)
            .accessibilityIdentifier("search.correction")
        }

        if model.scope == .people {
            people
        } else {
            titles
            if model.scope == .all, !model.people.isEmpty {
                SearchPeopleRow(people: model.people, margin: metrics.gridPageMargin)
            }
        }

        // The placeholder grid stands for the first results on its own, as on Discover.
        if isLoadingResults, model.scope == .people || !resultItems.isEmpty {
            Spinner()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Searching")
                .accessibilityIdentifier("search.loading")
        }

        // A plain title search with no TMDb token is answered by the addons alone, and says nothing about it.
        if model.isDiscovery, model.scope != .people, model.aiPhase == .done, let issue = model.aiIssue {
            HStack {
                Text(LocalizedStringKey(issue.text))
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { model.retryAI() }
            }
            .padding(.horizontal, metrics.gridPageMargin)
            .accessibilityIdentifier("search.ai.retry")
        }
    }

    @ViewBuilder
    private var titles: some View {
        if !resultItems.isEmpty {
            MediaGrid(items: resultItems, fillsWidth: true)
        } else if isLoadingResults {
            MediaGridPlaceholder(aspect: .poster, fillsWidth: true)
        } else if model.filter.isActive, model.hasResults {
            EmptyStateView("No matches for these filters", systemImage: "line.3.horizontal.decrease",
                           actionTitle: "Clear Filters", action: { model.clearFilters() })
        } else if !model.isOffline, model.scope != .all || model.people.isEmpty {
            EmptyStateView("No results", systemImage: "magnifyingglass",
                           actionTitle: model.failures.isEmpty ? nil : "Retry Search",
                           action: { Task { await model.submit() } })
                .accessibilityIdentifier("search.empty")
        }
    }

    /// The People results: portrait cards in a grid, each opening the person's page.
    @ViewBuilder
    private var people: some View {
        if !model.people.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: SearchPeopleRow.cardWidth), spacing: metrics.cardSpacing, alignment: .top)],
                      alignment: .leading, spacing: metrics.shelfSpacing) {
                ForEach(model.people) { PersonCardLink(person: $0, width: SearchPeopleRow.cardWidth) }
            }
            .padding(.horizontal, metrics.gridPageMargin)
            .accessibilityIdentifier("search.people.grid")
        } else if !isLoadingResults, !model.isOffline {
            EmptyStateView("No results", systemImage: "person")
                .accessibilityIdentifier("search.empty")
        }
    }

}
#endif
