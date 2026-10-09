#if canImport(UIKit)
import SwiftUI
import PlayerKit
import StremioKit

struct LibraryView: View {
    @State private var model: LibraryViewModel
    @State private var showsFilters = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutMetrics) private var metrics
    @Environment(TitleActions.self) private var actions: TitleActions?
    @Environment(PosterRatingsStore.self) private var ratings: PosterRatingsStore?
    let onOpenAddons: () -> Void

    init(services: AppServices, onOpenAddons: @escaping () -> Void) {
        _model = State(initialValue: LibraryViewModel(services: services))
        self.onOpenAddons = onOpenAddons
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.shelfSpacing) {
                filters
                if !model.hasLoaded {
                    SkeletonRow()
                } else if model.isEmpty {
                    EmptyStateLayout(title: "Your library is empty", systemImage: "books.vertical",
                                     message: "Titles you save, and anything you finish watching, show up here.") {
                        Button("Find something to watch", action: onOpenAddons)
                            .buttonStyle(.primaryActionCompact)
                            .accessibilityIdentifier("library.empty.action")
                    }
                    .accessibilityIdentifier("library.empty")
                } else {
                    if !model.hasMatches {
                        EmptyStateLayout(title: "No titles match", systemImage: "line.3.horizontal.decrease.circle",
                                         message: "Try removing a filter.") {
                            Button("Clear Filters") { model.clearFilters() }
                                .buttonStyle(.primaryActionCompact)
                                .accessibilityIdentifier("library.noMatches.clear")
                        }
                        .accessibilityIdentifier("library.noMatches")
                    } else {
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
        .sheet(isPresented: $showsFilters) { LibraryFilterSheet(model: model) }
        .task { model.attachRatings(ratings) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                await actions?.refresh()
                do {
                    try await Task.sleep(for: .seconds(300))
                } catch {
                    return
                }
            }
        }
        .refreshable { await ratings?.refresh(); await model.refresh(); await actions?.refresh() }
        .onChange(of: actions?.savedIdentities) { Task { await model.load() } }
        .onChange(of: actions?.watchedIdentities) { Task { await model.load() } }
        .accessibilityIdentifier("library.list")
    }

    private var filters: some View {
        @Bindable var model = model
        let kinds: [LibraryKind] = [.movie, .series, .anime]
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            QualitySelector(titles: ["All"] + kinds.map(\.title), selection: Binding {
                kinds.firstIndex(where: { model.filter.kinds.contains($0) }).map { $0 + 1 } ?? 0
            } set: { index in
                model.filter.kinds = index > 0 && index <= kinds.count ? [kinds[index - 1]] : []
            }, accessibilityID: "library.filter.kind")
            .padding(.horizontal, metrics.pageMargin)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Menu {
                        if let range = model.availableYears {
                            Picker("From", selection: $model.filter.minimumYear) {
                                Text("Any").tag(Int?.none)
                                ForEach(LibraryFiltering.decadeStarts(in: range), id: \.self) { Text(LibraryFiltering.decadeText($0)).tag(Int?.some($0)) }
                            }
                            Picker("To", selection: $model.filter.maximumYear) {
                                Text("Any").tag(Int?.none)
                                ForEach(LibraryFiltering.decadeStarts(in: range), id: \.self) { Text(LibraryFiltering.decadeText($0)).tag(Int?.some($0 + 9)) }
                            }
                        } else {
                            Text("No release years yet")
                        }
                    } label: {
                        filterLabel("Year", isActive: model.filter.minimumYear != nil || model.filter.maximumYear != nil)
                    }
                    .accessibilityIdentifier("library.filter.year")
                    Menu {
                        Button("Any") { model.filter.statuses = [] }
                        ForEach(WatchStatus.allCases) { status in
                            Toggle(status.title, isOn: membership(status, in: \.statuses))
                                .accessibilityIdentifier("library.filter.status.\(status.rawValue)")
                        }
                    } label: {
                        filterLabel("Status", tint: model.filter.statuses.contains(.watched) ? .green
                                    : model.filter.statuses.contains(.inProgress) ? .orange : .primary, isActive: !model.filter.statuses.isEmpty)
                    }
                    .accessibilityIdentifier("library.filter.status")
                    Menu {
                        RatingPicker(threshold: $model.filter.minimumRating)
                    } label: {
                        filterLabel("Rating", systemImage: "star.fill", tint: .yellow, isActive: model.filter.minimumRating != nil)
                    }
                    .accessibilityIdentifier("library.filter.rating")
                }
            }
            Menu {
                Picker("Sort by", selection: $model.filter.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                filterLabel(model.filter.sort.title, systemImage: "arrow.up.arrow.down", tint: .blue,
                            isActive: model.filter.sort != .recentlyAdded)
            }
            .accessibilityLabel("Sort by \(model.filter.sort.title)")
            .accessibilityIdentifier("library.sort")
            if !model.filter.chips.isEmpty { filterChips }
            }
            .padding(.horizontal, metrics.pageMargin)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: model.filter)
        .accessibilityIdentifier("library.filters")
    }

    private func filterLabel(_ title: String, systemImage: String? = nil, tint: Color = .primary, isActive: Bool = false) -> some View {
        FilterMenuLabel(title, systemImage: systemImage, tint: tint, isActive: isActive)
    }

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

    /// The active filters, one chip each (tap to clear it), and a chip that clears them all. The stack already adds 8pt above this view
    /// and `shelfSpacing` below it, so the padding makes those gaps 12pt above and 24pt below. The view is removed with the last chip,
    /// so clearing every filter leaves no gap behind.
    private var filterChips: some View {
        ActiveFilterChips(chips: model.filter.chips.map { chip in
            ActiveFilterChip(id: chip.id, label: chip.label) { model.removeFilter(chip) }
        }, identifier: "library", clearAll: { model.clearFilters() })
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xl - metrics.shelfSpacing)
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("Saved").padding(.horizontal, metrics.pageMargin)
            LazyVGrid(columns: metrics.posterGridColumns, spacing: metrics.gridRowSpacing) {
                ForEach(model.saved) { item in
                    MediaCardLink(item: item.preview).stretched()
                        .accessibilityIdentifier("library.saved.\(item.id)")
                        .onAppear { model.savedCardAppeared(item.id) }
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
                        .onAppear { model.watchedCardAppeared(item.id) }
                }
            }
            .padding(.horizontal, metrics.pageMargin)
        }
    }
}

/// The minimum rating, out of 10. Each title is rated by its best available score, so the menu names no site.
struct RatingPicker: View {
    @Binding var threshold: Double?

    var body: some View {
        Picker("At least", selection: $threshold) {
            Text("Any").tag(Double?.none)
            ForEach([5.0, 6, 7, 8, 9], id: \.self) { value in
                Text("\(LibraryFiltering.ratingText(value))+").tag(Double?.some(value))
            }
        }
        .accessibilityIdentifier("library.filter.rating.threshold")
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
                            ForEach(LibraryFiltering.decadeStarts(in: range), id: \.self) { Text(LibraryFiltering.decadeText($0)).tag(Int?.some($0)) }
                        }
                        Picker("To", selection: $model.filter.maximumYear) {
                            Text("Any").tag(Int?.none)
                            ForEach(LibraryFiltering.decadeStarts(in: range), id: \.self) { Text(LibraryFiltering.decadeText($0)).tag(Int?.some($0 + 9)) }
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
                Section {
                    RatingPicker(threshold: $model.filter.minimumRating)
                } header: {
                    Text("Rating")
                } footer: {
                    Text("Ratings are out of 10, using the best score available for each title.")
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
            .sensoryFeedback(.selection, trigger: model.filter)
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
