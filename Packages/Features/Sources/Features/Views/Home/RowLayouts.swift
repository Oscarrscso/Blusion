#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

/// A row drawn in one of Blusion's own layouts (`RowLayout`) once its items have loaded: the row's header, then the layout. The row's
/// menu is on the header and the space around the cards; on the Mac it covers the whole row, and a card's own menu wins over it.
struct LayoutRow: View {
    let layout: RowLayout
    let title: String
    let hideTitle: Bool
    let items: [MetaPreview]
    let presentation: WidgetPresentation
    let onSeeAll: () -> Void
    let menu: AnyView
    @Environment(\.layoutMetrics) private var metrics
    @State private var zoomScope = UUID().uuidString

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            if !hideTitle {
                SectionHeader(title, onSeeAll: onSeeAll)
                    .contextMenu { menu }
                    .padding(.horizontal, metrics.pageMargin)
            }
            layoutBody
                .environment(\.layoutMetrics, metrics.layoutCards(presentation.cardStyle.cardSize))
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .contextMenu { menu }
                }
        }
        .environment(\.zoomScope, zoomScope)
        #if targetEnvironment(macCatalyst)
        .contextMenu { menu }
        #endif
    }

    @ViewBuilder
    private var layoutBody: some View {
        switch layout {
        case .mosaic: MosaicLayout(items: items, presentation: presentation)
        case .flow: FlowLayoutRow(items: items, showsRating: presentation.showsRatings)
        case .wall: WallLayout(items: items)
        case .parallax: ParallaxLayout(items: items, showsRating: presentation.showsRatings)
        case .spines: SpinesLayout(items: items, showsRating: presentation.showsRatings)
        case .slots: SlotsLayout(items: items)
        case .deck: DeckLayout(items: items, showsRating: presentation.showsRatings)
        case .snapshots: SnapshotsLayout(items: items)
        case .videoStore: VideoStoreLayout(items: items, showsRating: presentation.showsRatings)
        }
    }

    /// The height `layout` takes under its header, for the placeholder that stands in for it. Flow's is its posters' alone: its caption is
    /// text, whose room the placeholder keeps with the caption's own lines.
    static func height(of layout: RowLayout, metrics: LayoutMetrics, containerWidth: CGFloat) -> CGFloat {
        switch layout {
        case .mosaic: MosaicLayout.height(metrics)
        case .flow: FlowLayoutRow.height(metrics)
        case .wall: WallLayout.height(metrics)
        case .parallax: ParallaxLayout.height(metrics, containerWidth: containerWidth)
        case .spines: SpinesLayout.height(metrics)
        case .slots: SlotsLayout.height(metrics, containerWidth: containerWidth)
        case .deck: DeckLayout.height(metrics)
        case .snapshots: SnapshotsLayout.height(metrics)
        case .videoStore: VideoStoreLayout.height(metrics)
        }
    }
}

/// The stand-in for a layout row while its items load: its header over a shimmering panel of the layout's height.
struct LayoutRowPlaceholder: View {
    let layout: RowLayout
    /// Nil when the row hides its title.
    let title: String?
    /// The widget's card size, which the layout's height follows.
    var size: CardSize = .medium
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.heroContainerWidth) private var containerWidth

    var body: some View {
        let cards = metrics.layoutCards(size)
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            if let title {
                SectionHeader(title).padding(.horizontal, metrics.pageMargin)
            }
            VStack(spacing: layout == .flow ? Theme.Spacing.s : Theme.Spacing.m) {
                Color.clear.frame(height: LayoutRow.height(of: layout, metrics: cards, containerWidth: containerWidth))
                if layout == .flow { FlowLayoutRow.captionLines(name: " ", details: " ").hidden() }
            }
            // The slot machine's cabinet stands in the middle of the row at its own width.
            .frame(width: layout == .slots ? SlotsLayout.width(cards, containerWidth: containerWidth) : nil)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.surface * metrics.cornerScale(for: .artwork), style: .continuous)
                    .fill(Theme.surfaceStrong)
            }
            .shimmering()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.pageMargin)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Shared pieces

extension LayoutMetrics {
    /// These metrics for a layout row whose widget asks for `size` cards, as a shelf's cards follow it: the poster width the layouts are
    /// drawn from, and the card scale Parallax's cards follow, scaled by it.
    fileprivate func layoutCards(_ size: CardSize) -> LayoutMetrics {
        var metrics = self
        metrics.posterWidth = (posterWidth * size.scale).rounded()
        metrics.cardScale *= size.scale
        return metrics
    }
}

