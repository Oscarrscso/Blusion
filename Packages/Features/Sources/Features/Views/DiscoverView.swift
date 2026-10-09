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
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if model.hasSources {
                    filters
                    results
                } else {
                    EmptyAddonsView(onOpenAddons: onOpenAddons)
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Discover")
        .task { await model.loadSources() }
        .refreshable { await ratings?.refresh(); await model.reload() }
        .accessibilityIdentifier("discover.scroll")
    }

    /// The same filter row as the Library: the type control, menus that show their active choice, and removable chips under them.
    private var filters: some View {
        // Movies and Series only: the other catalogue types stay out of the type control.
        let types = model.types.filter { ["movie", "series"].contains($0.lowercased()) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if types.count > 1 {
                QualitySelector(titles: types.map(ContentTypeName.plural), selection: Binding {
                    types.firstIndex(where: { $0 == model.selectedType }) ?? 0
                } set: { index in
                    guard types.indices.contains(index) else { return }
                    Task { await model.select(type: types[index]) }
                }, accessibilityID: "discover.filter.type")
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
    }

    @ViewBuilder
    private var results: some View {
        if !model.items.isEmpty {
            MediaGrid(items: model.items, onLastAppear: { Task { await model.loadMore() } })
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
