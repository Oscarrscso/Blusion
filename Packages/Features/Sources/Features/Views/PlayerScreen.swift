#if canImport(SwiftUI)
import PlayerKit
import StremioKit
import SwiftUI

/// Full-screen player. Moving on to the next episode swaps the plan, which rebuilds the content with fresh state.
struct PlayerScreen: View {
    let services: AppServices
    @State private var plan: PlaybackPlan

    init(plan: PlaybackPlan, services: AppServices) {
        self.services = services
        _plan = State(initialValue: plan)
    }

    var body: some View {
        PlayerContent(plan: plan, services: services) { plan = $0 }
            .id(plan.id)
    }
}

struct PlayerContent: View {
    @State private var model: PlayerViewModel
    @State private var isPreparingNext = false
    #if canImport(UIKit) && canImport(AVKit)
    @State private var pip = PiPProxy()
    #endif
    @Environment(\.dismiss) private var dismiss
    let services: AppServices
    let onNextPlan: (PlaybackPlan) -> Void

    init(plan: PlaybackPlan, services: AppServices, onNextPlan: @escaping (PlaybackPlan) -> Void) {
        self.services = services
        self.onNextPlan = onNextPlan
        _model = State(initialValue: PlayerViewModel(plan: plan, services: services))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            surface
            SubtitleOverlay(text: model.cueText, controlsVisible: model.controlsVisible)
            if model.isBuffering && model.failureMessage == nil {
                ProgressView().tint(.white).scaleEffect(1.5).accessibilityIdentifier("player.buffering")
            }
            gestureLayer
            if model.controlsVisible && model.failureMessage == nil {
                PlayerControls(model: model, onClose: close, onNextEpisode: playNextEpisode, pipToggle: pipToggle, pipAvailable: pipAvailable)
                    .transition(.opacity)
            }
            if let notice = model.notice, model.failureMessage == nil, !model.isPlaying || model.coordinator?.failedAttempts.isEmpty == false {
                VStack {
                    Spacer()
                    Text(notice).font(.footnote).padding(10).background(.black.opacity(0.7), in: Capsule()).foregroundStyle(.white).padding(.bottom, 120)
                }
                .accessibilityIdentifier("player.notice")
            }
            if let message = model.failureMessage {
                FailureOverlay(message: message, onClose: close)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
        .task { await model.start() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                model.hideControlsIfIdle()
            }
        }
        .onChange(of: model.hasFinished) { _, finished in
            if finished { Task { await handleEnd() } }
        }
        .onDisappear { Task { await model.close() } }
        .modifier(PlayerChrome(model: model))
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .accessibilityIdentifier("player.screen")
    }

    @ViewBuilder
    private var surface: some View {
        #if canImport(UIKit) && canImport(AVKit)
        PlayerSurface(engine: model.coordinator?.engine, pip: pip).ignoresSafeArea()
        #else
        Color.black
        #endif
    }

    private var pipAvailable: Bool {
        #if canImport(UIKit) && canImport(AVKit)
        return model.canPictureInPicture && pip.isPossible
        #else
        return false
        #endif
    }

    private func pipToggle() {
        #if canImport(UIKit) && canImport(AVKit)
        pip.toggle()
        #endif
    }

    /// Tap toggles the controls; double-tap on the left or right third skips back or forward 10 s.
    private var gestureLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    let third = proxy.size.width / 3
                    if location.x < third { Task { await model.skip(by: -10) } } else if location.x > 2 * third { Task { await model.skip(by: 10) } } else { model.togglePlayPause() }
                }
                .onTapGesture { model.toggleControls() }
                .gesture(DragGesture(minimumDistance: 40).onEnded { if $0.translation.height > 140 { close() } })
        }
        .accessibilityHidden(true)
    }

    private func close() {
        Task {
            await model.close()
            dismiss()
        }
    }

    private func playNextEpisode() {
        guard !isPreparingNext else { return }
        isPreparingNext = true
        Task {
            await model.close()
            if let next = await model.prepareNextEpisode() {
                onNextPlan(next)
            } else {
                dismiss()   // no auto-selectable stream: back to the picker
            }
            isPreparingNext = false
        }
    }

    private func handleEnd() async {
        if model.hasNextEpisode { playNextEpisode() } else { model.showControls() }
    }
}

/// Lock-screen / Control Center integration and state mirroring.
private struct PlayerChrome: ViewModifier {
    let model: PlayerViewModel
    #if os(iOS)
    @State private var nowPlaying: NowPlayingController?
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onAppear {
                nowPlaying = NowPlayingController(title: model.plan.request.title, actions: .init(
                    play: { model.coordinator?.play() },
                    pause: { model.coordinator?.pause() },
                    toggle: { model.togglePlayPause() },
                    skip: { seconds in Task { await model.skip(by: seconds) } },
                    seek: { position in Task { await model.coordinator?.seek(to: position) } }))
            }
            .onChange(of: model.state) { _, state in nowPlaying?.update(state) }
            .onDisappear {
                nowPlaying?.tearDown()
                nowPlaying = nil
            }
        #else
        content
        #endif
    }
}

struct SubtitleOverlay: View {
    let text: String?
    let controlsVisible: Bool

    var body: some View {
        VStack {
            Spacer()
            if let text {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 24)
                    .padding(.bottom, controlsVisible ? 140 : 40)
                    .accessibilityIdentifier("player.subtitle")
            }
        }
        .allowsHitTesting(false)
    }
}

struct FailureOverlay: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
            Text("Can't play this").font(.title2.bold())
            Text(message).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Close", action: onClose).buttonStyle(.borderedProminent).accessibilityIdentifier("player.failure.close")
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(24)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.failure")
    }
}
#endif
