#if canImport(UIKit)
import SwiftUI
import StremioKit

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

extension View {
    /// Lift a Continue Watching card during the hold, then open its title from that artwork.
    func continueWatchingHold(preview: MetaPreview, request: StreamRequest) -> some View {
        modifier(ContinueWatchingHoldModifier(preview: preview, request: request))
    }
}

private struct ContinueWatchingHoldModifier: ViewModifier {
    let preview: MetaPreview
    let request: StreamRequest
    /// Set when a hold has already opened the title, so the Button's release does not also open the streams.
    @State private var heldOpen = false
    @GestureState private var isHolding = false
    @Environment(AppRouter.self) private var router
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.zoomScope) private var zoomScope
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let sourceID = "continue/\(zoomScope)/\(preview.identity)"
        Button {
            if heldOpen {
                heldOpen = false
                return
            }
            Haptics.tap()
            router.open(.home)
            router.homePath.append(request)
        } label: {
            content
                .scaleEffect(isHolding && !reduceMotion ? 1.08 : 1)
                .brightness(isHolding ? 0.06 : 0)
                .shadow(color: .black.opacity(isHolding ? 0.55 : 0), radius: 12, y: 6)
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.65), value: isHolding)
                .zoomSource(id: sourceID, in: zoomNamespace)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        // A swipe moves past maximumDistance and cancels the hold, so the row's horizontal scroll is never blocked.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5, maximumDistance: 10)
            .updating($isHolding) { pressing, holding, _ in holding = pressing }
            .onEnded { _ in
                heldOpen = true
                Haptics.scrollSnap()
                router.open(.home)
                if zoomNamespace != nil {
                    router.homePath.append(TitleDestination(preview: preview, sourceID: sourceID, usesZoomTransition: true))
                } else {
                    router.homePath.append(preview)
                }
            })
        .onChange(of: isHolding) { _, held in
            // The release can land before or after the Button action, so clear the flag shortly after the hold ends.
            guard !held, heldOpen else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                heldOpen = false
            }
        }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openStreams() }
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
            BottomFade(length: 0.70)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Capsule()
                            .fill(.white.opacity(0.32))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white).scaleEffect(x: fraction, y: 1, anchor: .leading)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 3)
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
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.s)
                    .frame(width: width, alignment: .leading)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
#endif
