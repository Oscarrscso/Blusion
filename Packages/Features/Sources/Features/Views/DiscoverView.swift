#if canImport(SwiftUI)
import SwiftUI
import StremioKit

struct DiscoverView: View {
    @State private var model: DiscoverViewModel
    let onOpenAddons: () -> Void

    init(services: AppServices, onOpenAddons: @escaping () -> Void) {
        _model = State(initialValue: DiscoverViewModel(services: services))
        self.onOpenAddons = onOpenAddons
    }

    var body: some View {
        content
            .navigationTitle("Discover")
            .task { await model.loadSources() }
            .refreshable { await model.reload() }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasSources {
            if model.state == .idle {
                EmptyAddonsView(onOpenAddons: onOpenAddons)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filters
                    results
                }
                .padding(.vertical)
            }
            .accessibilityIdentifier("discover.scroll")
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(model.sources) { source in
                    Button("\(source.title) · \(source.addon.name)") { Task { await model.select(source: source) } }
                }
            } label: {
                Label(model.selectedSource.map { "\($0.title) · \($0.addon.name)" } ?? "Catalog", systemImage: "square.stack")
            }
            .accessibilityIdentifier("discover.catalogMenu")

            if !model.genres.isEmpty {
                Menu {
                    Button("All genres") { Task { await model.select(genre: nil) } }
                    ForEach(model.genres, id: \.self) { genre in
                        Button(genre) { Task { await model.select(genre: genre) } }
                    }
                } label: {
                    Label(model.selectedGenre ?? "All genres", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("discover.genreMenu")
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .idle, .loadingFirstPage:
            ProgressView().frame(maxWidth: .infinity)
        case .failed(let error):
            WrappingStack {
                ErrorChip(text: error.shortDescription)
                Button("Try again") { Task { await model.reload() } }
            }
            .padding(.horizontal)
        case .loaded, .loadingMore:
            PosterGrid(items: model.items) { Task { await model.loadMore() } }
            if model.state == .loadingMore { ProgressView().frame(maxWidth: .infinity) }
        }
    }
}
#endif
