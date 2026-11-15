#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI

extension PlayerContent {
    // MARK: Up Next

    /// Called every half second. When the end comes up (`UpNextTiming`) the next episode starts loading off screen; once it is ready,
    /// Next Episode shows and counts down. Seeking back out of the end takes the button away again.
    func updateUpNext() {
        guard model.hasNextEpisode, model.failureMessage == nil, departure == .staying, !channelAdvanceFailed else { return }
        let creditsToEnd = model.activeSkipMarker.map { $0.kind == .credits && model.skipEndsMedia($0) } ?? false
        let nearEnd = UpNextTiming.isNearEnd(position: model.state.position, duration: model.duration, creditsToEnd: creditsToEnd)
        if !nearEnd && !(model.duration.map { $0 > 0 && $0 - model.state.position <= 45 } ?? false), nextPrompt == .creditsChosen {
            nextPrompt = .hidden
        }
        if nearEnd, case .notStarted = nextEpisode { readyNextEpisode() }
        // A channel readies its next programme, but lets the current programme finish instead of cutting its credits short.
        if model.plan.queue != nil { return }
        let inLast45Seconds = model.duration.map { $0.isFinite && $0 > 0 && $0 - model.state.position <= 45 } ?? false
        // Show the action even if preload is slow; keep it up once its countdown starts.
        let isReady = if case .ready = nextEpisode { true } else { false }
        let isCounting = upNextProgress != nil
        let shows = (nearEnd || inLast45Seconds) &&
            (isReady || inLast45Seconds || isCounting) && nextPrompt != .creditsChosen
        if shows && !isCounting {
            startCountdown()
        } else if !shows && isCounting {
            stopCountdown()
        }
    }

    /// The next episode's stream, chosen as the end of an episode chooses it, starts muted and holds on its first frame.
    private func readyNextEpisode() {
        let task = Task {
            guard let plan = await model.prepareNextEpisode(), !Task.isCancelled else {
                if case .readying = nextEpisode { nextEpisode = .unavailable }
                return
            }
            let next = Self.makeModel(plan: plan, services: services)
            PlayerPreload.begin(plan, services: services)
            await next.prepare()
            guard !Task.isCancelled, case .readying = nextEpisode, next.coordinator?.phase == .playing else {
                await next.close()   // nothing to play in it, or this screen has gone
                if case .readying = nextEpisode { nextEpisode = .unavailable }
                return
            }
            nextEpisode = .ready(UpNextEpisode(plan: plan, model: next))
        }
        nextEpisode = .readying(task)
    }

    /// Counts eight seconds of playback (a pause holds the count), then plays the next episode.
    private func startCountdown() {
        nextPrompt = .counting(0)
        upNextCountdown = Task {
            let clock = ContinuousClock()
            var last = clock.now
            var elapsed = Duration.zero
            while elapsed < UpNextTiming.countdown {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                let now = clock.now
                if model.isPlaying { elapsed += now - last }
                last = now
                nextPrompt = .counting(min(1, elapsed / UpNextTiming.countdown))
            }
            playNextEpisode()
        }
    }

    func stopCountdown() {
        upNextCountdown?.cancel()
        upNextCountdown = nil
        if case .counting = nextPrompt { nextPrompt = .hidden }
    }

    /// This screen is going: a readied next episode it did not hand on is closed, so its stream stops.
    func leaveUpNext() {
        stopCountdown()
        switch nextEpisode {
        case .readying(let task):
            task.cancel()
            nextEpisode = .unavailable
        case .ready(let next):
            nextEpisode = .unavailable
            Task { await next.model.close() }
        case .notStarted, .unavailable, .handedOver:
            break
        }
    }

    /// Netflix's choice at the end of an episode, in the player's glass: Watch Credits, and Next Episode filling as its eight seconds run.
    func upNextPrompt(progress: Double) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Spacer()
                Button {
                    Haptics.play(.playerControls)
                    stopCountdown()
                    nextPrompt = .creditsChosen
                } label: {
                    Text("Watch Credits")
                        .appFont(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .buttonSurface(.regular.interactive(), in: ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)))
                        .pointerInteraction(cornerRadius: 22 * metrics.cornerScale(for: .playerControls))
                }
                .buttonStyle(.hoverPlain)
                .accessibilityIdentifier("player.upNext.credits")
                Button {
                    Haptics.play(.playerControls)
                    playNextEpisode()
                } label: {
                    Label("Next Episode", systemImage: "play.fill")
                        .appFont(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(alignment: .leading) {
                            GeometryReader { proxy in
                                Rectangle().fill(.white.opacity(0.3)).frame(width: proxy.size.width * progress)
                            }
                        }
                        .clipShape(ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)))
                        .buttonSurface(.regular.interactive(), in: ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)))
                        .pointerInteraction(cornerRadius: 22 * metrics.cornerScale(for: .playerControls))
                }
                .buttonStyle(.hoverPlain)
                .keyboardShortcut("n", modifiers: [])
                .accessibilityIdentifier("player.upNext.play")
                .accessibilityValue("Plays in \(Int((8 * (1 - progress)).rounded(.up))) seconds")
            }
            .foregroundStyle(.white)
            .padding(.trailing, 24)
            .padding(.bottom, model.controlsVisible ? 190 : 40)
        }
        .transition(.opacity)
    }
}
#endif
