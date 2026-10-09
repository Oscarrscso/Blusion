#if canImport(UIKit)
import SwiftUI

/// A resume card: playback controls over the bottom of the artwork, with the title and episode metadata beneath it.
struct ProgressCard: View {
    let title: String
    let subtitle: String?
    let artwork: URL?
    let fraction: Double
    let duration: TimeInterval?
    let width: CGFloat?
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.displayScale) private var displayScale

    init(title: String, subtitle: String? = nil, artwork: URL?, fraction: Double, duration: TimeInterval? = nil, width: CGFloat? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.fraction = fraction
        self.duration = duration
        self.width = width
    }

    var body: some View {
        let progress = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let fixed = width ?? (metrics.isRegular ? 180 : 148)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Color.clear
                .frame(width: fixed, height: fixed / CardAspect.wide.ratio)
                .overlay { ArtworkImage(url: artwork, title: title, maxPixelSize: min((fixed * displayScale).rounded(.up), 1200)) }
                .overlay { PlaybackProgressOverlay(fraction: progress, duration: duration, width: fixed) }
                .mediaArtwork()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .lineLimit(1)
                Text(subtitleLine)
                    .font(Theme.Typography.cardSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: fixed, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle, "\(Int((progress * 100).rounded())) percent watched"].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private var subtitleLine: String {
        guard let subtitle, !subtitle.isEmpty else { return " " }
        return subtitle
    }
}

/// Shared by resume cards and episode stills. A real percentage is enough for the bar; runtime is shown only when known.
struct PlaybackProgressOverlay: View {
    let fraction: Double
    var duration: TimeInterval?
    let width: CGFloat

    var body: some View {
        if fraction.isFinite, fraction > 0, fraction < 1 {
            BottomFade(length: 0.38, strength: 0.9)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Capsule()
                            .fill(.white.opacity(0.32))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white).scaleEffect(x: fraction, y: 1, anchor: .leading)
                            }
                            .frame(width: min(96, width * 0.42), height: 3)
                        if let duration, duration.isFinite, duration > 0 {
                            let minutes = ((duration * (1 - fraction)).rounded() / 60).rounded(.up)
                            Text("\(minutes.formatted(.number.precision(.fractionLength(0))))m")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .lineLimit(1)
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
