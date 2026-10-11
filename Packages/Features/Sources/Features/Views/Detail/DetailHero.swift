#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The title page's hero. In portrait the picture runs under the bar with the logo low on it, and the controls and the synopsis sit beneath
/// it. In landscape the picture is beside the title and its controls, with the synopsis under them. The page supplies the controls and the
/// synopsis, so the state they keep stays on the page and survives a rotation.
struct DetailHero<Controls: View, Synopsis: View>: View {
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
    @ViewBuilder let controls: Controls
    @ViewBuilder let synopsis: Synopsis
    @State private var renderedLogoHeight: CGFloat = TitleHero.logoMaxHeight
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape

    @ViewBuilder
    var body: some View {
        if isLandscape {
            let artworkWidth = max(120, (size.width - contentMargin * 2 - Theme.Spacing.xl) * TitleHero.landscapeArtworkShare)
            // The column beside the artwork, where the play buttons sit. The ratings row is never wider than that.
            let controlsWidth = max(0, size.width - contentMargin * 2 - Theme.Spacing.xl - artworkWidth)
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
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
            synopsis
                .padding(.horizontal, contentMargin)
                .padding(.top, Theme.Spacing.s)
            RatingButtonsRow(item: model.detail.preview, startsLoading: model.hasSettledHero)
                .frame(maxWidth: controlsWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, contentMargin)
                .padding(.top, Theme.Spacing.m)
        } else {
            let height = TitleHero.height(width: size.width, metrics: metrics)
            let visible = TitleHero.visibleHeight(height, logoHeight: TitleHero.logoHeight(logoSlot, hidden: hidesLogo, width: size.width - contentMargin * 2))
            VStack(spacing: 0) {
                // Reserve artwork above the measured logo; all text and controls participate in normal vertical layout.
                Color.clear
                    // Never less than the top safe area, so a tall logo or title pushes the page down rather than up into the status bar.
                    .frame(height: max(topInset, height - renderedLogoHeight - TitleHero.logoTextGap))
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    titleArt(alignment: .center)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedLogoHeight = $0 }
                    // The block below the logo sits close to it. The stack's own spacing is part of that gap.
                    controls
                        .padding(.top, TitleHero.logoTextGap - Theme.Spacing.m)
                    // The same gap as between the ratings and the line under them. The stack's own spacing is part of it.
                    synopsis
                        .padding(.top, metrics.titleRatingsGap - Theme.Spacing.m)
                    RatingButtonsRow(item: model.detail.preview, startsLoading: model.hasSettledHero)
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
