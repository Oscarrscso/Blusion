#if canImport(UIKit)
import SwiftUI
import StremioKit

struct SearchView: View {
    @State private var model: SearchViewModel
    @State private var selectedGroup: String?
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics
    private let initialQuery: String?
    /// The id of the page's content, which its scroll goes back to when its tab's item is tapped.
    private static let topID = "search.top"

    init(services: AppServices, initialQuery: String? = nil) {
        _model = State(initialValue: SearchViewModel(services: services, history: services.searchHistory))
        self.initialQuery = initialQuery
    }

    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: metrics.shelfSpacing) {
                    pageTitle
                    if model.isOffline {
                        OfflineBanner()
                    } else if !model.failures.isEmpty {
                        WrappingStack { ForEach(model.failures) { ErrorChip(text: $0.text) } }
                            .padding(.horizontal, metrics.pageMargin)
                            .accessibilityIdentifier("search.failures")
                    }
                    if model.showsNoSearchableAddons {
                        EmptyStateView("No addon can search", systemImage: "magnifyingglass",
                                       message: "Add a catalog addon, such as Cinemeta, in Settings.",
                                       actionTitle: "Open Addons", action: { router.showAddons() })
                            .accessibilityIdentifier("search.noSearchableAddons")
                    } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        browse
                    } else {
                        results
                        if model.phase == .searching {
                            HStack(spacing: Theme.Spacing.s) {
                                ProgressView().controlSize(.small)
                                Text("Searching…").font(.footnote).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, metrics.pageMargin)
                            .accessibilityElement(children: .combine)
                            SkeletonRow()
                        } else if model.showsNoResults {
                            ContentUnavailableView.search(text: model.query)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.l)
                .id(Self.topID)
            }
            // Any scroll of the page puts the keyboard away, so a swipe down clears the view of the results.
            .scrollDismissesKeyboard(.immediately)
            .screenBackground()
            // The title is drawn in the content, as on Library and Discover, so the bar stays free of text.
            .navigationTitle("")
            #if targetEnvironment(macCatalyst)
            .searchable(text: $model.query, isPresented: $isSearchPresented,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "Shows, Movies, and More")
            #else
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            // The system's own place for a search tab's field: it takes the tab bar's place at the foot of the screen, above the keyboard.
            .searchable(text: $model.query, isPresented: $isSearchPresented, prompt: "Shows, Movies, and More")
            #endif
            .searchFocused($isSearchFocused)
            // Coming from another tab, Search starts on an empty field.
            .onChange(of: router.searchBrowseRevision) { model.query = "" }
            // Every arrival on Search, and every tap on its button, puts the cursor in the field and brings the keyboard up.
            .onChange(of: router.searchFocusRevision, initial: true) { focusField() }
            .onChange(of: model.query) {
                selectedGroup = nil
                model.queryDidChange()
            }
            .onSubmit(of: .search) { Task { await model.submit() } }
            .task { await model.refreshAvailability() }
            .onChange(of: router.tab) { old, _ in
                if old == .settings { Task { await model.refreshAvailability() } }
            }
            .task {
                guard let initialQuery, model.query.isEmpty else { return }
                model.query = initialQuery
                await model.submit()
            }
            .accessibilityIdentifier("search.results")
            // A tap on Search's tab item goes back to its first page, and scrolls it to the top.
            .onChange(of: router.tabTapRevisions[.search, default: 0]) { _, _ in
                withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    /// The page's title, drawn in the content so the navigation bar stays free of text.
    private var pageTitle: some View {
        Text("Search")
            .font(Theme.Typography.largeTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.pageMargin)
            .accessibilityAddTraits(.isHeader)
    }

    /// Puts the cursor in the field. The field is not there in the frame the tab changes, so the focus is asked for again a moment later.
    private func focusField() {
        isSearchPresented = true
        isSearchFocused = true
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            isSearchPresented = true
            isSearchFocused = true
        }
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: metrics.shelfSpacing) {
            if !model.recentQueries.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader("Recent")
                        Button("Clear") { model.clearRecents() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear recent searches")
                            .accessibilityIdentifier("search.clearRecents")
                    }
                    // Recent searches as chips that wrap, so a dozen take three lines instead of a screen of rows.
                    FlowLayout(spacing: Theme.Spacing.s) {
                        ForEach(model.recentQueries, id: \.self) { query in
                            GlassChip(query, systemImage: "clock", isCompact: true) {
                                model.query = query
                                Task { await model.submit() }
                            }
                            .accessibilityIdentifier("search.recent.\(query)")
                            .contextMenu {
                                Button("Remove", role: .destructive) { model.removeRecent(query) }
                            }
                        }
                    }
                }
                .padding(.horizontal, metrics.pageMargin)
            }
            if model.browseGenres.isEmpty {
                EmptyStateView("Search your addons", systemImage: "magnifyingglass", message: "Find something to watch by title.")
            } else {
                SectionHeader("Browse").padding(.horizontal, metrics.pageMargin)
                LazyVGrid(columns: metrics.wideGridColumns, spacing: metrics.cardSpacing) {
                    ForEach(model.browseGenres) { genre in
                        NavigationLink(value: CatalogListRequest(title: genre.name, sources: [genre.source])) {
                            CollectionTile(title: genre.name).stretched()
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityIdentifier("search.genre.\(genre.name)")
                    }
                }
                .padding(.horizontal, metrics.pageMargin)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.groups.count > 1 {
            ChipRow(fittingColumns: min(4, model.groups.count + 1)) {
                GlassChip("All", isSelected: selectedGroup == nil, fillsWidth: true) { selectedGroup = nil }
                ForEach(model.groups) { group in
                    GlassChip(group.title, isSelected: selectedGroup == group.id, fillsWidth: true) { selectedGroup = group.id }
                }
            }
        }
        ForEach(model.groups) { group in
            if model.groups.count == 1 || selectedGroup == group.id {
                MediaGrid(items: group.items)
            } else if selectedGroup == nil {
                MediaRow(group.title, onSeeAll: { selectedGroup = group.id }) {
                    ForEach(group.items, id: \.identity) { MediaCardLink(item: $0) }
                }
            }
        }
    }
}
#endif
