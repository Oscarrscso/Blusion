import Foundation

/// The size of a Parallax card.
///
/// An upright phone keeps a card that is most of the page, so the next one peeks in. An upright iPad keeps the wide-window card.
/// A sideways phone or iPad, and every Mac window, uses a shorter card: the wide formula otherwise grows one nearly as tall as the
/// screen. The height is the card's and, when the card is the shorter one, the shelf's, so the row is exactly as tall as the card.
enum ParallaxCardLayout {
    /// Landscape and Mac base width, before the card-size setting.
    static let compactBase = 360.0
    /// Upright wide-window base width, before the card-size setting.
    static let regularBase = 560.0

    /// The card's width. `compactCards` is landscape and the Mac. Never wider than the page, and scaled by the card-size setting.
    static func cardWidth(containerWidth: Double, pageMargin: Double, cardScale: Double, isRegular: Bool, compactCards: Bool) -> Double {
        let available = containerWidth - pageMargin * 2
        let base = compactCards ? min(compactBase, available * 0.62)
            : (isRegular ? min(regularBase, available * 0.62) : max(200, available - 28))
        return max(1, min(available, (base * cardScale).rounded()))
    }

    /// The card's height: its width over 1.5, in whole points. A shelf pinned to this is exactly as tall as the card.
    static func height(containerWidth: Double, pageMargin: Double, cardScale: Double, isRegular: Bool, compactCards: Bool) -> Double {
        (cardWidth(containerWidth: containerWidth, pageMargin: pageMargin, cardScale: cardScale, isRegular: isRegular,
                   compactCards: compactCards) / 1.5).rounded()
    }
}
