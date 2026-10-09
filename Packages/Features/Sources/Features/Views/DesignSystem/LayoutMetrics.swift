#if canImport(UIKit)
import SwiftUI

/// Every size that differs between a phone and a Mac window, in one place. Screens read these instead of hard-coding numbers, so
/// the same code is right on both:
///
///     @Environment(\.layoutMetrics) private var metrics
///     ... .padding(.horizontal, metrics.pageMargin)
///
/// The compact set is the iPhone layout of the TV app (about 3.2 posters across, 260 pt Up Next cards); the regular set is the
/// Mac window and the iPad (posters about 160 pt, as many across as fit). The environment picks one from the horizontal size
/// class; `.environment(\.layoutMetrics, .regular)` forces a set (the gallery and previews do).
struct LayoutMetrics: Equatable, Sendable {
    /// True for the wide layout (Mac window, iPad): sidebar navigation, left-aligned hero, readable-width text columns.
    var isRegular: Bool
    /// Horizontal inset of page content. Shelves scroll to this edge and the first card lines up with the header.
    var pageMargin: CGFloat
    /// Vertical gap between two shelves (or sections) on a page.
    var shelfSpacing: CGFloat
    /// Gap between a shelf's header and its cards.
    var headerSpacing: CGFloat
    /// Gap between cards in a shelf and between grid cells.
    var cardSpacing: CGFloat
    /// Gap between rows of a grid.
    var gridRowSpacing: CGFloat
    /// Width of a 2:3 poster in a shelf (`CardSize.medium`).
    var posterWidth: CGFloat
    /// Width of a 16:9 card with a caption: Up Next, landscape shelves (`CardSize.medium`).
    var wideCardWidth: CGFloat
    /// Width of a square card in a shelf (`CardSize.medium`).
    var squareWidth: CGFloat
    /// Width of a 16:9 category tile in a shelf.
    var tileWidth: CGFloat
    /// Width of an episode lockup (16:9 still with its texts underneath).
    var episodeWidth: CGFloat
    /// Diameter of a cast and crew avatar.
    var avatarSize: CGFloat
    /// The widest a block of reading text (a synopsis) grows. Wider windows put the information block beside it.
    var readableWidth: CGFloat
    /// The tallest the featured carousel is allowed to be (a tall window should not make it a tower).
    var heroMaxHeight: CGFloat

    static let compact = LayoutMetrics(
        isRegular: false, pageMargin: 20, shelfSpacing: 28, headerSpacing: 10, cardSpacing: 12, gridRowSpacing: 16,
        posterWidth: 112, wideCardWidth: 260, squareWidth: 124, tileWidth: 200, episodeWidth: 250, avatarSize: 72,
        readableWidth: .infinity, heroMaxHeight: 640
    )

    static let regular = LayoutMetrics(
        isRegular: true, pageMargin: 32, shelfSpacing: 36, headerSpacing: 12, cardSpacing: 16, gridRowSpacing: 20,
        posterWidth: 160, wideCardWidth: 300, squareWidth: 176, tileWidth: 260, episodeWidth: 280, avatarSize: 88,
        readableWidth: 640, heroMaxHeight: 620
    )

    /// The featured carousel's height for a screen `width` points wide: a poster's proportions, capped. It follows the width alone,
    /// never the height the scroll view offers, so a navigation bar that changes while scrolling cannot resize the art.
    func heroHeight(forWidth width: CGFloat) -> CGFloat {
        min(width * 1.5, heroMaxHeight)
    }

    /// The columns of a poster grid: three on a phone, as many as fit on a wide screen.
    var posterGridColumns: [GridItem] {
        isRegular
            ? [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: cardSpacing, alignment: .top)]
            : Array(repeating: GridItem(.flexible(), spacing: cardSpacing, alignment: .top), count: 3)
    }

    /// The columns of a grid of 16:9 cards or category tiles: two on a phone, as many as fit on a wide screen.
    var wideGridColumns: [GridItem] {
        isRegular
            ? [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: cardSpacing, alignment: .top)]
            : Array(repeating: GridItem(.flexible(), spacing: cardSpacing, alignment: .top), count: 2)
    }

    /// The columns of a grid of square cards.
    var squareGridColumns: [GridItem] {
        isRegular
            ? [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: cardSpacing, alignment: .top)]
            : Array(repeating: GridItem(.flexible(), spacing: cardSpacing, alignment: .top), count: 3)
    }

    func gridColumns(for aspect: CardAspect) -> [GridItem] {
        switch aspect {
        case .poster: posterGridColumns
        case .wide: wideGridColumns
        case .square: squareGridColumns
        }
    }
}

extension EnvironmentValues {
    @Entry var isLandscape = false
    /// Set only to force a layout; `layoutMetrics` falls back to the one the size class asks for.
    @Entry var layoutMetricsOverride: LayoutMetrics?

    /// The metrics of the current layout: compact in a compact-width window (an iPhone, a narrow split view), regular otherwise
    /// (a Mac window, an iPad). Reading it makes the view depend on the size class, so it follows window resizes.
    var layoutMetrics: LayoutMetrics {
        get { layoutMetricsOverride ?? (horizontalSizeClass == .compact ? .compact : .regular) }
        set { layoutMetricsOverride = newValue }
    }
}
#endif
