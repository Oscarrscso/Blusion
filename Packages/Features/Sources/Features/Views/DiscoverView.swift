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

    private var filters: some View {
        let types = model.types.filter { $0.lowercased() != "other" }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if types.count > 1 {
                QualitySelector(titles: types.map(ContentTypeName.plural), selection: Binding {
                    types.firstIndex(where: { $0 == model.selectedType }) ?? 0
                } set: { index in
                    guard types.indices.contains(index) else { return }
                    Task { await model.select(type: types[index]) }
                }, accessibilityID: "discover.filter.type")
                .padding(.horizontal, metrics.pageMargin)
            }
            Menu {
                ForEach(model.visibleSources) { source in
                    Button("\(source.title) · \(source.addon.name)") { Task { await model.select(source: source) } }
                }
            } label: {
                HStack { Text(model.selectedSource?.title ?? "Catalog"); Image(systemName: "chevron.down") }
            }
            .buttonStyle(.glassCapsule)
            .padding(.horizontal, metrics.pageMargin)
            .accessibilityIdentifier("discover.catalogMenu")
            if !model.genres.isEmpty {
                ChipRow {
                    GlassChip("All", isSelected: model.selectedGenre == nil) { Task { await model.select(genre: nil) } }
                    ForEach(model.genres, id: \.self) { genre in
                        GlassChip(genre, isSelected: model.selectedGenre == genre) { Task { await model.select(genre: genre) } }
                    }
                }
                .accessibilityIdentifier("discover.genreMenu")
            }
        }
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
