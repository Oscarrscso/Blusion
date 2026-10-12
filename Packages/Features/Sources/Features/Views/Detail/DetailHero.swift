#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The title page's hero. In portrait the picture runs under the bar with the logo low on it, and the controls, the trailer's panel and the
/// synopsis sit beneath it. In landscape the picture is beside the title and its controls, with the trailer's panel and the synopsis under
/// them. The trailer's panel is there only while the trailer has one to show, and then pushes the synopsis down. The page supplies the
/// controls, the panel and the synopsis, so the state they keep stays on the page and survives a rotation.
struct DetailHero<Controls: View, TrailerPanel: View, Synopsis: View>: View {
    let model: DetailViewModel
    let size: CGSize
    let contentMargin: CGFloat
    /// The least space kept clear above the logo.
    let topInset: CGFloat
    let scrollPull: CGFloat
    let pictureSlot: HeroSlot
    let logoSlot: HeroSlot
    let isRevealed: Bool
    let hidesLogo: Bool
    /// False hides the trailer's panel, the synopsis and the ratings row, leaving the picture, the logo and the controls. The page then
    /// shows its streams under them.
    let showsDetails: Bool
    /// How far the portrait logo, its fade and everything below them sit below their spotlight placement (see `TitleHero.detailDrop`). The page
    /// passes none while a spotlight page is still arriving, and the full drop after.
    let drop: CGFloat
    @ViewBuilder let controls: Controls
    @ViewBuilder let trailer: TrailerPanel
    @ViewBuilder let synopsis: Synopsis
    @State private var renderedLogoHeight: CGFloat = TitleHero.logoMaxHeight
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape

    /// Three parts in a row, so the trailer's panel is the same view in both orientations: turning the device while its player is full
    /// screen must not rebuild the player. Only the parts above and below it differ between portrait and landscape.
    @ViewBuilder
    var body: some View {
        if isLandscape { landscapeTop } else { portraitTop }
        if showsDetails && model.trailer.showsPanel {
            trailer
                .padding(.horizontal, contentMargin)
                // The same gap as the synopsis keeps from what is above it, in each orientation.
                .padding(.top, isLandscape ? Theme.Spacing.s : metrics.titleRatingsGap)
                .transition(Self.trailerTransition)
        }
        if showsDetails {
            if isLandscape {
                landscapeBottom.transition(.opacity)
            } else {
                portraitBottom.transition(.opacity)
            }
        }
    }

    /// The landscape picture's width, and the width of the column beside it, where the play buttons sit.
    private var landscapeWidths: (artwork: CGFloat, controls: CGFloat) {
        let artwork = max(120, (size.width - contentMargin * 2 - Theme.Spacing.xl) * TitleHero.landscapeArtworkShare)
        return (artwork, max(0, size.width - contentMargin * 2 - Theme.Spacing.xl - artwork))
    }

    /// Landscape: the picture beside the title and its controls.
    private var landscapeTop: some View {
        let artworkWidth = landscapeWidths.artwork
        return HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            HeroPicture(slot: pictureSlot, isRevealed: isRevealed, contentMode: .fit, preview: model.preview)
                .frame(width: artworkWidth, height: artworkWidth / CardAspect.wide.ratio)
                .overlay(alignment: .bottomTrailing) {
                    PosterRatingsOverlay(item: model.preview, isLandscape: true, startsLoading: model.hasSettledHero)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous))
            VStack(alignment: .leading, spacing: TitleHero.logoTextGap) {
                titleArt(alignment: .leading)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, contentMargin)
        .padding(.vertical, Theme.Spacing.m)
    }

    /// Landscape: the synopsis, then the ratings row, which is never wider than the column the play buttons sit in.
    @ViewBuilder
    private var landscapeBottom: some View {
        synopsis
            .padding(.horizontal, contentMargin)
            .padding(.top, Theme.Spacing.s)
        RatingButtonsRow(item: model.detail.preview, startsLoading: model.hasSettledHero)
            .frame(maxWidth: landscapeWidths.controls, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentMargin)
            .padding(.top, Theme.Spacing.m)
    }

    /// Portrait: the picture under the bar, with the logo low on it and the controls beneath.
    private var portraitTop: some View {
        let height = TitleHero.height(width: size.width, metrics: metrics)
        let visible = TitleHero.visibleHeight(height, logoHeight: TitleHero.logoHeight(logoSlot, hidden: hidesLogo, width: size.width - contentMargin * 2),
                                              drop: drop)
        return VStack(spacing: 0) {
            // Reserve artwork above the measured logo; all text and controls participate in normal vertical layout.
            Color.clear
                // Never less than the top safe area, so a tall logo or title pushes the page down rather than up into the status bar. The drop
                // is added after that floor, so the logo moves by the same amount in every case, and the fade with it.
                .frame(height: max(topInset, height - renderedLogoHeight - TitleHero.logoTextGap) + drop)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                titleArt(alignment: .center)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedLogoHeight = $0 }
                // The block below the logo sits close to it. The stack's own spacing is part of that gap.
                controls
                    .padding(.top, TitleHero.logoTextGap - Theme.Spacing.m)
            }
            .padding(.horizontal, contentMargin)
        }
        .background(alignment: .top) {
            // The fade runs past the picture's bottom edge, so no row of picture pixels shows under its black end.
            HeroPicture(slot: pictureSlot, isRevealed: isRevealed, contentMode: .fill, preview: model.preview)
                .frame(width: size.width, height: TitleHero.pictureHeight(height) + scrollPull)
                .frame(height: visible + scrollPull, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    BottomFade(length: TitleHero.fadeLength(height: height, visible: visible + scrollPull),
                               strength: TitleHero.fadeStrength)
                        .padding(.bottom, -TitleHero.fadeOverscan)
                }
                .offset(y: -scrollPull)
        }
    }

    /// Portrait: the synopsis, then the ratings row. The gaps are the ones these had as rows of one stack with the controls: the stack's
    /// spacing, here the padding above the block, is part of the gap above the synopsis.
    private var portraitBottom: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // The same gap as between the ratings and the line under them.
            synopsis
                .padding(.top, metrics.titleRatingsGap - Theme.Spacing.m)
            RatingButtonsRow(item: model.detail.preview, startsLoading: model.hasSettledHero)
        }
        .padding(.top, Theme.Spacing.m)
        .padding(.horizontal, contentMargin)
    }

    /// The panel fades in and grows from its top edge, so the content below it moves down with it rather than jumping.
    private static var trailerTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }

    private func titleArt(alignment: Alignment) -> some View {
        HeroTitleArt(name: model.detail.name, slot: logoSlot, alignment: alignment, compact: isLandscape, hidden: hidesLogo)
            .frame(maxWidth: .infinity, alignment: alignment)
            // Hidden rather than removed, so the layout does not move when the title appears.
            .opacity(isRevealed ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.detail.name)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail.title")
    }
}
#endif
