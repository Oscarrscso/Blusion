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

    /// Most of a phone's width, so the next card peeks in; a fixed width in a wider window. Both scale with the card size, never wider
    /// than the page.
    static func cardWidth(_ metrics: LayoutMetrics, containerWidth: CGFloat) -> CGFloat {
        let available = containerWidth - metrics.pageMargin * 2
        let base = metrics.isRegular ? min(560, available * 0.62) : max(200, available - 28)
        return max(1, min(available, (base * metrics.cardScale).rounded()))
    }

    static func height(_ metrics: LayoutMetrics, containerWidth: CGFloat) -> CGFloat {
        (cardWidth(metrics, containerWidth: containerWidth) / 1.5).rounded()
    }

    var body: some View {
        let width = Self.cardWidth(metrics, containerWidth: containerWidth)
        let height = Self.height(metrics, containerWidth: containerWidth)
        // The cards' height follows the window's width, so the shelf measures again when it changes instead of keeping the tallest it
        // has seen, which left a narrowed window's cards in a row too tall for them.
        ShelfScroll(margin: metrics.pageMargin, spacing: metrics.cardSpacing, resetKey: "\(width)x\(height)") {
            ForEach(items, id: \.identity) { item in
                ParallaxCard(item: item, width: width, height: height, showsRating: showsRating)
                    .reportsShelfEdge(id: item.identity)
            }
        }
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
                    .font(Theme.Typography.metaLine.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            if let synopsis {
                Text(synopsis)
                    .font(Theme.Typography.metaLine)
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
