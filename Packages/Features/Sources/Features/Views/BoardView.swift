#if canImport(SwiftUI)
import SwiftUI
import PlayerKit
import StremioKit

struct BoardView: View {
    @State private var model: BoardViewModel
    let onOpenAddons: () -> Void

    init(services: AppServices, onOpenAddons: @escaping () -> Void) {
        _model = State(initialValue: BoardViewModel(services: services))
        self.onOpenAddons = onOpenAddons
    }

    var body: some View {
        content
            .navigationTitle("Home")
            .task { await model.observeAddons() }
            .onAppear { Task { await model.refreshContinueWatching() } }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noAddons:
            EmptyAddonsView(onOpenAddons: onOpenAddons)
        case .noCatalogs:
            ContentUnavailableView("Nothing to browse", systemImage: "rectangle.stack",
                                   description: Text("None of your addons offers catalogs. Install one that does, or search by title."))
                .accessibilityIdentifier("board.noCatalogs")
        case .ready:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if !model.continueWatching.isEmpty { ContinueWatchingRow(items: model.continueWatching) }
                    ForEach(model.rows) { row in
                        CatalogRowView(row: row) { Task { await model.retry(rowID: row.id) } }
                    }
                }
                .padding(.vertical)
            }
            .accessibilityIdentifier("board.rows")
        }
    }
}

/// Resumable titles above the catalogs. Tapping one goes straight to its streams; the player resumes from the saved position.
struct ContinueWatchingRow: View {
    let items: [WatchProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Watching").font(.title3.bold()).padding(.horizontal).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: LibraryViewModel.request(for: item)) {
                            VStack(alignment: .leading, spacing: 6) {
                                PosterImage(url: item.poster, title: item.title).frame(width: 120)
                                ProgressView(value: item.fraction).frame(width: 120)
                                Text(item.title).font(.footnote.weight(.medium)).lineLimit(2).frame(width: 120, alignment: .leading)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.title), \(Int(item.fraction * 100)) percent watched")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("board.continue.\(item.id)")
                    }
                }
                .padding(.horizontal)
            }
        }
        .accessibilityIdentifier("board.continueWatching")
    }
}

struct CatalogRowView: View {
    let row: BoardViewModel.Row
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.source.title).font(.title3.bold())
                Text(row.source.addon.name).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            rowBody
        }
        .accessibilityIdentifier("board.row.\(row.source.catalog.id)")
    }

    @ViewBuilder
    private var rowBody: some View {
        switch row.state {
        case .idle, .loading:
            ProgressView().padding(.horizontal)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                ErrorChip(text: "\(row.source.addon.name): \(error.shortDescription)")
                Button("Try again", action: retry)
            }
            .padding(.horizontal)
        case .loaded(let items):
            if items.isEmpty {
                Text("Nothing here").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { PosterLink(item: $0) }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
#endif
