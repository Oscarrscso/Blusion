import Foundation

/// The width of a cast and crew card on a title page: four whole cards fit across the page, between its margins and with the gaps between
/// them, so the fifth only peeks in at the edge. Never wider than the shelf's usual card, so a wide window keeps today's size. The cards
/// on the shelf are a little smaller than that. On Mac the Cast and Season controls are half of one of those cards; on iPhone and iPad the
/// Cast control is the card's own width.
enum CastCardLayout {
    /// How many whole cards fit across the page.
    static let cardsAcross = 4
    /// The shelf draws each cast card this much smaller than the four-across width.
    private static let shelfScale = 0.8

    /// The card width for a page `pageWidth` wide with `margin` on each side and `spacing` between cards, at most `maximum`. Whole points,
    /// rounded down, so the fourth card never runs past the margin. Zero when nothing fits.
    static func cardWidth(pageWidth: Double, margin: Double, spacing: Double, maximum: Double) -> Double {
        let across = Double(cardsAcross)
        let fitting = (pageWidth - margin * 2 - spacing * (across - 1)) / across
        guard fitting.isFinite, fitting > 0 else { return 0 }
        return min(maximum, fitting.rounded(.down))
    }

    /// The width of the cast cards actually drawn: the four-across width, a little smaller.
    static func shelfCardWidth(pageWidth: Double, margin: Double, spacing: Double, maximum: Double) -> Double {
        cardWidth(pageWidth: pageWidth, margin: margin, spacing: spacing, maximum: maximum) * shelfScale
    }

    /// The Cast control's width for cards `shelfCardWidth` wide. `halfCard` is the Mac layout, where Cast and Season are half a cast card.
    /// Elsewhere Cast matches the card. Zero when the card has no width.
    static func controlWidth(shelfCardWidth: Double, halfCard: Bool) -> Double {
        guard shelfCardWidth.isFinite, shelfCardWidth > 0 else { return 0 }
        return halfCard ? shelfCardWidth / 2 : shelfCardWidth
    }

    /// Mac draws Cast and Season at half a cast card. iPhone and iPad keep Cast as wide as the card, and Season sizes to its label.
    static var usesHalfCardControl: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
}
