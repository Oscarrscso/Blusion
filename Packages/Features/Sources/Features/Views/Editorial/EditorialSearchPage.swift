#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// Search on the editorial pages. Idle, it is a black page set like a film magazine's index: an underlined SEARCH field, the genres in
/// capitals beside their label, and a featured title low on the page over its own poster drawn as a two-tone silhouette in the accent.
/// With a query the page turns to the accent with black type: BACK, SEARCH RESULTS, the results as staggered stills in Appearance's
/// tone with their captions, the filters as black tags with ×, a dashed place to add one, and the genres list. The field stays where it
/// is between the two, so typing never drops the keyboard. The search itself, its filters, people, suggestions and chips are the
/// standard page's (`SearchViewModel`); only how they are drawn is this page's own.
struct EditorialSearchPage: View {
    @Bindable var model: SearchViewModel
    let services: AppServices
    /// The results as the standard page lists them, already narrowed to the type chosen.
    let results: [MetaPreview]
    let isLoading: Bool
    @Environment(AppRouter.self) private var router
    @Environment(\.appAppearance) private var appearance
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(PosterRatingsStore.self) private var ratingsStore: PosterRatingsStore?
    @FocusState private var isFieldFocused: Bool
    @State private var showsAllGenres = false
    /// The title low on the idle page, and the silhouette behind it: one of the first genre's titles.
    @State private var featured: MetaPreview?

    private static let shownGenres = 16
    private static let tagWidth: CGFloat = 238
    private static let tagHeight: CGFloat = 48
    /// How far every other tag stands in from the right, as the mockup staggers them.
    private static let tagStep: CGFloat = 56

    /// A filter on the results, drawn as a black tag: the kind shown, when it is not All, each genre, and each requirement a
    /// described search was read as asking for.
    private enum Tag: Identifiable, Hashable {
        case scope(String)
        case genre(String)
        case chip(SearchChip)

        var id: String {
            switch self {
            case .scope: "scope"
            case .genre(let genre): "genre.\(genre)"
            case .chip(let chip): "chip.\(chip.title)"
            }
        }

        var title: String {
            switch self {
            case .scope(let title), .genre(let title): title
            case .chip(let chip): chip.title
            }
        }
    }