/// "Drama · 2008 · ★ 8": the first genre, the year and, when shown, the IMDb rating.
func layoutDetailLine(_ item: MetaPreview, showsRating: Bool) -> String {
    let rating = showsRating ? item.imdbRating.map { "★ \(ScoreText.wholeScore($0))" } : nil
    return [item.genres.first, item.releaseInfo, rating].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}

/// A title's poster filling `width` by `height`, decoded at the size it is drawn. Only its own frame takes touches.
struct LayoutPoster: View {
    let item: MetaPreview
    let width: CGFloat
    let height: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .overlay {
                ArtworkImage(url: PosterQuality.poster(for: item), title: item.name,
                             maxPixelSize: min((max(width, height) * displayScale).rounded(.up), 1200), keepsPictureOnShow: true)
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// A picture that opens its title, for the layouts' own cards: the push, zoom, press, tap haptic, hover and Mac menu a shelf's card has.
/// `copy` tells apart the repeats of one title in a layout that shows it more than once, so each is its own zoom source. `prewarms` false
/// leaves out the title page's artwork lookup ahead of a tap, and with it the poster's watch on whether it is on screen, for a layout
/// that moves all its posters on every frame.
struct LayoutTitleLink<Label: View>: View {
    let item: MetaPreview
    var copy = ""
    var prewarms = true
    let cornerRadius: CGFloat
    @ViewBuilder let label: () -> Label
    @Environment(\.zoomScope) private var zoomScope
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let sourceID = "\(zoomScope)/\(copy)\(item.identity)"
        let link = NavigationLink(value: TitleDestination(preview: item, sourceID: sourceID)) {
            label()
                .mediaArtwork(cornerRadius: cornerRadius)
                .zoomSource(id: sourceID, in: zoomNamespace, cornerRadius: cornerRadius * metrics.cornerScale(for: .artwork))
        }
        .buttonStyle(PressableCardStyle.poster)
        .titleTapHaptic()
        Group {
            if prewarms { link.prewarmsHeroArtwork(item) } else { link }
        }
        .help(item.name)
        .titleCardMenu(item)
        .accessibilityLabel(item.name)
    }
}

/// A title's logo in a `width` by `height` box, pinned to its bottom leading corner: the spotlight's logo (the catalog's, else TMDb's from
/// the spotlight's artwork lookup), loaded as the spotlight loads it, trimmed and made light when it is dark. Its name in bold when it has
/// none.
struct LayoutLogo: View {
    let item: MetaPreview
    let width: CGFloat
    let height: CGFloat
    @Environment(PosterRatingsStore.self) private var ratings: PosterRatingsStore?
    @State private var hero = HeroLoader()
    @State private var heroArtwork: TMDbArtwork?
    /// Set once the spotlight's artwork lookup has answered, so a title with no logo falls back to its name.
    @State private var artworkChecked = false

    private var logoCandidates: [URL] {
        HeroLogos.candidates(preview: item.logo, artwork: heroArtwork, imdbID: item.id,
                             artworkReady: artworkChecked || item.logo != nil)
    }
    private var logoURL: URL? { logoCandidates.first }

    var body: some View {
        Group {
            switch hero.slot(url: logoURL, maxPixelSize: HeroLoader.logoPixelSize, lookupFinished: artworkChecked) {
            case .ready(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            case .pending:
                Color.clear
            case .none:
                Text(item.name)
                    .appFont(style: .title3, weight: .bold, role: .display)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
        .task(id: item.identity) {
            // The catalog's own logo needs no lookup; otherwise the spotlight's artwork, known already when the title was prewarmed.
            guard item.logo == nil else { return }
            heroArtwork = ratings?.cachedHeroArtwork(for: item)
            if heroArtwork == nil { heroArtwork = await ratings?.heroArtwork(for: item) }
            guard !Task.isCancelled else { return }
            artworkChecked = true
        }
        .task(id: logoCandidates.map(\.absoluteString).joined(separator: "|")) {
            await hero.load(priority: .medium, picture: nil, pictureSize: 0, logo: logoURL, logoSize: HeroLoader.logoPixelSize,
                            logoFallbacks: Array(logoCandidates.dropFirst()))
        }
        .accessibilityHidden(true)
    }
}
#endif
