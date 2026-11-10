#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

// MARK: - Mosaic

/// `RowLayout.mosaic`: pages of five posters, one twice the size of the others, which sit in a square of four beside it. The large poster
/// changes sides from page to page, so the row reads as a mosaic rather than a grid.
struct MosaicLayout: View {
    let items: [MetaPreview]
    let presentation: WidgetPresentation
    @Environment(\.layoutMetrics) private var metrics

    static func tileWidth(_ metrics: LayoutMetrics) -> CGFloat { (metrics.posterWidth * 0.72).rounded() }
    static func gap(_ metrics: LayoutMetrics) -> CGFloat { max(4, (metrics.cardSpacing * 0.67).rounded()) }
    /// Two small posters and the gap between them, which is also the large poster's height.
    static func height(_ metrics: LayoutMetrics) -> CGFloat { tileWidth(metrics) * 3 + gap(metrics) }

    var body: some View {
        let tile = Self.tileWidth(metrics)
        let gap = Self.gap(metrics)
        let pages = stride(from: 0, to: items.count, by: 5).map { Array(items[$0..<min($0 + 5, items.count)]) }
        ShelfScroll(margin: metrics.pageMargin, spacing: gap) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                MosaicPage(items: page, featureFirst: index.isMultiple(of: 2), tile: tile, feature: Self.height(metrics) / 1.5, gap: gap,
                           presentation: presentation)
                    .reportsShelfEdge(id: index)
            }
        }
        // A phone on its side draws posters as wide cards, which would break the mosaic's squares.
        .environment(\.isLandscape, false)
    }
}

private struct MosaicPage: View {
    let items: [MetaPreview]
    let featureFirst: Bool
    let tile: CGFloat
    let feature: CGFloat
    let gap: CGFloat
    let presentation: WidgetPresentation

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            if featureFirst { card(items[0], width: feature, isFeature: true) }
            if items.count > 1 { quartet }
            if !featureFirst { card(items[0], width: feature, isFeature: true) }
        }
    }

    private var quartet: some View {
        let rest = Array(items.dropFirst())
        return VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: gap) {
                ForEach(rest.prefix(2), id: \.identity) { card($0, width: tile, isFeature: false) }
            }
            if rest.count > 2 {
                HStack(spacing: gap) {
                    ForEach(rest.dropFirst(2), id: \.identity) { card($0, width: tile, isFeature: false) }
                }
            }
        }
    }

    /// Ratings only on the large poster: the small ones are too narrow for the badges.
    private func card(_ item: MetaPreview, width: CGFloat, isFeature: Bool) -> some View {
        MediaCardLink(item: item, aspect: .poster, size: isFeature ? .large : .small, showsTitle: false,
                      showsRating: presentation.showsRatings && isFeature, width: width, usesBetterPosters: presentation.usesBetterPosters)
    }
}
#endif