    private var hasQuery: Bool { !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Black on the accent, white on black.
    private var ink: Color { hasQuery ? .black : .white }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                field
                PickControls(model: model) { isFieldFocused = false }
                    .padding(.vertical, Theme.Spacing.m)
                if hasQuery {
                    resultsPage.transition(.opacity)
                } else {
                    browsePage.transition(.opacity)
                }
            }
            .padding(.horizontal, Editorial.margin)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background { ground }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .animation(.smooth(duration: 0.35), value: hasQuery)
        .onChange(of: hasQuery, initial: true) { _, has in
            router.showsAccentPage = has
        }
        // Every arrival on Search, and every tap on its capsule, puts the cursor in the field, as the standard page does.
        .onChange(of: router.searchFocusRevision, initial: true) { focusField() }
        .onChange(of: router.searchPath.count) { _, count in
            if count > 0 { isFieldFocused = false }
        }
        .task(id: model.categories.first?.id) { await loadFeatured() }
        .accessibilityIdentifier("editorial.search")
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: Theme.Spacing.s) {
            TextField("Search", text: $model.query, prompt: Text("SEARCH").foregroundStyle(ink.opacity(0.9)))
                .font(Editorial.font(.body))
                .foregroundStyle(ink)
                .tint(ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFieldFocused)
                .onSubmit { Task { await model.submit() } }
                .accessibilityIdentifier("editorial.search.field")
            Button {
                if hasQuery {
                    Haptics.play(.buttons)
                    model.query = ""
                }
                isFieldFocused = true
            } label: {
                Image(systemName: hasQuery ? "xmark" : "magnifyingglass")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(ink)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.hoverPlain)
            .accessibilityLabel(hasQuery ? "Clear" : "Search")
        }
        .padding(.vertical, Theme.Spacing.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ink).frame(height: 1).allowsHitTesting(false)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    /// Puts the cursor in the field. The field is not there in the frame the tab changes, so the focus is asked for again a moment later.
    private func focusField() {
        guard router.tab == .search, router.searchPath.isEmpty else { return }
        isFieldFocused = true
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard router.tab == .search, router.searchPath.isEmpty else { return }
            isFieldFocused = true
        }
    }

    // MARK: Idle

    @ViewBuilder
    private var browsePage: some View {
        if model.showsNoSearchableAddons {
            EmptyStateView("No addon can search", systemImage: "magnifyingglass",
                           actionTitle: "Open Addons", action: { router.showAddons() })
                .padding(.top, 80)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Text("Genres")
                        .font(Editorial.font(.body))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    genreList
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.white)
                // The silhouette behind can be light where the type crosses it.
                .shadow(color: .black.opacity(0.6), radius: 8)
                .padding(.top, 56)
                if let featured {
                    featuredTitle(featured)
                        .padding(.top, 88)
                        .transition(.opacity)
                }
            }
        }
    }

    private var genreList: some View {
        let genres = showsAllGenres ? model.categories : Array(model.categories.prefix(Self.shownGenres))
        let hidden = model.categories.count - genres.count
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(genres) { genre in
                NavigationLink(value: CatalogListRequest(title: genre.name, sources: genre.sources)) {
                    Text(genre.name.uppercased())
                        .font(Editorial.font(size: 21))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hoverPlain)
                .titleTapHaptic()
                .accessibilityIdentifier("search.genre.\(genre.name)")
            }
            if hidden > 0 {
                Button {
                    Haptics.play(.buttons)
                    withAnimation(.smooth(duration: 0.35)) { showsAllGenres = true }
                } label: {
                    Text("+ \(hidden)")
                        .font(Editorial.font(.footnote))
                        .foregroundStyle(Theme.faintText)
                        .padding(.vertical, Theme.Spacing.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hoverPlain)
                .padding(.top, 40)
                .accessibilityLabel("Show \(hidden) more genres")
            }
        }
    }

    private func featuredTitle(_ item: MetaPreview) -> some View {
        let sourceID = "editorial.featured/\(item.identity)"
        return NavigationLink(value: TitleDestination(preview: item, sourceID: sourceID)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ArtworkImage(url: item.poster, title: item.name, maxPixelSize: 400)
                    .frame(width: 86, height: 128)
                    .clipped()
                    .zoomSource(id: sourceID, in: zoomNamespace)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.uppercased())
                        .font(Editorial.font(size: 24, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(Editorial.captionLine(year: item.releaseInfo, certification: ratingsStore?.cachedCertification(for: item),
                                               runtime: item.runtime))
                        .font(Editorial.font(.caption))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 220, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.hoverPlain)
        .titleTapHaptic()
        .accessibilityIdentifier("editorial.search.featured")
    }

    /// One of the first genre's titles with a poster, chosen once for the page.
    private func loadFeatured() async {
        guard featured == nil, let genre = model.categories.first else { return }
        let items = (try? await services.widgetContent.items(for: genre.sources, limit: 20)) ?? []
        guard !Task.isCancelled else { return }
        let chosen = items.filter { $0.poster != nil }.randomElement()
        withAnimation(.smooth(duration: 0.4)) { featured = chosen }
    }

    /// Black, with the featured title's poster as a two-tone silhouette in the accent while idle; the accent itself under the results.
    private var ground: some View {
        ZStack {
            Color.black
            if !hasQuery, let poster = featured?.poster {
                ArtworkImage(url: poster, title: "", maxPixelSize: 900)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .grayscale(1)
                    .contrast(2.4)
                    .colorMultiply(appearance.editorialAccent)
                    .opacity(0.75)
                    .transition(.opacity)
            }
            appearance.editorialAccent.opacity(hasQuery ? 1 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Results

    private var resultsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                EditorialBackButton(ink: .black) {
                    model.query = ""
                    isFieldFocused = false
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: -6) {
                    Text("SEARCH")
                    Text("RESULTS")
                }
                .font(Editorial.font(size: 46, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, Theme.Spacing.xl)
            SearchRefinements(model: model, showsGenre: false, showsChips: false, usesFilterBar: false)
                .tint(.black)
                .padding(.top, Theme.Spacing.l)
            if let correction = model.correction {
                Button {
                    Haptics.play(.buttons)
                    Task { await model.applyCorrection() }
                } label: {
                    Text("DID YOU MEAN \(correction.uppercased())?")
                        .font(Editorial.font(.body))
                        .underline()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hoverPlain)
                .padding(.top, Theme.Spacing.l)
                .accessibilityIdentifier("search.correction")
            }
            if model.scope != .people { resultRow.padding(.top, 40) }
            if model.scope == .all || model.scope == .people { peopleRow.padding(.top, 40) }
            tagStack
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 48)
            genresMenu
                .padding(.top, 56)
        }
        .foregroundStyle(.black)
    }

    /// The people found, as portraits in Appearance's tone with their names in capitals. On People alone, the place of the results.
    @ViewBuilder
    private var peopleRow: some View {
        if !model.people.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 6) {
                    ForEach(model.people) { EditorialPersonCard(person: $0) }
                }
                .padding(.horizontal, Editorial.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Editorial.margin)
        } else if model.scope == .people {
            Group {
                if isLoading {
                    ProgressView().tint(.black)
                } else {
                    Text(model.isOffline ? "OFFLINE" : "NO RESULTS")
                        .font(Editorial.font(size: 32, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .leading)
        }
    }

    @ViewBuilder
    private var resultRow: some View {
        let items = results
        if items.isEmpty {
            Group {
                if isLoading {
                    ProgressView().tint(.black)
                } else {
                    Text(model.isOffline ? "OFFLINE" : "NO RESULTS")
                        .font(Editorial.font(size: 32, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                        EditorialResultCard(item: item, isTall: index % 2 == 1)
                    }
                }
                .padding(.horizontal, Editorial.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Editorial.margin)
        }
    }

    // MARK: Filters

    private var activeTags: [Tag] {
        let scope: [Tag] = model.scope == .all ? [] : [.scope(model.scope.title)]
        return scope + model.chips.map { Tag.chip($0) } + model.filter.genres.map { Tag.genre($0) }
    }

    /// The genres the results carry, the most common first; before any carry one, the genres Search browses.
    private var availableGenres: [String] {
        var counts: [String: Int] = [:]
        // Counted before the genre filter, so choosing one genre does not take the others off the list.
        for genre in model.availableGenres { counts[genre, default: 0] += 0 }
        for item in results {
            for genre in item.genres where !genre.isEmpty { counts[genre, default: 0] += 1 }
        }
        let found = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        return Array((found.isEmpty ? model.categories.map(\.name) : found).prefix(30))
    }

    /// The tags stacked from the right, every other one standing in, then the dashed place to add one. The newest of two or more lies
    /// askew across the bottom, where it was dropped, as the mockup's does.
    private var tagStack: some View {
        let tags = activeTags
        let tossed = tags.count > 1 ? tags.last : nil
        let settled = tossed == nil ? tags : Array(tags.dropLast())
        return VStack(alignment: .trailing, spacing: 2) {
            ForEach(Array(settled.enumerated()), id: \.element.id) { index, tag in
                tagView(tag)
                    .padding(.trailing, index.isMultiple(of: 2) ? Self.tagStep : 0)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            addTag
                .padding(.trailing, settled.count.isMultiple(of: 2) ? Self.tagStep : 0)
            if let tossed {
                tagView(tossed)
                    .rotationEffect(.degrees(-12))
                    .padding(.trailing, Self.tagStep + 40)
                    .padding(.top, -14)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.standard, value: tags)
    }

    /// A tag removes its filter on a tap. One whose requirement can be changed (the kind, years, runtime or score a described
    /// search asked for) opens the values it can take, with its removal.
    @ViewBuilder
    private func tagView(_ tag: Tag) -> some View {
        if case .chip(let chip) = tag, !model.options(for: chip).isEmpty {
            Menu { SearchChipActions(model: model, chip: chip) } label: { tagLabel(tag, systemImage: "chevron.down") }
                .tint(.black)
                .accessibilityLabel(tag.title)
        } else {
            Button { remove(tag) } label: { tagLabel(tag, systemImage: "xmark") }
                .buttonStyle(.hoverPlain)
                .accessibilityLabel("Remove \(tag.title)")
        }
    }

    private func tagLabel(_ tag: Tag, systemImage: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(tag.title.uppercased())
                .font(Editorial.font(.body))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 18)
        .frame(width: Self.tagWidth, height: Self.tagHeight)
        .background(Color.black)
        .contentShape(Rectangle())
    }

    private var addTag: some View {
        Menu { filterOptions } label: {
            ZStack {
                Rectangle().fill(.black.opacity(0.1))
                Rectangle().strokeBorder(.black.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.black.opacity(0.45))
            }
            .frame(width: Self.tagWidth, height: Self.tagHeight)
            .contentShape(Rectangle())
        }
        .tint(.black)
        .accessibilityLabel("Add a filter")
        .accessibilityIdentifier("editorial.search.addFilter")
    }

    private var genresMenu: some View {
        Menu { filterOptions } label: {
            HStack {
                Text("GENRES LIST").font(Editorial.font(.body))
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .regular))
            }
            .foregroundStyle(.black)
            .padding(.vertical, Theme.Spacing.s)
            .overlay(alignment: .bottom) { Rectangle().fill(.black).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .tint(.black)
        .accessibilityIdentifier("editorial.search.genres")
    }

    @ViewBuilder
    private var filterOptions: some View {
        Section("Show") {
            ForEach(SearchScope.allCases) { scope in
                Button { choose(scope) } label: {
                    if scope == model.scope {
                        Label(scope.title, systemImage: "checkmark")
                    } else {
                        Text(scope.title)
                    }
                }
            }
        }
        Section("Genres") {
            ForEach(availableGenres, id: \.self) { genre in
                Button { toggle(genre) } label: {
                    if model.filter.genres.contains(genre) {
                        Label(genre, systemImage: "checkmark")
                    } else {
                        Text(genre)
                    }
                }
            }
        }
    }

    private func choose(_ scope: SearchScope) {
        guard scope != model.scope else { return }
        Haptics.play(.choices)
        withAnimation(Theme.Motion.standard) { model.scope = scope }
    }

    private func toggle(_ genre: String) {
        Haptics.play(.choices)
        withAnimation(Theme.Motion.standard) {
            if let index = model.filter.genres.firstIndex(of: genre) {
                model.filter.genres.remove(at: index)
            } else {
                model.filter.genres.append(genre)
            }
        }
    }

    private func remove(_ tag: Tag) {
        Haptics.play(.choices)
        withAnimation(Theme.Motion.standard) {
            switch tag {
            case .scope: model.scope = .all
            case .genre(let genre): model.filter.genres.removeAll { $0 == genre }
            case .chip(let chip): model.remove(chip)
            }
        }
    }
}

/// One person on the editorial results: the portrait in Appearance's artwork tone, the name in capitals and what they are known
/// for under it. Opens the person's page.
private struct EditorialPersonCard: View {
    let person: TMDbTitlePerson
    @Environment(\.appAppearance) private var appearance
    static let width: CGFloat = 132

    var body: some View {
        NavigationLink(value: PersonDestination(id: person.id, name: person.name, profile: person.profile)) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkImage(url: person.profile, title: person.name, maxPixelSize: 400, contentMode: .fill)
                    .frame(width: Self.width, height: 178)
                    .clipped()
                    .artworkTone(appearance.artworkTone)
                Text(person.name.uppercased())
                    .font(Editorial.font(size: 21, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let role = person.roleText {
                    Text(role.uppercased())
                        .font(Editorial.font(.caption))
                        .opacity(0.75)
                }
            }
            .frame(width: Self.width, alignment: .leading)
            .foregroundStyle(.black)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle.poster)
        .titleTapHaptic()
        .accessibilityIdentifier("editorial.person.\(person.id)")
    }
}

/// One result on the editorial results: its still in Appearance's artwork tone in a square frame, every other one taller, as the mockup
/// staggers them, with its name in capitals and the year, rating and runtime under it.
private struct EditorialResultCard: View {
    let item: MetaPreview
    let isTall: Bool
    @Environment(\.appAppearance) private var appearance
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(PosterRatingsStore.self) private var ratingsStore: PosterRatingsStore?
    static let width: CGFloat = 178

    var body: some View {
        let sourceID = "editorial.results/\(item.identity)"
        NavigationLink(value: TitleDestination(preview: item, sourceID: sourceID)) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkImage(url: item.background ?? MetahubArtwork.background(imdbID: item.id), title: item.name, maxPixelSize: 600,
                             fallbackURL: item.poster)
                    .frame(width: Self.width, height: isTall ? 236 : 178)
                    .clipped()
                    .artworkTone(appearance.artworkTone)
                    .zoomSource(id: sourceID, in: zoomNamespace)
                Text(item.name.uppercased())
                    .font(Editorial.font(size: 21, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(Editorial.captionLine(year: item.releaseInfo, certification: ratingsStore?.cachedCertification(for: item),
                                           runtime: item.runtime))
                    .font(Editorial.font(.caption))
                    .opacity(0.75)
            }
            .frame(width: Self.width, alignment: .leading)
            .foregroundStyle(.black)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle.poster)
        .titleTapHaptic()
        .accessibilityIdentifier("editorial.result.\(item.identity)")
    }
}
#endif

