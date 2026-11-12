#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Add Widget: every kind of widget drawn as Home draws it, with the same titles in each, so a widget is picked by how it looks. A style
/// opens the new widget's settings already in it; a collection or Continue Watching is added at once. Home's own views draw the
/// previews, so a change to a layout shows here too.
struct WidgetGalleryView: View {
    let model: WidgetsManagerViewModel
    let services: AppServices
    /// Leaves this page, and the settings opened from it, once a widget has been added.
    let finish: () -> Void
    @State private var creating: WidgetStyle?
    @State private var showsGenreCollection = false
    /// Set when the genre sheet adds its collection, so this page leaves once the sheet has gone.
    @State private var addedGenreCollection = false
    @State private var spotlightPage: String?
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.appAppearance) private var appearance

    /// What the page offers, in its order: the styles, then the collections and Continue Watching.
    private enum Option: Hashable, Identifiable {
        case style(WidgetStyle), genres, services, continueWatching, blusionTV

        static var all: [Option] { WidgetStyle.allCases.map(Option.style) + [.genres, .services, .continueWatching, .blusionTV] }

        var id: String {
            switch self {
            case .style(let style): style.id
            case .genres: "genres"
            case .services: "services"
            case .continueWatching: "continue"
            case .blusionTV: "tv"
            }
        }

        var name: String {
            switch self {
            case .style(let style): style.rawValue
            case .genres: "Genre Collection"
            case .services: "Streaming Services"
            case .continueWatching: "Continue Watching"
            case .blusionTV: "Blusion TV"
            }
        }

        var systemImage: String {
            switch self {
            case .style(let style): style.systemImage
            case .genres: "square.grid.2x2"
            case .services: "play.tv"
            case .continueWatching: "play.circle"
            case .blusionTV: "tv"
            }
        }
    }

    /// Home's margins, which its rows are drawn with.
    private var homeMetrics: LayoutMetrics {
        var homeMetrics = metrics
        homeMetrics.pageMargin = metrics.contentMargin
        return homeMetrics
    }

    private var hasGenres: Bool { model.catalogChoices.contains { !$0.genres.isEmpty } }
    private var hasContinue: Bool { model.widgets.contains { $0.content == .continueWatching } }
    private var hasTV: Bool { model.widgets.contains { $0.content == .blusionTV } }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Option.all) { option in
                        // A faint line parts each two, as it parts a title page's sections.
                        if option != Option.all.first {
                            TitleSectionLine(contentMargin: homeMetrics.pageMargin)
                                .padding(.vertical, homeMetrics.titleRatingsGap)
                        }
                        row(option)
                    }
                }
                // The Mac's room for its navigation is this page's own top margin; the shelves inside the previews must not take it too,
                // or their cards sit that far below their heading.
                .contentMargins(.top, 0, for: .scrollContent)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.visible, axes: .vertical)
            .scrollIndicatorsFlash(onAppear: true)
            .screenBackground()
            .environment(\.heroContainerWidth, geometry.size.width)
            .environment(\.heroContainerHeight, geometry.size.height)
            .environment(\.layoutMetrics, homeMetrics)
        }
        .navigationTitle("Add Widget")
        .navigationBarTitleDisplayMode(.inline)
        .macBackNavigation()
        .accessibilityIdentifier("widgets.gallery")
        .navigationDestination(item: $creating) { WidgetEditorView(style: $0, model: model, services: services, onAdded: finish) }
        .sheet(isPresented: $showsGenreCollection, onDismiss: {
            if addedGenreCollection { finish() }
        }) {
            NavigationStack {
                GenreCollectionPicker(model: model) { choice, genres in
                    let title = GenreCollectionPicker.title(for: choice)
                    Task { await model.add(WidgetsManagerViewModel.makeGenreCollection(title: title, choice: choice, genres: genres)) }
                    addedGenreCollection = true
                    showsGenreCollection = false
                }
            }
        }
    }

    private func add(_ widget: HomeWidget) {
        Task { await model.add(widget) }
        finish()
    }

    private func isEnabled(_ option: Option) -> Bool {
        switch option {
        case .genres: hasGenres
        case .continueWatching: !hasContinue
        case .blusionTV: !hasTV
        case .style, .services: true
        }
    }

    private func isAdded(_ option: Option) -> Bool {
        (option == .continueWatching && hasContinue) || (option == .blusionTV && hasTV)
    }

    private func choose(_ option: Option) {
        switch option {
        case .style(let style): creating = style
        case .genres: showsGenreCollection = true
        case .services: add(WidgetsManagerViewModel.makeServicesCollection())
        case .continueWatching: add(HomeWidget(title: "Continue", content: .continueWatching))
        case .blusionTV: add(HomeWidget(title: "Blusion TV", content: .blusionTV))
        }
    }

    /// One kind of widget: its symbol and name with Add beside them, over its preview. The preview takes no touches of its own, and a tap
    /// on it is Add's.
    private func row(_ option: Option) -> some View {
        let enabled = isEnabled(option)
        return VStack(alignment: .leading, spacing: homeMetrics.headerSpacing) {
            HStack(spacing: Theme.Spacing.m) {
                Label {
                    Text(option.name)
                        .headingStyle()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: option.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                // Continue Watching and Blusion TV are one of a kind: once on Home they read Added.
                Button { choose(option) } label: {
                    Text(isAdded(option) ? "Added" : "Add")
                        .fontWeight(.semibold)
                        .pointerFeedback()
                }
                .finishedProminentButtonStyle(appearance.buttonFinish)
                .buttonBorderShape(metrics.cornerScale(for: .actionButtons) == 1
                    ? .capsule : .roundedRectangle(radius: Theme.Radius.surface * metrics.cornerScale(for: .actionButtons)))
                .controlSize(.small)
                .disabled(!enabled)
                .accessibilityLabel(isAdded(option) ? "\(option.name) Added" : "Add \(option.name)")
                .accessibilityIdentifier("widgets.gallery.\(option.id)")
            }
            .padding(.horizontal, homeMetrics.pageMargin)
            preview(option)
                .allowsHitTesting(false)
                .opacity(enabled ? 1 : 0.4)
                .overlay {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { choose(option) }
                        .buttonCursor(enabled)
                        .allowsHitTesting(enabled)
                }
                .accessibilityHidden(true)
        }
    }

    // MARK: Previews

    @ViewBuilder
    private func preview(_ option: Option) -> some View {
        switch option {
        case .style(let style): preview(of: style)
        case .genres: genresPreview
        case .services: servicesPreview
        case .continueWatching: continuePreview
        case .blusionTV: tvPreview
        }
    }

    @ViewBuilder
    private func preview(of style: WidgetStyle) -> some View {
        switch style {
        case .row:
            MediaRow(style.rawValue, hideTitle: true) {
                ForEach(GallerySamples.items) { MediaCard(item: $0) }
            }
        case .spotlight:
            HeroCarousel(items: GallerySamples.items, pageID: $spotlightPage, menu: AnyView(EmptyView()))
        case .banner:
            HeroBanner(items: GallerySamples.items, row: RowConfiguration(source: .unsupported(kind: "")))
        default:
            // Every other style is one of Blusion's own layouts.
            if let layout = style.layout {
                LayoutRow(layout: layout, title: style.rawValue, hideTitle: true, items: GallerySamples.items,
                          presentation: WidgetPresentation(), onSeeAll: {}, menu: AnyView(EmptyView()))
            }
        }
    }

    /// Genre tiles, each with a title's backdrop, as Home's genre collections show them.
    private var genresPreview: some View {
        MediaRow("Genre Collection", hideTitle: true) {
            ForEach(Array(GallerySamples.genres.enumerated()), id: \.offset) { index, genre in
                let item = GallerySamples.items[index % GallerySamples.items.count]
                CollectionTile(title: genre, imageURL: item.background)
            }
        }
    }

    /// The services collection's own tiles: each service's logo on its colour.
    private var servicesPreview: some View {
        let widget = WidgetsManagerViewModel.makeServicesCollection()
        let tiles: [CollectionItem]
        if case .collection(let items) = widget.content { tiles = items } else { tiles = [] }
        return MediaRow(widget.title, hideTitle: true) {
            ForEach(tiles) { tile in
                CollectionTile(title: tile.title, provider: StreamProvider(tileTitle: tile.title), aspect: tile.imageAspect.cardAspect)
            }
        }
    }

    /// Wide cards with their progress, as Continue Watching shows titles in progress.
    private var continuePreview: some View {
        MediaRow("Continue Watching", hideTitle: true, aspect: .wide, cardWidth: homeMetrics.continueCardWidth) {
            ForEach(Array(GallerySamples.items.prefix(6).enumerated()), id: \.offset) { index, item in
                ProgressCard(title: item.name, artwork: item.background, logo: item.logo, fraction: [0.62, 0.3, 0.84][index % 3],
                             duration: 7200, width: homeMetrics.continueCardWidth)
            }
        }
    }

    /// Channels on Continue Watching's cards, each with what is on now and what follows, as Home's Blusion TV shows them.
    private var tvPreview: some View {
        let shows = GallerySamples.items.filter { $0.type == "series" } + GallerySamples.items.filter { $0.type != "series" }
        return MediaRow("Blusion TV", hideTitle: true, aspect: .wide, cardWidth: homeMetrics.continueCardWidth) {
            ForEach(Array(["Drama", "Late Night", "Classics", "Weekend"].enumerated()), id: \.offset) { index, channel in
                let item = shows[index]
                VStack(alignment: .leading, spacing: 2) {
                    ProgressCard(title: item.name, subtitle: "S\(index + 1) E\(index + 4)", artwork: item.background, logo: item.logo,
                                 fraction: [0.45, 0, 0.7, 0][index], duration: 2700, width: homeMetrics.continueCardWidth)
                        .padding(.bottom, Theme.Spacing.xs)
                    TVCardCaption(caption: channel, detail: "Next · \(shows[index + 1].name)")
                }
                .frame(width: homeMetrics.continueCardWidth, alignment: .leading)
            }
        }
    }
}

