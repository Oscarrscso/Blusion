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

    init(services: AppServices, initialQuery: String? = nil) {
        _model = State(initialValue: SearchViewModel(services: services, history: services.searchHistory))
        self.initialQuery = initialQuery
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.shelfSpacing) {
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
                        Text("Searching…").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, metrics.pageMargin)
                        SkeletonRow()
                    } else if model.showsNoResults {
                        ContentUnavailableView.search(text: model.query)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        // Any scroll of the page puts the keyboard away, so a swipe down clears the view of the results.
        .scrollDismissesKeyboard(.immediately)
        .screenBackground()
        .navigationTitle("Search")
        .searchable(text: $model.query, isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Shows, Movies, and More")
        .searchFocused($isSearchFocused)
        .onChange(of: router.searchBrowseRevision) {
            model.query = ""
            isSearchPresented = false
            isSearchFocused = false
        }
        .onChange(of: router.searchFocusRevision) {
            isSearchPresented = true
            isSearchFocused = true
        }
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
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: metrics.shelfSpacing) {
            if !model.recentQueries.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack {
                        SectionHeader("Recent Searches")
                        Button("Clear") { model.clearRecents() }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .accessibilityIdentifier("search.clearRecents")
                    }
                    ForEach(model.recentQueries, id: \.self) { query in
                        Button {
                            model.query = query
                            Task { await model.submit() }
                        } label: {
                            Label(query, systemImage: "clock")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.recent.\(query)")
                        .contextMenu {
                            Button("Remove", role: .destructive) { model.removeRecent(query) }
                        }
                    }
                }
                .padding(.horizontal, metrics.pageMargin)
            }
            if model.browseGenres.isEmpty {
                EmptyStateView("Search your addons", systemImage: "magnifyingglass", message: "Find something to watch by title.")
            } else {
                SectionHeader("Browse Categories").padding(.horizontal, metrics.pageMargin)
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
