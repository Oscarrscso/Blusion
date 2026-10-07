#if canImport(SwiftUI)
import SwiftUI
import PlayerKit
import StremioKit

struct LibraryView: View {
    @State private var model: LibraryViewModel
    let onOpenAddons: () -> Void

    init(services: AppServices, onOpenAddons: @escaping () -> Void) {
        _model = State(initialValue: LibraryViewModel(services: services))
        self.onOpenAddons = onOpenAddons
    }

    var body: some View {
        content
            .navigationTitle("Library")
            .onAppear { Task { await model.load() } }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isEmpty {
            ContentUnavailableView {
                Label("Your library is empty", systemImage: "books.vertical")
            } description: {
                Text("Titles you save, and anything you start watching, show up here. Open a title and choose Save to Library.")
            } actions: {
                Button("Find something to watch", action: onOpenAddons)
                    .accessibilityIdentifier("library.empty.action")
            }
            .accessibilityIdentifier("library.empty")
        } else {
            List {
                if !model.continueWatching.isEmpty { continueSection }
                if !model.saved.isEmpty { savedSection }
                if !model.watched.isEmpty { watchedSection }
            }
            .accessibilityIdentifier("library.list")
        }
    }

    private var continueSection: some View {
        Section("Continue Watching") {
            ForEach(model.continueWatching) { item in
                NavigationLink(value: LibraryViewModel.request(for: item)) { ProgressRow(item: item) }
                    .accessibilityIdentifier("library.continue.\(item.id)")
                    .swipeActions(edge: .trailing) {
                        Button("Remove", role: .destructive) { Task { await model.removeFromContinueWatching(item) } }
                        Button("Watched") { Task { await model.markWatched(item) } }.tint(.green)
                    }
            }
        }
    }

    private var savedSection: some View {
        Section("Saved") {
            ForEach(model.saved) { item in
                NavigationLink(value: item.preview) {
                    HStack(spacing: 12) {
                        PosterImage(url: item.poster, title: item.name).frame(width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body)
                            if let year = item.releaseInfo { Text(year).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .accessibilityIdentifier("library.saved.\(item.id)")
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) { Task { await model.removeSaved(item) } }
                }
            }
        }
    }

    private var watchedSection: some View {
        Section("Watched") {
            ForEach(model.watched) { item in
                HStack {
                    Text(item.title)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title), watched")
                .accessibilityIdentifier("library.watched.\(item.id)")
                .swipeActions(edge: .trailing) {
                    Button("Not watched") { Task { await model.markUnwatched(item) } }
                }
            }
        }
    }
}

/// A title with a bar showing how far through it the viewer got.
struct ProgressRow: View {
    let item: WatchProgress

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: item.poster, title: item.title).frame(width: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.body).lineLimit(2)
                ProgressView(value: item.fraction)
                Text("\(PlayerTime.format(item.position)) of \(PlayerTime.format(item.duration))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(Int(item.fraction * 100)) percent watched")
    }
}
#endif
