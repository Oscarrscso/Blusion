#if canImport(UIKit)
import SwiftUI

struct SearchRefinements: View {
    @Bindable var model: SearchViewModel
    var showsGenre = true

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
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
                    Picker("Minimum IMDb rating", selection: $model.filter.minimumRating) {
                        Text("Any rating").tag(Int?.none)
                        ForEach(5...9, id: \.self) { Text("\($0)+").tag(Int?.some($0)) }
                    }
                } label: { Text(model.filter.minimumRating.map { "IMDb \($0)+" } ?? "IMDb") }
                if model.filter.isActive || model.filter.sort != .relevance {
                    Button("Clear", systemImage: "xmark.circle") { model.clearFilters() }
                }
            }
            .buttonStyle(.bordered)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("search.refinements")
    }

    private var genres: [String] {
        Array(Set(model.availableGenres + [model.filter.genre].compactMap { $0 })).sorted()
    }

    private var years: [Int] {
        Array(Set(model.availableYears + [model.filter.year].compactMap { $0 })).sorted(by: >)
    }
}

struct TonightControls: View {
    let model: SearchViewModel
    var onChoose: () -> Void
    @State private var expanded = false
    @State private var mood = "Funny"
    @State private var minutes = 120

    var body: some View {
        DisclosureGroup("Pick something for me", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Mood", selection: $mood) {
                    ForEach(["Funny", "Feel-good", "Tense", "Scary", "Romantic", "Mind-bending"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Picker("Time available", selection: $minutes) {
                    ForEach([90, 120, 150, 180], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                HStack {
                    Button("Find three films", systemImage: "sparkles") {
                        onChoose()
                        model.chooseTonight(mood: mood, minutes: minutes)
                    }
                    .disabled(model.aiPhase == .searching && model.isTonightSearch)
                    if model.isTonightSearch && !model.describedItems.isEmpty {
                        Button("Reshuffle", systemImage: "shuffle") { model.reshuffleTonight() }
                    }
                }
                .buttonStyle(.bordered)
            }
            .pickerStyle(.menu)
            .padding(.top, 8)
        }
        .accessibilityIdentifier("search.tonight")
    }
}
#endif

