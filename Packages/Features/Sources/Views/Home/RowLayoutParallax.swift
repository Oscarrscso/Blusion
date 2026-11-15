#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

// MARK: - Parallax

/// `RowLayout.parallax`: wide cards whose backdrops slide slower than the cards as the row scrolls, each carrying the title's logo (or
/// name), its details and the start of its synopsis over a fade.
struct ParallaxLayout: View {
    let items: [MetaPreview]
    let showsRating: Bool
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.heroContainerWidth) private var containerWidth
    @Environment(\.isPhoneLandscape) private var isLandscape

    /// Most of a phone's width in portrait, so the next card peeks in. Landscape and the Mac use a shorter card (`ParallaxCardLayout`).
    /// Both scale with the card size, never wider than the page.
    static func cardWidth(_ metrics: LayoutMetrics, containerWidth: CGFloat, isLandscape: Bool = false) -> CGFloat {
        layoutWidth(metrics, containerWidth: containerWidth, compactCards: usesCompactCards(isLandscape: isLandscape))
    }

    static func height(_ metrics: LayoutMetrics, containerWidth: CGFloat, isLandscape: Bool = false) -> CGFloat {
        CGFloat(ParallaxCardLayout.height(containerWidth: Double(containerWidth), pageMargin: Double(metrics.pageMargin),
                                          cardScale: Double(metrics.cardScale), isRegular: metrics.isRegular,
                                          compactCards: usesCompactCards(isLandscape: isLandscape)))
    }

    /// The Mac always uses the shorter card. A sideways phone or iPad does too; `isPhoneLandscape` is set for both.
    static func usesCompactCards(isLandscape: Bool) -> Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return isLandscape
        #endif
    }

    var body: some View {
        let compact = Self.usesCompactCards(isLandscape: isLandscape)
        let width = Self.cardWidth(metrics, containerWidth: containerWidth, isLandscape: isLandscape)
        let height = Self.height(metrics, containerWidth: containerWidth, isLandscape: isLandscape)
        // Pin only when the card actually got shorter. A measured shelf only grows, so that shorter card would otherwise sit in the
        // taller row and leave an empty band under it. Portrait, and a window the cap does not change, still measure as before.
        let pinsShelf = compact && width < Self.layoutWidth(metrics, containerWidth: containerWidth, compactCards: false)
        // The cards' height follows the window's width, so a measured shelf starts again when it changes instead of keeping the tallest
        // it has seen, which left a narrowed window's cards in a row too tall for them.
        ShelfScroll(margin: metrics.pageMargin, spacing: metrics.cardSpacing, resetKey: "\(width)x\(height)",
                    pinnedHeight: pinsShelf ? height : nil) {
            ForEach(items, id: \.identity) { item in
                if pinsShelf {
                    ParallaxCard(item: item, width: width, height: height, showsRating: showsRating)
                        .fixedSize(horizontal: false, vertical: true)
                        .reportsShelfEdge(id: item.identity)
                } else {
                    ParallaxCard(item: item, width: width, height: height, showsRating: showsRating)
                        .reportsShelfEdge(id: item.identity)
                }
            }
        }
    }

    private static func layoutWidth(_ metrics: LayoutMetrics, containerWidth: CGFloat, compactCards: Bool) -> CGFloat {
        CGFloat(ParallaxCardLayout.cardWidth(containerWidth: Double(containerWidth), pageMargin: Double(metrics.pageMargin),
                                             cardScale: Double(metrics.cardScale), isRegular: metrics.isRegular,
                                             compactCards: compactCards))
    }
}

private struct ParallaxCard: View {
    let item: MetaPreview
    let width: CGFloat
    let height: CGFloat
    let showsRating: Bool
    @Environment(\.displayScale) private var displayScale

    private var backdrop: URL? {
        PosterQuality.landscape(item.background) ?? MetahubArtwork.background(imdbID: item.id) ?? PosterQuality.poster(for: item)
    }

    private var synopsis: String? {
        let text = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    var body: some View {
        // The picture is wider than the card by `shift` each side, and slides by up to that much against the card's own movement.
        let shift = (width * 0.14).rounded()
        LayoutTitleLink(item: item, cornerRadius: Theme.Radius.surface) {
            Color.clear
                .frame(width: width, height: height)
                .overlay {
                    ArtworkImage(url: backdrop, title: item.name,
                                 maxPixelSize: min(((width + shift * 2) * displayScale).rounded(.up), 2048))
                        .frame(width: width + shift * 2, height: height)
                        .scrollTransition(.interactive.threshold(.centered), axis: .horizontal) { content, phase in
                            content.offset(x: -CGFloat(phase.value) * shift)
                        }
                }
                .clipped()
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.55), location: 0.65),
                                           .init(color: .black.opacity(0.88), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) { caption }
                .contentShape(Rectangle())
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            LayoutLogo(item: item, width: width * 0.5, height: height * 0.24)
            let details = layoutDetailLine(item, showsRating: showsRating)
            if !details.isEmpty {
                Text(details)
                    .appFont(.metaLine, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            if let synopsis {
                Text(synopsis)
                    .appFont(.metaLine, role: .reading)
                    .foregroundStyle(Theme.dimmerText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
