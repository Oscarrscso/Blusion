#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI

#if DEBUG
/// The value comes from the renderer's real layout, with its identity, viewport,
/// clipping rectangle and picture frame. It is exposed only to UI automation.
struct PlayerSurfaceTestAccessibility: ViewModifier {
    let geometry: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.environment["BLUSION_UITEST"] == "1" {
            content.accessibilityElement(children: .ignore)
                .accessibilityLabel("Video surface")
                .accessibilityValue(geometry)
                .accessibilityIdentifier("player.videoSurface")
        } else {
            content
        }
    }
}
#endif

/// Starts fetching the stream a player opens on as soon as the player is made, before its screen appears. SwiftUI makes a view again
/// and again, so each plan starts it once.
@MainActor
enum PlayerPreload {
    private static var begun: Set<UUID> = []

    static func begin(_ plan: PlaybackPlan, services: AppServices) {
        guard !plan.isOffline, let first = plan.candidates.first, begun.insert(plan.id).inserted else { return }
        services.preloadStream(first)
    }
}

/// Lock-screen / Control Center integration and state mirroring.
struct PlayerChrome: ViewModifier {
    let model: PlayerViewModel
    #if os(iOS)
    @State private var nowPlaying: NowPlayingController?
    @Environment(\.scenePhase) var scenePhase
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onAppear {
                // A return from the background finds the last one kept: its lock-screen commands are removed before new ones are added.
                nowPlaying?.tearDown()
                nowPlaying = NowPlayingController(title: model.plan.request.title, actions: .init(
                    play: { model.coordinator?.play() },
                    pause: { model.coordinator?.pause() },
                    toggle: { model.togglePlayPause() },
                    skip: { seconds in Task { await model.skip(by: seconds) } },
                    seek: { position in Task { await model.coordinator?.seek(to: position) } }))
                nowPlaying?.setSkipIntervals(backward: model.skipBackSeconds, forward: model.skipForwardSeconds)
            }
            .onChange(of: model.state) { _, state in nowPlaying?.update(state) }
            // The settings load after the screen appears: the lock screen takes the player's skip amounts when they arrive.
            .onChange(of: model.skipBackSeconds + 1000 * model.skipForwardSeconds) { _, _ in
                nowPlaying?.setSkipIntervals(backward: model.skipBackSeconds, forward: model.skipForwardSeconds)
            }
            .onDisappear {
                // Backgrounding can report the surface as gone without a dismissal: lock-screen controls stay then, as playback does.
                if LivePlaybackSession.closesOnDisappear(scenePhase: scenePhase) {
                    nowPlaying?.tearDown()
                    nowPlaying = nil
                }
            }
        #else
        content
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Mac keyboard shortcuts that work while the controls are hidden. They call the same actions as the buttons in `PlayerControls`,
/// whose own shortcuts are compiled out on Mac so each key has one registration.
struct PlayerKeyboard: View {
    let model: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Button("Close", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
            Button("Play or pause") { model.togglePlayPause() }
                .keyboardShortcut(" ", modifiers: [])
            Button("Back \(Int(model.skipBackSeconds)) seconds") { Task { await model.skipBack() } }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward \(Int(model.skipForwardSeconds)) seconds") { Task { await model.skipForward() } }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Subtitles") { Task { await model.cycleSubtitles() } }
                .keyboardShortcut("c", modifiers: [])
            Button("Volume up") { model.adjustVolume(by: 0.1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Volume down") { model.adjustVolume(by: -0.1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Mute") { model.toggleMute() }
                .keyboardShortcut("m", modifiers: [])
            Button("Previous chapter") { Task { await model.previousChapter() } }
                .keyboardShortcut("[", modifiers: [])
            Button("Next chapter") { Task { await model.nextChapter() } }
                .keyboardShortcut("]", modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

struct FailureOverlay: View {
    @Environment(\.layoutMetrics) var metrics
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
            Text("Can't play this").appFont(style: .title2, weight: .bold, role: .display)
            Text(message).appFont(style: .callout, weight: .regular, role: .reading).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Close", action: onClose).buttonStyle(.primaryActionCompact).accessibilityIdentifier("player.failure.close")
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28 * metrics.cornerScale(for: .playerControls)))
        .padding(24)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.failure")
    }
}
#endif
