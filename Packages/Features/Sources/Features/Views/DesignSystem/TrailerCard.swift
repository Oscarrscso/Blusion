#if canImport(UIKit)
import SwiftUI
import StremioKit

/// A trailer on a shelf or in the trailer list: a Continue Watching card with the trailer's frame, and under it the play mark, the title and
/// the duration when it is known. A YouTube trailer shows its YouTube thumbnail. A direct file has none, so it shows `fallbackArtwork`, the
/// title's own backdrop. The caller presents the trailer when the card is tapped.
struct TrailerCard: View {
    let trailer: Trailer
    let width: CGFloat?
    let fallbackArtwork: URL?
    @State private var artwork: URL?
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.displayScale) private var displayScale

    init(trailer: Trailer, width: CGFloat? = nil, fallbackArtwork: URL? = nil) {
        self.trailer = trailer
        self.width = width
        self.fallbackArtwork = fallbackArtwork
        let hasThumbnails = !trailer.thumbnailCandidates.isEmpty
        _artwork = State(initialValue: hasThumbnails ? ResolvedThumbnails.urls[trailer.id] : fallbackArtwork)
    }

    var body: some View {
        let fixed = width ?? metrics.continueCardWidth
        let maxPixelSize = LandscapeArtwork.maxPixelSize(width: fixed, scale: displayScale)
        LandscapeCard(title: "", artwork: artwork, width: width) {
            CardCaption(width: fixed) { caption }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        // Cancelled when the card leaves the shelf, so only the cards on screen download a thumbnail.
        .task(id: "\(trailer.id)|\(fallbackArtwork?.absoluteString ?? "")") {
            if trailer.thumbnailCandidates.isEmpty {
                artwork = fallbackArtwork
                return
            }
            let resolved = await Self.resolveThumbnail(for: trailer, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            artwork = resolved
            if let resolved { ResolvedThumbnails.urls[trailer.id] = resolved }
        }
    }

    private var caption: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(trailer.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let duration {
                Text(PlayerTime.format(duration))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    /// The length from the trailer or, when neither TMDb nor the addon gave one, the length learned from its last play.
    private var duration: TimeInterval? { trailer.duration ?? TrailerDurations.shared.seconds[trailer.id] }

    private var accessibilityLabel: String {
        [trailer.title, trailer.kind == .teaser ? "Teaser" : "Trailer", duration.map(PlayerTime.format)]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// The first thumbnail candidate that loads at this size. A missing `maxresdefault` fails and the next, `hq720` then `mqdefault`, is
    /// tried. The loaded picture stays in the pipeline's cache, so the card's own picture shows it at once.
    private static func resolveThumbnail(for trailer: Trailer, maxPixelSize: CGFloat) async -> URL? {
        for candidate in trailer.thumbnailCandidates {
            if (try? await ImagePipeline.shared.image(for: candidate, maxPixelSize: maxPixelSize)) != nil { return candidate }
            guard !Task.isCancelled else { return nil }
        }
        return nil
    }
}

/// The thumbnail each trailer resolved to this session. A card that scrolls back into view starts with it, so it does not wait for the
/// lookup again.
@MainActor
private enum ResolvedThumbnails {
    static var urls: [String: URL] = [:]
}
#endif
