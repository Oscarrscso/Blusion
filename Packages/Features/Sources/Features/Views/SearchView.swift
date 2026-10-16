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
                .id(Self.topID)
            }
            // Any scroll of the page puts the keyboard away, so a swipe down clears the view of the results.
            .scrollDismissesKeyboard(.immediately)
            .screenBackground()
            .navigationTitle("Search")
            .searchable(text: $model.query, isPresented: $isSearchPresented,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "Shows, Movies, and More")
            .searchFocused($isSearchFocused)
            // Coming from another tab, Search starts on an empty field.
            .onChange(of: router.searchBrowseRevision) { model.query = "" }
            // A title opened from a search was recorded as a recent search; the list reads them again.
            .onChange(of: router.recentSearchRevision) { model.reloadRecents() }
            // Every arrival on Search, and every tap on its button, puts the cursor in the field and brings the keyboard up. The field
            // stays where it is, under the title.
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

    /// Two across on a phone, as many as fit on a wide window.
    private var categoryColumns: [GridItem] {
        metrics.isRegular
            ? [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: Theme.Spacing.s)]
            : Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: 2)
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: metrics.shelfSpacing) {
            if !model.recentQueries.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack {
                        SectionHeader("Recent Searches")
                        Button("Clear", systemImage: "xmark") {
                            Haptics.tap()
                            model.clearRecents()
                        }
                            .labelStyle(.iconOnly)
                            .glassCircleButton(.small)
                            .help("Clear")
                            .accessibilityIdentifier("search.clearRecents")
                    }
                    .padding(.horizontal, metrics.pageMargin)
                    ForEach(model.recentQueries, id: \.self) { query in
                        Button {
                            model.query = query
                            Task { await model.submit() }
                        } label: {
                            // The inset is part of the label, so the whole row from edge to edge answers a tap, not only the text.
                            Label(query, systemImage: "clock")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, metrics.pageMargin)
                                .contentShape(Rectangle())
                                .pointerInteraction(cornerRadius: Theme.Radius.card)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.recent.\(query)")
                        .contextMenu {
                            Button("Remove", role: .destructive) { model.removeRecent(query) }
                        }
                    }
                }
            }
            if model.browseGenres.isEmpty {
                EmptyStateView("Search your addons", systemImage: "magnifyingglass", message: "Find something to watch by title.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader("Browse Categories")
                    // Compact rows on the page's own surface, each with its category's glyph in a small coloured badge: calmer than a
                    // wall of picture-sized colour tiles, and twice as many fit on a screen.
                    LazyVGrid(columns: categoryColumns, spacing: Theme.Spacing.s) {
                        ForEach(model.browseGenres) { genre in
                            NavigationLink(value: CatalogListRequest(title: genre.name, sources: [genre.source])) {
                                CategoryRow(title: genre.name)
                            }
                            .buttonStyle(PressableCardStyle(lifts: false))
                            .accessibilityIdentifier("search.genre.\(genre.name)")
                        }
                    }
                }
                .padding(.horizontal, metrics.pageMargin)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        // A "what should I watch?" search gets the on-device model's picks first, each with why it fits.
        if !model.picks.isEmpty {
            MediaRow("Picks for You") {
                ForEach(model.picks) { pick in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        MediaCardLink(item: pick.item, width: metrics.posterWidth)
                        Text(pick.reason)
                            .font(Theme.Typography.cardSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(3, reservesSpace: true)
                            .frame(width: metrics.posterWidth, alignment: .leading)
                    }
                }
            }
            .accessibilityIdentifier("search.picks")
        }
        // A search typed as a description gets the titles it describes first, found by TMDb from the filters it names.
        if !model.describedItems.isEmpty {
            MediaRow("Matching Your Description") {
                ForEach(model.describedItems, id: \.identity) { MediaCardLink(item: $0) }
            }
            .accessibilityIdentifier("search.described")
        }
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

/// One category on the Search page: its glyph in a small badge of its colour, its name, and a chevron.
private struct CategoryRow: View {
    let title: String

    var body: some View {
        let accent = CollectionTile.accent(for: title)
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: accent.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(accent.colour.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .cardSurface(cornerRadius: Theme.Radius.card + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}
#endif
