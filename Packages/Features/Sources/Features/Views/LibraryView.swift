#if canImport(UIKit)
import SwiftUI
import PlayerKit
import StremioKit

struct LibraryView: View {
    @State private var model: LibraryViewModel
    @State private var showsFilters = false
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
                    if !model.filter.chips.isEmpty { filterChips }
                    if !model.hasMatches {
                        EmptyStateLayout(title: "No titles match", systemImage: "line.3.horizontal.decrease.circle",
                                         message: "Try removing a filter.") {
                            Button("Clear Filters") { model.clearFilters() }
                                .buttonStyle(.primaryActionCompact)
                                .accessibilityIdentifier("library.noMatches.clear")
                        }
                        .accessibilityIdentifier("library.noMatches")
                    } else {
                        if !model.continueWatching.isEmpty { continueSection }
                        if !model.saved.isEmpty { savedSection }
                        if !model.watched.isEmpty { watchedSection }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsFilters = true } label: {
                    Label("Filter and Sort", systemImage: model.filter.isNarrowing ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("library.filter")
            }
        }
        .sheet(isPresented: $showsFilters) {
            LibraryFilterSheet(model: model)
        }
        .onAppear { Task { await model.load() } }
        .refreshable { await model.load() }
        .onChange(of: actions?.savedIdentities) { Task { await model.load() } }
        .onChange(of: actions?.watchedIdentities) { Task { await model.load() } }
        .accessibilityIdentifier("library.list")
    }

    /// The active filters, one chip each (tap to clear it), and a chip that clears them all.
    private var filterChips: some View {
        ChipRow {
            ForEach(model.filter.chips) { chip in
                GlassChip(chip.label, systemImage: "xmark") { model.removeFilter(chip) }
                    .accessibilityIdentifier("library.chip.\(chip.id)")
            }
            GlassChip("Clear all", systemImage: "xmark.circle") { model.clearFilters() }
                .accessibilityIdentifier("library.chip.clear")
        }
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

/// The filter and sort controls, in a sheet. Every change applies at once; "Clear Filters" removes them all and keeps the sort.
struct LibraryFilterSheet: View {
    @Bindable var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    ForEach(LibraryKind.allCases) { kind in
                        Toggle(kind.title, isOn: membership(kind, in: \.kinds))
                            .accessibilityIdentifier("library.filter.kind.\(kind.rawValue)")
                    }
                }
                Section("Status") {
                    ForEach(WatchStatus.allCases) { status in
                        Toggle(status.title, isOn: membership(status, in: \.statuses))
                            .accessibilityIdentifier("library.filter.status.\(status.rawValue)")
                    }
                }
                Section("Release year") {
                    if let range = model.availableYears {
                        Picker("From", selection: $model.filter.minimumYear) {
                            Text("Any").tag(Int?.none)
                            ForEach(Array(range.reversed()), id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                        }
                        Picker("To", selection: $model.filter.maximumYear) {
                            Text("Any").tag(Int?.none)
                            ForEach(Array(range.reversed()), id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                        }
                    } else {
                        Text("No release years yet").foregroundStyle(.secondary)
                    }
                }
                Section {
                    let genres = model.availableGenres
                    if genres.isEmpty {
                        Text("Genres appear here for titles saved from now on.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(genres, id: \.self) { genre in
                            Toggle(genre, isOn: membership(genre, in: \.genres))
                        }
                    }
                } header: {
                    Text("Genre")
                } footer: {
                    Text("A title matches if it has any of the chosen genres.")
                }
                Section("Rating") {
                    Picker("At least", selection: $model.filter.minimumRating) {
                        Text("Any").tag(Double?.none)
                        ForEach([5.0, 6.0, 7.0, 8.0, 9.0], id: \.self) { Text("★ \(LibraryFiltering.ratingText($0))+").tag(Double?.some($0)) }
                    }
                }
                Section("Added") {
                    Picker("Added", selection: $model.filter.addedWithin) {
                        ForEach(AddedWithin.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Sort by") {
                    Picker("Sort by", selection: $model.filter.sort) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("library.sort")
                }
                Section {
                    Button("Clear Filters", role: .destructive) { model.clearFilters() }
                        .disabled(!model.filter.isNarrowing)
                        .accessibilityIdentifier("library.filter.clear")
                }
            }
            .navigationTitle("Filter and Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    /// A toggle for one member of a filter set: on adds it, off removes it.
    private func membership<Value: Hashable>(_ value: Value, in keyPath: WritableKeyPath<LibraryFilter, Set<Value>>) -> Binding<Bool> {
        Binding {
            model.filter[keyPath: keyPath].contains(value)
        } set: { included in
            if included {
                model.filter[keyPath: keyPath].insert(value)
            } else {
                model.filter[keyPath: keyPath].remove(value)
            }
        }
    }
}

struct ProgressRow: View {
    let item: WatchProgress

    var body: some View {
        ProgressCard(title: item.title, artwork: item.poster, fraction: item.fraction)
    }
}
#endif
