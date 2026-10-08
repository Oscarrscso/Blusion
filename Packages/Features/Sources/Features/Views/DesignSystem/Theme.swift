#if canImport(UIKit)
import SwiftUI

/// Design tokens. Screens take their spacing, radii and colours from here so every screen lines up on the same grid.
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
        /// Small containers: status panels, progress tracks.
        static let small: CGFloat = 10
        /// Poster artwork.
        static let poster: CGFloat = 14
        /// Wide artwork, collection tiles and grouped surfaces.
        static let card: CGFloat = 20
    }

    /// Horizontal inset of screen content. Rows scroll to this edge so the first card lines up with the titles.
    static let screenPadding: CGFloat = 20
    /// Vertical gap between rows on a browse screen.
    static let rowSpacing: CGFloat = 28
    /// Gap between cards in a row or a grid.
    static let cardSpacing: CGFloat = 12

    static let background = Color(red: 0.035, green: 0.035, blue: 0.06)
    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.11)
    static let separator = Color.white.opacity(0.09)
    static let brandStart = Color(red: 0.12, green: 0.30, blue: 0.86)
    static let brandEnd = Color(red: 0.48, green: 0.17, blue: 1.0)
    static let brandGradient = LinearGradient(colors: [brandStart, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension View {
    /// The app's screen background: `Theme.background` edge to edge with a soft brand-coloured glow fading down from the top.
    func screenBackground() -> some View {
        background {
            ZStack {
                Theme.background
                // Several stops with an eased falloff: two stops leave a visible ring where the glow meets the background.
                RadialGradient(stops: [
                    .init(color: Theme.brandEnd.opacity(0.30), location: 0),
                    .init(color: Theme.brandEnd.opacity(0.16), location: 0.22),
                    .init(color: Theme.brandStart.opacity(0.07), location: 0.52),
                    .init(color: Theme.brandStart.opacity(0.02), location: 0.80),
                    .init(color: .clear, location: 1),
                ], center: .top, startRadius: 0, endRadius: 460)
            }
            .ignoresSafeArea()
        }
    }

    /// A subtle translucent rounded surface for grouped content. Deliberately not glass: glass is for controls over media.
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
#endif
