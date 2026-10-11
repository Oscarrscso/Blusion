#if canImport(UIKit)
import SwiftUI
import StremioKit

struct DiscoverView: View {
    @State private var model: DiscoverViewModel
    @Environment(\.layoutMetrics) private var metrics
    @Environment(PosterRatingsStore.self) private var ratings: PosterRatingsStore?
    let onOpenAddons: () -> Void

    init(services: AppServices, onOpenAddons: @escaping () -> Void) {
        _model = State(initialValue: DiscoverViewModel(services: services))
        self.onOpenAddons = onOpenAddons
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                pageTitle
                if model.hasSources {
                    VStack(alignment: .leading, spacing: metrics.shelfSpacing) {
                        filters
                        results
                    }
                } else {
                    EmptyAddonsView(onOpenAddons: onOpenAddons)
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        #endif
        .task { await model.loadSources() }
        .accessibilityIdentifier("discover.scroll")
    }

    /// The page's title, drawn in the content so the navigation bar stays free of text.
    private var pageTitle: some View {
        Text("Discover")
            .font(Theme.Typography.largeTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.pageMargin)
            .padding(.bottom, metrics.headerSpacing)
            .accessibilityAddTraits(.isHeader)
    }

    /// The same filter row as the Library: the type control, menus that show their active choice, and removable chips under them.
    private var filters: some View {
        @Bindable var model = model
        // Movies and Series only: the other catalogue types stay out of the type control.
        let types = model.types.filter { ["movie", "series"].contains($0.lowercased()) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if types.count > 1 {
                QualitySelector(titles: ["All", "Movies", "Series"], selection: Binding {
                    model.showsAllTypes ? 0 : model.selectedType?.lowercased() == "series" ? 2 : 1
                } set: { index in
                    guard index > 0 else { Task { await model.selectAllTypes() }; return }
                    let type = index == 2 ? "series" : "movie"
                    guard let selected = types.first(where: { $0.lowercased() == type }) else { return }
                    Task { await model.select(type: selected) }
                }, symbols: ["square.grid.2x2", "film", "tv"], accessibilityID: "discover.filter.type")
                .padding(.horizontal, metrics.pageMargin)
            }
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Menu {
                        ForEach(model.visibleSources) { source in
                            Button("\(source.title) · \(source.addon.name)") { Task { await model.select(source: source) } }
                        }
                    } label: {
                        FilterMenuLabel(model.selectedSource?.title ?? "Catalog", systemImage: "square.stack")
                    }
                    .accessibilityIdentifier("discover.catalogMenu")
                    if !model.genres.isEmpty {
                        Menu {
                            Button("All genres") { Task { await model.select(genre: nil) } }
                            ForEach(model.genres, id: \.self) { genre in
                                Button {
                                    Task { await model.select(genre: genre) }
                                } label: {
                                    if model.selectedGenre == genre { Label(genre, systemImage: "checkmark") } else { Text(genre) }
                                }
                            }
                        } label: {
                            FilterMenuLabel(model.selectedGenre ?? "Genre", systemImage: "tag", isActive: model.selectedGenre != nil)
                        }
                        .accessibilityIdentifier("discover.genreMenu")
                    }
                    Menu {
                        ReleaseYearOptions(minimumYear: $model.minimumYear, maximumYear: $model.maximumYear, identifier: "discover.filter.year")
                    } label: {
                        FilterMenuLabel("Year", systemImage: "calendar", isActive: model.minimumYear != nil || model.maximumYear != nil)
                    }
                    .accessibilityIdentifier("discover.filter.year")
                }
            }
            .padding(.horizontal, metrics.pageMargin)
            if let genre = model.selectedGenre {
                ActiveFilterChips(chips: [ActiveFilterChip(id: "genre", label: genre) { Task { await model.select(genre: nil) } }],
                                  identifier: "discover", clearAll: { Task { await model.select(genre: nil) } })
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: model.selectedGenre)
        .sensoryFeedback(.selection, trigger: model.selectedSource)
        .sensoryFeedback(.selection, trigger: model.minimumYear)
    }

    @ViewBuilder
    private var results: some View {
        if !model.visibleItems.isEmpty {
            MediaGrid(items: model.visibleItems, onLastAppear: { Task { await model.loadMore() } })
        } else if !model.items.isEmpty {
            // Every title loaded so far is outside the year span: keep reading until one fits, or the catalogue ends.
            EmptyStateView("No titles match", systemImage: "line.3.horizontal.decrease.circle", message: "Try another year.")
                .task(id: model.items.count) { if model.canLoadMore { await model.loadMore() } }
        }
        switch model.state {
        case .idle, .loadingFirstPage:
            if model.items.isEmpty { SkeletonRow() }
        case .failed(let error):
            if model.isOffline {
                OfflineBanner()
            } else {
                InlineErrorView(error.shortDescription, retry: { Task { await model.reload() } })
                    .padding(.horizontal, metrics.pageMargin)
            }
        case .loaded:
            if model.items.isEmpty { EmptyStateView("Nothing here yet", systemImage: "film", message: "Try another category or genre.") }
        case .loadingMore:
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}
#endif
