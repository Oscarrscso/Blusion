#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

#if targetEnvironment(macCatalyst)
/// The title page's hero on a Mac. The picture runs the full width of the window, darker on its left, and the title, the actions and the
/// ratings sit over its lower left edge. Beneath it the trailer's panel and the synopsis share a column, with the information beside them
/// when the window is wide enough for two. The page supplies the controls, the panel, the synopsis and the information, so the state they
/// keep stays on the page.
struct DesktopDetailHero<Controls: View, Trailer: View, Synopsis: View, Information: View>: View {
    let model: DetailViewModel
    /// The page's own size: the full width of the window's content, and its height.
    let size: CGSize
    let contentMargin: CGFloat
    let pictureSlot: HeroSlot
    let logoSlot: HeroSlot
    let isRevealed: Bool
    /// False hides the trailer's panel, the synopsis, the information and the ratings, leaving the picture, the title and the controls. The
    /// page then shows its streams under them.
    let showsDetails: Bool
    @ViewBuilder let controls: Controls
    /// The trailer's panel, at the width its column gives it.
    let trailer: (CGFloat) -> Trailer
    @ViewBuilder let synopsis: Synopsis
    @ViewBuilder let information: Information

    /// The hero's height: most of the window, kept between 440 and 620 points.
    private var heroHeight: CGFloat { min(max(size.height * 0.62, 440), 620) }
    /// The widest the title, the actions and the ratings are, over the picture's lower left edge.
    private static var textWidth: CGFloat { 560 }
    /// The widest and tallest the title's logo is on this page.
    private static var logoBox: CGSize { CGSize(width: 420, height: 120) }
    /// The page's width from which the synopsis and the information sit side by side.
    private static var twoColumnWidth: CGFloat { 900 }
    /// The information's column beside the synopsis, and the gap between them.
    private static var informationWidth: CGFloat { 300 }
    private static var columnGap: CGFloat { 48 }
    /// The widest the synopsis and the trailer's panel run, so their lines stay readable on a wide window.
    private static var detailsMax: CGFloat { 640 }

    /// The page's width less its margins.
    private var contentWidth: CGFloat { max(0, size.width - contentMargin * 2) }
    private var hasTwoColumns: Bool { contentWidth >= Self.twoColumnWidth }
    /// The synopsis and the trailer's panel share this width: beside the information when there are two columns.
    private var detailsWidth: CGFloat {
        let beside = hasTwoColumns ? Self.columnGap + Self.informationWidth : 0
        return min(Self.detailsMax, contentWidth - beside)
    }

    /// The trailer's panel fades in and grows from its top edge, so the synopsis moves down with it rather than jumping.
    private static var trailerTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }

    @ViewBuilder
    var body: some View {
        hero
        if showsDetails {
            details
                .transition(.opacity)
        }
    }

    /// The picture across the window, with the title and the controls over its lower left edge, and the ratings beside the picture's
    /// bottom right corner.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            HeroPicture(slot: pictureSlot, isRevealed: isRevealed, contentMode: .fill, alignment: .center, preview: model.preview,
                        standInFromBackdrop: true)
            // Darker on the left, where the text sits, so the title and the buttons read over the picture.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.85), location: 0),
                .init(color: .black.opacity(0.35), location: 0.5),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false)
            BottomFade(length: 0.6)
            textColumn
        }
        .frame(width: size.width, height: heroHeight)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            PosterRatingsOverlay(item: model.preview, isLandscape: true, startsLoading: model.hasSettledHero)
        }
    }

    /// The title, the metadata line and, once the details show, the overview and the ratings, then the actions: one column over the
    /// picture's lower left edge, in the order the Mac's title page sets them.
    private var textColumn: some View {
        VStack(alignment: .leading, spacing: TitleHero.logoTextGap) {
            titleArt
            metaLine
            if showsDetails {
                overview
                RatingButtonsRow(item: model.detail.preview, startsLoading: model.hasSettledHero)
                    .padding(.bottom, Theme.Spacing.s)
            }
            controls
        }
        .frame(maxWidth: Self.textWidth, alignment: .leading)
        .padding(.leading, contentMargin)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
    }

    /// The metadata line, the same text as iPhone's, set over the picture's left edge. Like iPhone's, it drops genres before the rating.
    private var metaLine: some View {
        MetaLine(model.heroMetaLine, genres: model.heroMetaGenres, identifier: "detail.metaLine", spreads: true)
    }

    /// The overview, cut to three lines and not expandable: its full text, and More, are in the details below the hero.
    @ViewBuilder
    private var overview: some View {
        if let description = model.detail.preview.description, !description.isEmpty {
            JustifiedText(text: description, color: UIColor.white.withAlphaComponent(0.85), lineLimit: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("detail.overview")
        }
    }

    private var titleArt: some View {
        HeroTitleArt(name: model.detail.name, slot: logoSlot, alignment: .leading, compact: false, logoBox: Self.logoBox)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Hidden rather than removed, so the layout does not move when the title appears.
            .opacity(isRevealed ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.detail.name)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail.title")
    }

    /// Beneath the hero: the trailer's panel and the synopsis in one column, and the information beside them on a wide window or under
    /// them on a narrow one. One layout serves both widths, so the trailer's player keeps its place in the view tree when the window
    /// crosses the two-column width; a different container there would rebuild the player during playback.
    @ViewBuilder
    private var details: some View {
        layout {
            detailsColumn
            information
                .frame(maxWidth: hasTwoColumns ? Self.informationWidth : Self.detailsMax, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, contentMargin)
        .padding(.top, Theme.Spacing.xxl)
    }

    /// Side by side on a wide page, stacked on a narrow one.
    private var layout: AnyLayout {
        hasTwoColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Self.columnGap))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xl))
    }

    /// The trailer's panel, when it has one to show, above the synopsis. The panel is the same view the iPhone page places above the
    /// synopsis, so the two read in the same order.
    private var detailsColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if model.trailer.showsPanel {
                trailer(detailsWidth)
                    .transition(Self.trailerTransition)
            }
            synopsis
        }
        .frame(width: detailsWidth, alignment: .leading)
    }
}
#endif
#endif
