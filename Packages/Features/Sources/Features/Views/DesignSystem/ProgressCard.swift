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
    @State private var logoImage: UIImage?

    init(title: String, subtitle: String? = nil, artwork: URL?, logo: URL? = nil, fraction: Double,
         duration: TimeInterval? = nil, width: CGFloat? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.logo = logo
        self.fraction = fraction
        self.duration = duration
        self.width = width
        _logoImage = State(initialValue: logo.flatMap { ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: 400) })
    }

    var body: some View {
        let progress = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let fixed = width ?? (metrics.isRegular ? 180 : 148)
        let overlay = PlaybackProgressOverlay(fraction: progress, duration: duration, episode: subtitle, width: fixed)
        Color.clear
            .frame(width: fixed, height: fixed / CardAspect.wide.ratio)
            .overlay { ArtworkImage(url: artwork, maxPixelSize: min((fixed * displayScale).rounded(.up), 1200)) }
            .overlay { overlay }
            .overlay {
                Group {
                    if let logoImage {
                        Image(uiImage: logoImage).resizable().scaledToFit()
                    } else {
                        Text(title)
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: fixed * 0.65, height: fixed / CardAspect.wide.ratio * 0.32)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .allowsHitTesting(false)
            }
            .mediaArtwork()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, subtitle, overlay.remainingTime, "\(Int((progress * 100).rounded())) percent watched"].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: ", "))
            .task(id: logo) {
                guard let logo else { logoImage = nil; return }
                let image = try? await ImagePipeline.shared.image(for: logo, maxPixelSize: 400)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { logoImage = image }
            }
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
