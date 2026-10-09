#if canImport(UIKit)
import SwiftUI
import PlayerKit
import StremioKit

struct LibraryView: View {
    @State private var model: LibraryViewModel
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
                                     message: "Titles you save, and anything you start watching, show up here.") {
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
                        ReleaseYearOptions(model: model)
                    } label: {
                        filterLabel("Year", isActive: model.filter.minimumYear != nil || model.filter.maximumYear != nil)
                    }
                    .accessibilityIdentifier("library.filter.year")
                    Menu {
                        RatingPicker(threshold: $model.filter.minimumRating)
                    } label: {
                        filterLabel("Rating", systemImage: "star.fill", tint: .yellow, isActive: model.filter.minimumRating != nil)
                    }
                    .accessibilityIdentifier("library.filter.rating")
                    Menu {
                        Picker("Added", selection: $model.filter.addedWithin) {
                            ForEach(AddedWithin.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        filterLabel("Added", isActive: model.filter.addedWithin != .anyTime)
                    }
                    .accessibilityIdentifier("library.filter.added")
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

    private var continueSection: some View {
        MediaRow("Continue") {
            ForEach(model.continueWatching) { item in
                NavigationLink(value: LibraryViewModel.request(for: item)) {
                    ProgressCard(title: item.title, subtitle: progressSubtitle(item), artwork: item.poster, fraction: item.fraction)
                }
                .buttonStyle(PressableCardStyle())
                .titleTapHaptic()
                .accessibilityIdentifier("library.continue.\(item.id)")
                .contextMenu {
                    Button("Mark as Watched") { Task { await model.markWatched(item); await actions?.refresh() } }
                    Button("Remove from Continue", role: .destructive) { Task { await model.removeFromContinueWatching(item) } }
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

/// The minimum rating, out of 10. Each title is rated by its best available score, so the menu names no site.
struct RatingPicker: View {
    @Binding var threshold: Double?

    var body: some View {
        Picker("At least", selection: $threshold) {
            Text("Any").tag(Double?.none)
            ForEach([5.0, 6, 7, 8, 9, 10], id: \.self) { value in
                Text("\(LibraryFiltering.ratingText(value))+").tag(Double?.some(value))
            }
        }
        .accessibilityIdentifier("library.filter.rating.threshold")
    }
}

/// Release years in ten-year spans, "1920 - 1929" up to "2020 - 2029". Choosing a span sets both ends of the year filter to it; "Any" clears it.
struct ReleaseYearOptions: View {
    let model: LibraryViewModel
    private static let starts = Array(stride(from: 1920, through: 2020, by: 10))

    var body: some View {
        Button { setSpan(nil) } label: {
            choice("Any", isOn: model.filter.minimumYear == nil && model.filter.maximumYear == nil)
        }
        ForEach(Self.starts, id: \.self) { start in
            Button { setSpan(start) } label: {
                choice("\(start) - \(start + 9)", isOn: model.filter.minimumYear == start && model.filter.maximumYear == start + 9)
            }
            .accessibilityIdentifier("library.filter.year.\(start)")
        }
    }

    private func setSpan(_ start: Int?) {
        model.filter.minimumYear = start
        model.filter.maximumYear = start.map { $0 + 9 }
    }

    @ViewBuilder private func choice(_ title: String, isOn: Bool) -> some View {
        if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

struct ProgressRow: View {
    let item: WatchProgress

    var body: some View {
        ProgressCard(title: item.title, artwork: item.poster, fraction: item.fraction)
    }
}
#endif
