#if canImport(UIKit)
import SwiftUI

/// Design tokens. Screens take their spacing, radii and colours from here so every screen lines up on the same grid.
/// Sizes that differ between a phone and a Mac window (page margin, poster width, shelf spacing) live in `LayoutMetrics`.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        /// Small containers: episode stills, progress tracks.
        static let small: CGFloat = 10
        /// Poster artwork.
        static let poster: CGFloat = 10
        /// Wide artwork: Up Next cards, landscape cards, category tiles.
        static let card: CGFloat = 12
        /// Grouped surfaces and panels (the system's inset-grouped corner).
        static let surface: CGFloat = 20
    }

    /// Horizontal inset of screen content on a phone. Adaptive screens read `LayoutMetrics.pageMargin` instead.
    static let screenPadding: CGFloat = 20
    /// Vertical gap between rows on a phone browse screen. Adaptive screens read `LayoutMetrics.shelfSpacing`.
    static let rowSpacing: CGFloat = 28
    /// Gap between cards in a row or a grid on a phone. Adaptive screens read `LayoutMetrics.cardSpacing`.
    static let cardSpacing: CGFloat = 12

    /// The TV app's page: pure black, edge to edge.
    static let background = Color.black
    /// A raised surface on the black page (grouped panels, placeholders): the system's dark secondary grouped grey.
    static let surface = Color.white.opacity(0.11)
    static let surfaceStrong = Color.white.opacity(0.18)
    static let separator = Color.white.opacity(0.12)
    static let artworkBorder = Color.white.opacity(0.22)
    /// Flat grey shown where artwork is still loading. Opaque, so a card never shows what is behind it.
    static let placeholder = Color(white: 0.11)
    static let brandStart = Color(red: 0.12, green: 0.30, blue: 0.86)
    static let brandEnd = Color(red: 0.48, green: 0.17, blue: 1.0)
    static let brandGradient = LinearGradient(colors: [brandStart, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The TV app's type styles. System text styles, so Dynamic Type works; weights are the app's.
    enum Typography {
        /// A shelf header: "Continue Watching", "Season 2".
        static let shelfTitle = Font.title2.bold()
        /// The title under a card, and a row title: bold footnote.
        static let cardTitle = Font.footnote.weight(.semibold)
        /// The grey line under a card title: "S2, E5 · 21 min left".
        static let cardSubtitle = Font.caption
        /// The small grey caps above an episode title: "EPISODE 5". Apply `.textCase(.uppercase)` too.
        static let eyebrow = Font.caption2.weight(.semibold)
        /// A screen's large title ("Search", "Library") when it draws its own.
        static let largeTitle = Font.largeTitle.bold()
        /// The name of a title on its own page when there is no logo artwork.
        static let heroTitle = Font.system(.largeTitle, design: .default, weight: .bold)
        /// The single grey line under a title's name: "Drama · 2008 · 2 hr 32 min".
        static let metaLine = Font.footnote
        /// Body copy such as a synopsis.
        static let body = Font.subheadline
        /// A label inside a button.
        static let button = Font.headline
    }
}

extension View {
    /// The app's screen background: pure black edge to edge, like the TV app. Artwork is the only colour on screen.
    func screenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }

    /// A subtle translucent rounded surface for grouped content. Deliberately not glass: glass is for controls over media.
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.surface) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Glass for a card of content (a stream, a panel) with its translucent hairline. Cards share `Theme.Radius.card`.
    func glassCardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return glassEffect(.regular, in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.7) }
    }

    /// The same inset, one-pixel hairline for posters, cards and tiles. Full-screen hero artwork does not use it.
    func mediaArtwork(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(MediaArtworkModifier(cornerRadius: cornerRadius))
    }
}

private struct MediaArtworkModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.pixelLength) private var pixelLength

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Theme.artworkBorder, lineWidth: pixelLength)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

private struct ScreenBackgroundModifier: ViewModifier {
    @Environment(\.isLandscape) private var isLandscape

    func body(content: Content) -> some View {
        content.background { Theme.background.ignoresSafeArea() }
            .scrollEdgeEffectHidden(isLandscape, for: .top)
            .toolbarBackgroundVisibility(isLandscape ? .hidden : .automatic, for: .navigationBar)
    }
}

/// A fade from clear to black, eased so there is no visible edge where it starts. Hero artwork and the backdrops of title pages
/// end in one. `length` is the share of the height the fade covers, measured from the bottom.
struct BottomFade: View {
    var length: Double = 0.55
    var strength: Double = 1

    var body: some View {
        let start = max(0, 1 - length)
        LinearGradient(stops: [
            .init(color: .black.opacity(0), location: start),
            .init(color: .black.opacity(0.10 * strength), location: start + (1 - start) * 0.18),
            .init(color: .black.opacity(0.32 * strength), location: start + (1 - start) * 0.40),
            .init(color: .black.opacity(0.62 * strength), location: start + (1 - start) * 0.65),
            .init(color: .black.opacity(0.88 * strength), location: start + (1 - start) * 0.85),
            .init(color: .black.opacity(strength), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
