#if canImport(UIKit)
import SwiftUI

/// Landscape artwork with a centered title logo and a compact playback row inside its bottom fade.
struct ProgressCard: View {
    let title: String
    let subtitle: String?
    let artwork: URL?
    let logo: URL?
    let fraction: Double
    let duration: TimeInterval?
    let width: CGFloat?
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.displayScale) private var displayScale

    init(title: String, subtitle: String? = nil, artwork: URL?, logo: URL? = nil, fraction: Double,
         duration: TimeInterval? = nil, width: CGFloat? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.logo = logo
        self.fraction = fraction
        self.duration = duration
        self.width = width
    }

    var body: some View {
        let progress = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let fixed = width ?? metrics.continueCardWidth
        let overlay = PlaybackProgressOverlay(fraction: progress, duration: duration, episode: subtitle, width: fixed)
        Color.clear
            .frame(width: fixed, height: fixed / CardAspect.wide.ratio)
            .overlay {
                LandscapeArtwork(title: title, artwork: artwork, logo: logo, maxPixelSize: min((fixed * displayScale).rounded(.up), 1200))
            }
            .overlay { overlay }
            .mediaArtwork()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, subtitle, overlay.remainingTime, "\(Int((progress * 100).rounded())) percent watched"].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// Shared playback styling. Unknown runtime leaves the time label out; unwatched and completed artwork has no playback overlay.
struct PlaybackProgressOverlay: View {
    let fraction: Double
    var duration: TimeInterval?
    var episode: String?
    let width: CGFloat

    private var hasProgress: Bool { fraction.isFinite && fraction > 0 && fraction < 1 }

    var remainingTime: String? {
        guard hasProgress, let duration, duration.isFinite, duration > 0 else { return nil }
        let minutes = ((duration * (1 - fraction)).rounded() / 60).rounded(.up)
        return "\(minutes.formatted(.number.precision(.fractionLength(0))))m"
    }

    var body: some View {
        if hasProgress {
            BottomFade(length: 0.40)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Capsule()
                            .fill(.white.opacity(0.32))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white).scaleEffect(x: fraction, y: 1, anchor: .leading)
                            }
                            .frame(width: min(52, width * 0.20), height: 3)
                        if let remainingTime {
                            Text(remainingTime)
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .fixedSize()
                        }
                        if let episode, !episode.isEmpty {
                            Text(episode)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.92), in: Capsule())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.s)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
#endif
