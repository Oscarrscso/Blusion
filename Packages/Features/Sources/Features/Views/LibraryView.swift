#if canImport(UIKit)
import SwiftUI
import PlayerKit
import StremioKit

struct LibraryView: View {
    @State private var model: LibraryViewModel
    @Environment(\.layoutMetrics) private var metrics
    @Environment(TitleActions.self) private var actions: TitleActions?
    let onOpenAddons: () -> Void

    init(services: AppServices, onOpenAddons: @escaping () -> Void) {
        _model = State(initialValue: LibraryViewModel(services: services))
        self.onOpenAddons = onOpenAddons
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.shelfSpacing) {
                if !model.hasLoaded {
                    SkeletonRow()
                } else if model.isEmpty {
                    EmptyStateLayout(title: "Your library is empty", systemImage: "books.vertical",
                                     message: "Titles you save, and anything you start watching, show up here.") {
                        Button("Find something to watch", action: onOpenAddons)
                            .buttonStyle(.primaryActionCompact)
                            .accessibilityIdentifier("library.empty.action")
                    }
                    .accessibilityIdentifier("library.empty")
                } else {
                    if !model.continueWatching.isEmpty { continueSection }
                    if !model.saved.isEmpty { savedSection }
                    if !model.watched.isEmpty { watchedSection }
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Library")
        .onAppear { Task { await model.load() } }
        .refreshable { await model.load() }
        .onChange(of: actions?.savedIdentities) { Task { await model.load() } }
        .onChange(of: actions?.watchedIdentities) { Task { await model.load() } }
        .accessibilityIdentifier("library.list")
    }

    private var continueSection: some View {
        MediaRow("Continue Watching") {
            ForEach(model.continueWatching) { item in
                NavigationLink(value: LibraryViewModel.request(for: item)) {
                    ProgressCard(title: item.title, subtitle: progressSubtitle(item), artwork: item.poster, fraction: item.fraction)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("library.continue.\(item.id)")
                .contextMenu {
                    Button("Mark as Watched") { Task { await model.markWatched(item); await actions?.refresh() } }
                    Button("Remove from Continue Watching", role: .destructive) { Task { await model.removeFromContinueWatching(item) } }
                }
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("Saved").padding(.horizontal, metrics.pageMargin)
            LazyVGrid(columns: metrics.posterGridColumns, spacing: metrics.gridRowSpacing) {
                ForEach(model.saved) { item in
                    MediaCardLink(item: item.preview).stretched()
                        .accessibilityIdentifier("library.saved.\(item.id)")
                }
            }
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    private var watchedSection: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("Watched").padding(.horizontal, metrics.pageMargin)
            LazyVGrid(columns: metrics.posterGridColumns, spacing: metrics.gridRowSpacing) {
                ForEach(model.watched) { item in
                    let preview = MetaPreview(id: item.seriesID ?? item.contentID, type: item.type, name: item.title, poster: item.poster)
                    MediaCardLink(item: preview).stretched()
                        .overlay(alignment: .topTrailing) { Badge("Watched", systemImage: "checkmark").padding(6) }
                        .accessibilityIdentifier("library.watched.\(item.id)")
                        .contextMenu { Button("Mark as Unwatched") { Task { await model.markUnwatched(item); await actions?.refresh() } } }
                }
            }
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    private func progressSubtitle(_ item: WatchProgress) -> String {
        let remaining = "\(max(0, Int((item.duration - item.position) / 60))) min left"
        if let season = item.season, let episode = item.episode { return "S\(season), E\(episode) · \(remaining)" }
        return remaining
    }
}

struct ProgressRow: View {
    let item: WatchProgress

    var body: some View {
        ProgressCard(title: item.title, artwork: item.poster, fraction: item.fraction)
    }
}
#endif