/// Fixed titles, so every preview on the page shows the same artwork.
private enum GallerySamples {
    static let items: [MetaPreview] = [
        title("tt0816692", "movie", "Interstellar", "2014", 8.7, ["Sci-Fi", "Drama"]),
        title("tt0468569", "movie", "The Dark Knight", "2008", 9.0, ["Action", "Crime"]),
        title("tt0903747", "series", "Breaking Bad", "2008–2013", 9.5, ["Crime", "Drama"]),
        title("tt1375666", "movie", "Inception", "2010", 8.8, ["Action", "Sci-Fi"]),
        title("tt15398776", "movie", "Oppenheimer", "2023", 8.3, ["Biography", "Drama"]),
        title("tt0944947", "series", "Game of Thrones", "2011–2019", 9.2, ["Fantasy", "Drama"]),
        title("tt0133093", "movie", "The Matrix", "1999", 8.7, ["Action", "Sci-Fi"]),
        title("tt0111161", "movie", "The Shawshank Redemption", "1994", 9.3, ["Drama"]),
        title("tt0120737", "movie", "The Lord of the Rings", "2001", 8.9, ["Adventure", "Fantasy"]),
        title("tt1160419", "movie", "Dune", "2021", 8.0, ["Sci-Fi", "Adventure"]),
        title("tt0110912", "movie", "Pulp Fiction", "1994", 8.8, ["Crime", "Drama"]),
        title("tt0245429", "movie", "Spirited Away", "2001", 8.6, ["Animation", "Fantasy"]),
    ]

    static let genres = ["Action", "Comedy", "Drama", "Sci-Fi", "Thriller", "Animation"]

    private static func title(_ id: String, _ type: String, _ name: String, _ year: String, _ rating: Double,
                              _ genres: [String]) -> MetaPreview {
        MetaPreview(id: id, type: type, name: name, poster: MetahubArtwork.poster(imdbID: id),
                    background: MetahubArtwork.background(imdbID: id), logo: MetahubArtwork.logo(imdbID: id),
                    releaseInfo: year, imdbRating: rating, genres: genres)
    }
}
#endif
