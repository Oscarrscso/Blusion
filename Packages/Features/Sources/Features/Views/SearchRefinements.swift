#if canImport(UIKit)
import SwiftUI
import StremioKit

/// The controls over Search's results, shared by both appearances: what a described search was read as asking for, as chips that
/// can be changed or removed, then the sort, genre, year and rating menus.
struct SearchRefinements: View {
    @Bindable var model: SearchViewModel
    var showsGenre = true
    /// False where the page draws the chips its own way (the editorial page's tags).
    var showsChips = true
    /// False keeps the editorial page's own row of bordered menus.
    var usesFilterBar = true

    var body: some View {
        if usesFilterBar { filterBar } else { plainRow }
    }

    /// The same filter bar as Discover and the Library: the scope selector, glass menus, then a removable chip for each active filter.
    private var filterBar: some View {
        let height = BrowseFilterBar<EmptyView>.menuHeight
        let scopes = SearchScope.allCases
        var active: [ActiveFilterChip] = model.filter.genres.map { genre in
            ActiveFilterChip(id: "genre.\(genre)", label: genre) { model.filter.genres.removeAll { $0 == genre } }
        }
        if let year = model.filter.year {
            active.append(ActiveFilterChip(id: "year", label: String(year)) { model.filter.year = nil })
        }
        if let rating = model.filter.minimumRating {
            active.append(ActiveFilterChip(id: "rating", label: "Rating \(LibraryFiltering.minimumRatingText(Double(rating)))") {
                model.filter.minimumRating = nil
            })
        }
        return BrowseFilterBar(kinds: .init(titles: scopes.map(\.title), selection: Binding {
            scopes.firstIndex(of: model.scope) ?? 0
        } set: { model.scope = scopes[$0] }, identifier: "search.filters", symbols: ["square.grid.2x2", "film", "tv", "person.2"]),
        chips: active, identifier: "search", clearAll: { model.clearFilters() }) {
            if showsChips {
                ForEach(model.chips) { chip in
                    FilterMenu(minHeight: height) { SearchChipActions(model: model, chip: chip) } label: {
                        FilterMenuLabel(chip.title, isActive: true, minHeight: height)
                    }
                    .accessibilityIdentifier("search.chip.\(chip.title)")
                }
            }
            if showsGenre {
                FilterMenu(minHeight: height) {
                    Picker("Genre", selection: $model.filter.genre) {
                        Text("Any").tag(String?.none)
                        ForEach(genres, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    FilterMenuLabel("Genre", systemImage: "tag", isActive: !model.filter.genres.isEmpty, minHeight: height)
                }
            }
            FilterMenu(minHeight: height) {
                Picker("Year", selection: $model.filter.year) {
                    Text("Any").tag(Int?.none)
                    ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                }
            } label: {
                FilterMenuLabel("Year", systemImage: "calendar", isActive: model.filter.year != nil, minHeight: height)
            }
            FilterMenu(minHeight: height) {
                Picker("Minimum rating", selection: $model.filter.minimumRating) {
                    Text("Any").tag(Int?.none)
                    ForEach(5...9, id: \.self) { Text(LibraryFiltering.minimumRatingText(Double($0))).tag(Int?.some($0)) }
                }
            } label: {
                FilterMenuLabel("Rating", systemImage: "star.fill", isActive: model.filter.minimumRating != nil, minHeight: height)
            }
            FilterMenu(minHeight: height) {
                Picker("Sort by", selection: $model.filter.sort) {
                    ForEach(SearchResultFilter.Sort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                FilterMenuLabel(model.filter.sort.title, systemImage: "arrow.up.arrow.down", isActive: model.filter.sort != .relevance,
                                minHeight: height)
            }
            .accessibilityLabel("Sort by \(model.filter.sort.title)")
        }
        .onChange(of: model.filter) { _, _ in Haptics.play(.choices) }
        .accessibilityIdentifier("search.refinements")
    }

    /// The editorial page's row: the system's bordered menus in its own tint, side by side.
    private var plainRow: some View {
        ScrollView(.horizontal) {
            HStack {
                if showsChips {
                    ForEach(model.chips) { chip in
                        Menu { SearchChipActions(model: model, chip: chip) } label: {
                            Text(chip.title).fontWeight(.semibold)
                        }
                        .accessibilityIdentifier("search.chip.\(chip.title)")
                    }
                }
                Menu {
                    Picker("Sort", selection: $model.filter.sort) {
                        ForEach(SearchResultFilter.Sort.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Label(model.filter.sort.title, systemImage: "arrow.up.arrow.down") }
                if showsGenre {
                    Menu {
                        Picker("Genre", selection: $model.filter.genre) {
                            Text("Any genre").tag(String?.none)
                            ForEach(genres, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: { Text(model.filter.genre ?? "Genre") }
                }
                Menu {
                    Picker("Year", selection: $model.filter.year) {
                        Text("Any year").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                    }
                } label: { Text(model.filter.year.map(String.init) ?? "Year") }
                Menu {
                    Picker("Minimum rating", selection: $model.filter.minimumRating) {
                        Text("Any rating").tag(Int?.none)
                        ForEach(5...9, id: \.self) { Text(LibraryFiltering.minimumRatingText(Double($0))).tag(Int?.some($0)) }
                    }
                } label: { Text(model.filter.minimumRating.map { "Rating \(LibraryFiltering.minimumRatingText(Double($0)))" } ?? "Rating") }
                if model.filter.isActive || model.filter.sort != .relevance {
                    Button("Clear", systemImage: "xmark.circle") { model.clearFilters() }
                }
            }
            .buttonStyle(PointingHandButtonStyle(style: .bordered))
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("search.refinements")
    }

    private var genres: [String] {
        Array(Set(model.availableGenres + model.filter.genres)).sorted()
    }

    private var years: [Int] {
        Array(Set(model.availableYears + [model.filter.year].compactMap { $0 })).sorted(by: >)
    }
}

/// What a chip's menu offers: the values it can be changed to, where it has any, and its removal.
struct SearchChipActions: View {
    let model: SearchViewModel
    let chip: SearchChip

    var body: some View {
        ForEach(model.options(for: chip)) { option in
            Button(option.title) {
                Haptics.play(.choices)
                model.applyDiscovery(option.plan)
            }
        }
        Button("Remove", systemImage: "xmark", role: .destructive) {
            Haptics.play(.choices)
            model.remove(chip)
        }
    }
}

/// The people a search found, as a row of portrait cards that open their pages.
struct SearchPeopleRow: View {
    let people: [TMDbTitlePerson]
    let margin: CGFloat
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                ForEach(people) { PersonCardLink(person: $0, width: SearchPeopleRow.cardWidth) }
            }
            .padding(.horizontal, margin)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("search.people")
    }

    static let cardWidth: CGFloat = 110
}

/// Pick for me: a few optional choices (kind, mood, genre, decade, length, rating), then titles that fit them in a drawn order.
/// Nothing has to be chosen. Asked again for the same choices, the picks are drawn in a new order.
struct PickControls: View {
    let model: SearchViewModel
    var onChoose: () -> Void
    @Environment(\.layoutMetrics) private var metrics
    @State private var expanded = false
    @State private var pick = SearchPick()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.controlSpacing) {
            HStack(spacing: metrics.controlSpacing) {
                Button { expanded.toggle() } label: {
                    FilterMenuLabel("Pick for me", systemImage: "sparkles", isActive: expanded,
                                    minHeight: BrowseFilterBar<EmptyView>.menuHeight)
                }
                .buttonStyle(.hoverPlain)
                .accessibilityIdentifier("search.pick")
                if model.isPickSearch {
                    Button { model.shufflePick() } label: {
                        FilterMenuLabel("Again", systemImage: "shuffle", isActive: true,
                                        minHeight: BrowseFilterBar<EmptyView>.menuHeight)
                    }
                    .buttonStyle(.hoverPlain)
                    .accessibilityIdentifier("search.pick.again")
                }
                if model.isUsingAI {
                    HStack(spacing: Theme.Spacing.xs) {
                        Spinner().controlSize(.mini)
                        Text("AI").appFont(.captionStrong)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("AI searching")
                    .accessibilityIdentifier("search.ai.active")
                }
            }
            if expanded { controls }
        }
    }

    /// True while the results are this very pick's: the button then draws them again.
    private var showsPick: Bool { model.isPickSearch && model.query == pick.title }

    private var controls: some View {
        VStack(alignment: .leading, spacing: metrics.controlSpacing) {
            Grid(horizontalSpacing: metrics.controlSpacing, verticalSpacing: metrics.controlSpacing) {
                GridRow {
                    menu("Type", selection: $pick.kind, options: TMDbDiscoverQuery.Kind.allCases) { $0.title }
                    menu("Mood", selection: $pick.mood, options: SearchPick.Mood.allCases) { $0.title }
                }
                GridRow {
                    menu("Genre", selection: $pick.genre, options: SearchPick.genres(for: pick.kind)) { $0 }
                    menu("Decade", selection: $pick.decade, options: SearchPick.decades()) { "\($0)s" }
                }
                GridRow {
                    menu("Length", selection: $pick.maximumRuntime, options: SearchPick.runtimes, name: SearchPick.runtimeTitle)
                    menu("Rating", selection: $pick.minimumScore, options: SearchPick.scores, name: SearchPick.scoreTitle)
                }
            }
            .buttonStyle(.hoverPlain)
            Button {
                onChoose()
                model.pick(pick)
            } label: {
                FilterMenuLabel(showsPick ? "Pick again" : "Pick", systemImage: showsPick ? "shuffle" : "sparkles",
                                isActive: true, minHeight: BrowseFilterBar<EmptyView>.menuHeight)
            }
            .buttonStyle(.hoverPlain)
            .disabled(showsPick && model.aiPhase == .searching)
            .accessibilityIdentifier("search.pick.go")
        }
        // Series have no genre of some films' names: such a choice does not outlive the change of kind.
        .onChange(of: pick.kind) { _, kind in
            if let genre = pick.genre, !SearchPick.genres(for: kind).contains(genre) { pick.genre = nil }
        }
    }
    private func menu<Value: Hashable>(_ title: String, selection: Binding<Value?>, options: [Value],
                                       name: @escaping (Value) -> String) -> some View {
        FilterMenu(minHeight: BrowseFilterBar<EmptyView>.menuHeight) {
            Picker(title, selection: selection) {
                Text("Any \(title.lowercased())").tag(Value?.none)
                ForEach(options, id: \.self) { Text(name($0)).tag(Value?.some($0)) }
            }
        } label: {
            FilterMenuLabel(selection.wrappedValue.map(name) ?? title, isActive: selection.wrappedValue != nil,
                            minHeight: BrowseFilterBar<EmptyView>.menuHeight)
        }
        .accessibilityIdentifier("search.pick.\(title.lowercased())")
    }
}
#endif
