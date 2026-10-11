#if canImport(UIKit)
import StremioKit
import SwiftUI

/// The value a "Trailers" header pushes: every trailer of one title, with the title's name and its backdrop, which the cards of direct files show.
struct TrailerListDestination: Hashable {
    let title: String
    let trailers: [Trailer]
    let artwork: URL?
}

/// All of a title's trailers as cards: one full-width column on a phone, two or three across a wide window. A tap plays a direct file in
/// Blusion's player and opens a YouTube trailer in the YouTube app (see `trailerPlayer(item:)`).
struct TrailersView: View {
    let destination: TrailerListDestination
    @State private var playing: Trailer?
    /// The width the list is laid out in, read from the scroll view; zero before the first reading.
    @State private var listWidth: CGFloat = 0
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let layout = Self.columns(forWidth: listWidth, metrics: metrics)
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cardWidth), spacing: metrics.cardSpacing, alignment: .top),
                                     count: layout.count),
                      alignment: .leading, spacing: metrics.cardSpacing) {
                ForEach(destination.trailers) { trailer in
                    Button {
                        Haptics.tap()
                        playing = trailer
                    } label: {
                        TrailerCard(trailer: trailer, width: layout.cardWidth, fallbackArtwork: destination.artwork)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("trailers.\(trailer.id)")
                }
            }
            .padding(.horizontal, metrics.pageMargin)
            .padding(.vertical, Theme.Spacing.l)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        .screenBackground()
        .navigationTitle("Trailers")
        .navigationSubtitle(destination.title)
        .navigationBarTitleDisplayMode(.large)
        .trailerPlayer(item: $playing)
    }

    /// How many cards fit across `width` and how wide each is, between the page margins. A phone has one column across the whole width;
    /// a wide window has as many as fit at the wide card's width, from two to three.
    static func columns(forWidth width: CGFloat, metrics: LayoutMetrics) -> (count: Int, cardWidth: CGFloat) {
        let available = max(0, width - metrics.pageMargin * 2)
        guard metrics.isRegular else { return (1, available) }
        let spacing = metrics.cardSpacing
        let fit = Int((available + spacing) / (metrics.wideCardWidth + spacing))
        let count = min(3, max(2, fit))
        return (count, max(0, (available - spacing * CGFloat(count - 1)) / CGFloat(count)))
    }
}
#endif
