#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI

/// Full-screen player. Moving on to the next episode swaps the plan, which rebuilds the content with fresh state.
struct PlayerScreen: View {
    let services: AppServices
    @State var plan: PlaybackPlan
    @Environment(LivePlaybackSession.self) var livePlayback
    /// A player readied before its plan's screen showed (see `PlayerViewModel.prepare`): by the stream picker for the plan this screen
    /// opened on, by Up Next for the next episode. Used only for its own plan.
    @State private var prepared: PlayerViewModel?

    init(plan: PlaybackPlan, services: AppServices, prepared: PlayerViewModel? = nil) {
        self.services = services
        _prepared = State(initialValue: prepared?.plan.id == plan.id ? prepared : nil)
        _plan = State(initialValue: plan)
    }

    var body: some View {
        // A screen starting over for a plan it already plays rejoins the live session for it, keeping the engine, stream, position and
        // tracks the session holds rather than starting a second player.
        let readied = (prepared?.plan.id == plan.id ? prepared : nil) ?? livePlayback.session(for: plan)
        PlayerContent(plan: plan, services: services, prepared: readied) { next, readiedNext in
            prepared = readiedNext
            plan = next
        }
        .id(plan.id)
    }
}

/// The next episode and the player readied for it off screen, muted and paused on its first frame.
struct UpNextEpisode {
    let plan: PlaybackPlan
    let model: PlayerViewModel
}

/// The next episode's player, readied off screen during this one's last minute (`UpNextTiming`).
enum NextEpisodeState {
    case notStarted
    case readying(Task<Void, Never>)
    case ready(UpNextEpisode)
    /// Nothing to ready (no stream started for it), or this screen let it go: it is not tried again.
    case unavailable
    /// The readied player went to the next episode's screen: leaving this one must not close it.
    case handedOver
}

/// Next Episode's button at the end of an episode.
enum UpNextPrompt: Equatable {
    case hidden
    /// Up and counting down: how far its countdown has run, 0...1.
    case counting(Double)
    /// Watch Credits was chosen: the button stays away until the end comes up again. The episode still moves on when it ends.
    case creditsChosen
}

/// Whether this player screen is giving way to another one.
enum Departure {
    case staying
    /// Moving on to the next episode: its stream is being found, or the readied one handed over.
    case movingOn
    /// This screen handed its plan to another player screen (Up Next or a chosen episode): leaving it must not set the new
    /// session aside.
    case handedOver
}

/// The press-and-hold on the picture: whether a hold is under way, the height it began at, and whether the press rested long enough to
/// be no tap when it lifts. A reference type, so following the finger changes nothing the view draws.
@MainActor
final class PictureHoldTrack {
    /// The hold under way, nil while none is: the height it began at, and whether its press is on a locked hold, so dragged down it
    /// releases the lock rather than starting a hold (`SpeedHoldRules.unlocks`).
    var hold: (baselineY: CGFloat, unlocking: Bool)?
    /// Stays latched after release/cancellation until the next touch starts, regardless of callback order.
    var ownsTouch = false
    /// The press rested for the hold delay, so it is not a tap when it lifts, whether or not a hold began.
    var restedLong = false
}

/// The one pop-out over the player: a menu from the controls' bar, the episode picker, or the streams.
enum PlayerPopOut: Equatable {
    case closed
    case menu(PlayerPanelTab)
    case episodes
    case streams
}

/// A drag on the picture, from its first movement to its release.
enum PictureDrag: Equatable {
    case idle
    /// Moving, with no clear axis yet.
    case undecided
    /// Part of a pinch: it neither seeks nor sets a level.
    case pinch
    /// Sideways, seeking: the timeline fraction it has reached, and the drag's width when it got there.
    case seeking(fraction: Double, translation: Double)
    /// Sideways where it cannot seek.
    case horizontal
    /// Up or down, before it has picked brightness or volume, or where it sets neither.
    case vertical
    /// Up or down at a side, setting brightness or volume from the level it started at.
    case level(kind: SwipeLevel.Kind, start: Double)
}

/// How far the held finger has dragged toward the next lock change (`SpeedHoldRules.lockProgress`, `unlockProgress`). Its own observable
/// object, read only by the badge, so following the finger redraws the badge and not the player.
@MainActor
@Observable
final class HoldDragProgress {
    var fraction = 0.0

    func update(_ value: Double) {
        if fraction != value { fraction = value }
    }
}

/// The speed a hold plays at, at the top of the picture. Beside it sits the lock as it stands; while a drag moves toward a lock change, the
/// lock that change would leave, and a bar for how far the drag has got. Its own view, so following the finger redraws only this.
private struct PlayerHoldBadge: View {
    @Environment(\.layoutMetrics) var metrics
    let model: PlayerViewModel
    let progress: HoldDragProgress

    var body: some View {
        let rate = model.state.rate.formatted()
        let locked = model.heldSpeed?.isLocked == true
        let fraction = progress.fraction
        VStack {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: lockSymbol(locked: locked, fraction: fraction))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: locked)
                    Text("\(rate)×")
                }
                if fraction > 0 {
                    ProgressView(value: fraction)
                        .tint(.white)
                        .frame(width: 64)
                        .transition(.opacity)
                }
            }
            .appFont(.mediumStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)))
            .padding(.top, 16)
            .animation(.easeInOut(duration: 0.15), value: fraction > 0)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playing at \(rate) times speed")
        .accessibilityIdentifier("player.doubleSpeed")
    }

    /// The lock as it stands. While a drag moves toward a change, the lock that change would leave: an open lock on a locked hold, a closed
    /// one on an open hold.
    private func lockSymbol(locked: Bool, fraction: Double) -> String {
        if locked {
            return fraction > 0 ? "lock.open.fill" : "lock.fill"
        }
        return fraction > 0 ? "lock.fill" : "forward.fill"
    }
}

struct PlayerContent: View {
    @Environment(\.layoutMetrics) var metrics
    @State var model: PlayerViewModel
    @State private var infoModel: PlayerInfoModel
    @State var departure = Departure.staying
    @Environment(\.windowSafeArea) private var windowSafeArea
    #if canImport(UIKit) && canImport(AVKit)
    @State var pip = PiPProxy()
    @State var superResolution = SuperResolutionRenderer()
    /// Samples the picture for ambient mode's colours.
    @State var picture = PictureSampler()
    #endif
    @State private var importsSubtitle = false
    @State var popOut = PlayerPopOut.closed
    /// The open menu (it sits on the controls' menu bar); nil when none is open. Opening one closes the other pop-outs.
    var panel: PlayerPanelTab? {
        get {
            if case .menu(let tab) = popOut { return tab }
            return nil
        }
        nonmutating set {
            if let newValue { popOut = .menu(newValue) } else if case .menu = popOut { popOut = .closed }
        }
    }
    private var panelBinding: Binding<PlayerPanelTab?> { Binding(get: { panel }, set: { panel = $0 }) }
    @State private var noticeVisible = false
    /// The current chapter marker after its three-second Skip prompt has elapsed.
    @State private var hiddenSkipMarker: SkipMarker?
    @State private var importsAudio = false
    @State private var showsOpenSubtitles = false
    /// The episode picker's panel is open, dropped from the Episodes button.
    var showsEpisodes: Bool { popOut == .episodes }
    var showsStreams: Bool { popOut == .streams }
    /// The level a brightness or volume swipe is setting, for its indicator.
    @State var swipeLevel: SwipeLevel?
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @State var systemVolume = SystemVolume()
    #endif
    @State var drag = PictureDrag.idle
    var isDragging: Bool { drag != .idle }
    /// The accumulated timeline fraction of a sideways drag; nil while no drag seeks.
    var seekSwipeFraction: Double? {
        if case .seeking(let fraction, _) = drag { return fraction }
        return nil
    }
    /// A pinch is under way. A drag that is part of one neither seeks nor sets a level.
    @GestureState var isPinching = false
    /// Resets when the drag ends or when the system takes the touch, which skips the drag's `onEnded`.
    @GestureState var isDragGestureActive = false
    /// Ignore release taps from a pinch or swipe, including when one finger lifts before the other.
    @State var pictureGestureEndedAt: Date?
    /// When the last hold ended: the tap its release makes does not toggle the controls.
    @State var holdEndedAt: Date?
    /// The press-and-hold on the picture (`PictureHoldGesture`). Kept out of state: following the finger must not redraw the player.
    @State var holdTrack = PictureHoldTrack()
    @State var holdProgress = HoldDragProgress()
    @State var nativeFrameEngineID: ObjectIdentifier?
    @State var nextEpisode = NextEpisodeState.notStarted
    @State var channelAdvanceFailed = false
    @State var advanceTask: Task<Void, Never>?
    @State var nextPrompt = UpNextPrompt.hidden
    /// The running countdown of `nextPrompt`, called off with `stopCountdown`.
    @State var upNextCountdown: Task<Void, Never>?
    /// How far Next Episode's countdown has run, 0...1; nil while the button is not up.
    var upNextProgress: Double? {
        if case .counting(let progress) = nextPrompt { return progress }
        return nil
    }
    /// A stall has lasted half a second (`stallSpinnerDelay`): only then does a spinner show, so a momentary wait never flashes one.
    @State var showsStall = false
    /// Some engines still report 'playing' while their clock has stopped: monitor progress as a fallback.
    @State var lastPlaybackPosition: TimeInterval?
    @State var playbackAdvancedAt: Date?
    @State var playbackClockStalled = false
    #if DEBUG
    @State var testVideoGeometry = ""
    #endif
    @Environment(\.dismiss) var dismiss
    @Environment(\.appAppearance) private var appearance
    @Environment(\.scenePhase) var scenePhase
    @Environment(LivePlaybackSession.self) var livePlayback
    let services: AppServices
    /// Moves to the next episode's plan, with the player readied for it when there is one.
    let onNextPlan: (PlaybackPlan, PlayerViewModel?) -> Void

    init(plan: PlaybackPlan, services: AppServices, prepared: PlayerViewModel? = nil,
         onNextPlan: @escaping (PlaybackPlan, PlayerViewModel?) -> Void) {
        self.services = services
        self.onNextPlan = onNextPlan
        _model = State(initialValue: prepared ?? Self.makeModel(plan: plan, services: services))
        _infoModel = State(initialValue: PlayerInfoModel(request: plan.request, services: services))
        PlayerPreload.begin(plan, services: services)
    }

    /// The player's model, made here or by the stream picker that readies a player before opening this screen.
    static func makeModel(plan: PlaybackPlan, services: AppServices) -> PlayerViewModel {
        #if DEBUG
        // Automation round trips can exceed the normal controls idle window.
        // Freeze only its injected interaction clock; playback and gestures stay live.
        let isUITesting = ProcessInfo.processInfo.environment["BLUSION_UITEST"] == "1"
        return PlayerViewModel(plan: plan, services: services, now: { isUITesting ? Date.distantPast : Date() })
        #else
        return PlayerViewModel(plan: plan, services: services)
        #endif
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            #if os(iOS) && !targetEnvironment(macCatalyst)
            SystemVolumeControl(volume: systemVolume)
                .frame(width: 150, height: 32)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            #endif
            #if canImport(UIKit) && canImport(AVKit)
            if model.preferences.ambientMode { AmbientGlow(colours: picture.colours) }
            #endif
            // Keep the video at a fixed full-screen size while controls come and go.
            GeometryReader { viewport in
                surface
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            ZStack {
                if !isVideoReady && model.failureMessage == nil {
                    startupSpinner.transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isVideoReady)
            SubtitleOverlay(cues: model.activeCues, bitmap: model.activeBitmapCue, style: model.subtitleStyle,
                            controlsVisible: model.controlsVisible, layout: model.videoLayout)
                .opacity(isVideoReady ? 1 : 0)
            ZStack {
                if showsStandaloneSpinner {
                    spinner.accessibilityIdentifier("player.buffering").transition(.opacity)
                }
            }
            .animation(Theme.Motion.fade, value: showsStandaloneSpinner)
            .allowsHitTesting(false)
            gestureLayer
            // With a menu or the episodes open, a tap anywhere but them and the controls closes them.
            ZStack {
                if (panel != nil || showsEpisodes || showsStreams) && model.failureMessage == nil {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { closeMenus() }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel != nil || showsEpisodes || showsStreams)
            // Retain the controls (and native scrubber) while hidden. Their local
            // fade cannot change the video viewport or animate the renderer.
            PlayerControls(model: model, infoModel: infoModel, onClose: close, onNextEpisode: playNextEpisode, pipToggle: pipToggle, pipAvailable: pipAvailable,
                           onShowEpisodes: toggleEpisodes, episodesOpen: showsEpisodes,
                           panel: panelBinding, actions: controlActions, upscaling: upscalingRenderer,
                           onShowStreams: { guard !model.plan.isOffline else { return }; closeMenus(); model.showControls(); popOut = .streams },
                           streamsOpen: showsStreams, isVideoReady: isVideoReady, isStalled: showsStall && waitingForPlayback)
                .opacity(controlsAreVisible ? 1 : 0)
                .allowsHitTesting(controlsAreVisible)
                .accessibilityHidden(!controlsAreVisible)
                .disabled(!controlsAreVisible)
                .animation(controlsAreVisible ? nil : .easeInOut(duration: 0.18), value: controlsAreVisible)
            episodePanel
            streamPanel
            ZStack {
                if let progress = upNextProgress, model.failureMessage == nil {
                    upNextPrompt(progress: progress)
                } else if let marker = model.activeSkipMarker,
                          marker != hiddenSkipMarker || model.controlsVisible, model.failureMessage == nil, isVideoReady {
                    skipButton(marker)
                }
            }
            .animation(Theme.Motion.toggle, value: upNextProgress != nil)
            .animation(Theme.Motion.toggle, value: model.controlsVisible)
            if let swipeLevel { SwipeLevelIndicator(level: swipeLevel) }
            ZStack {
                if let fraction = seekSwipeFraction {
                    VStack {
                        Text(PlayerTime.format(fraction * (model.duration ?? 0)))
                            .monospacedDigit()
                            .appFont(.mediumStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .glassEffect(.regular, in: ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)))
                            .padding(.top, 16)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel("Seek position")
                    .accessibilityValue(PlayerTime.format(fraction * (model.duration ?? 0)))
                    .accessibilityIdentifier("player.seekPosition")
                } else if model.heldSpeed != nil { PlayerHoldBadge(model: model, progress: holdProgress).transition(.opacity) }
            }
            .animation(.easeInOut(duration: 0.15), value: model.heldSpeed != nil)
            if let notice = model.notice, noticeVisible, model.failureMessage == nil {
                VStack {
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                        Text(notice.contains("didn't work") ? "Stream unavailable · Trying another…" : notice)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .appFont(.caption, weight: .medium, role: .interface)
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)))
                    .overlay(ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)).strokeBorder(Theme.separator, lineWidth: 0.5))
                    .frame(maxWidth: 320)
                    .padding(.bottom, 150)
                }
                .allowsHitTesting(false)
                .accessibilityIdentifier("player.notice")
            }
            if let message = model.failureMessage {
                FailureOverlay(message: message, onClose: close)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Zoom Mode's Normal keeps the picture inside the safe area beside a notch or Dynamic Island, centred, as Infuse does.
        .onChange(of: max(windowSafeArea.leading, windowSafeArea.trailing), initial: true) { _, inset in
            model.setSafeAreaInset(inset)
        }
        .onChange(of: panel) { old, new in
            if new != .info { infoModel.closeReviews() }
            // A closed menu leaves the controls up, with a fresh idle delay, whichever way it was closed.
            if old != nil && new == nil { model.showControls() }
        }
        #if !targetEnvironment(macCatalyst)
        .onChange(of: isPinching) { _, pinching in
            if pinching { pinchBegan() } else { pictureGestureEndedAt = Date() }
        }
        .onChange(of: isDragGestureActive) { _, active in
            if !active {
                pictureGestureEndedAt = Date()
                Task { dragFinished() }
            }
        }
        #endif
        .onChange(of: model.notice, initial: true) { _, notice in
            withAnimation(Theme.Motion.toggle) { noticeVisible = notice != nil }
        }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.toggle) { noticeVisible = false }
        }
        .task(id: model.activeSkipMarker) {
            guard let marker = model.activeSkipMarker else {
                hiddenSkipMarker = nil
                return
            }
            hiddenSkipMarker = nil
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, model.activeSkipMarker == marker else { return }
            withAnimation(Theme.Motion.toggle) { hiddenSkipMarker = marker }
        }
        .task { await model.start() }
        .alert("Next programme unavailable", isPresented: $channelAdvanceFailed) {
            Button("Retry") {
                nextEpisode = .notStarted
                playNextEpisode()
            }
            Button("Close", role: .cancel) { close() }
        } message: {
            Text("No playable stream was found for the next programme.")
        }
        .task(id: infoModel.ratingsRevision) {
            await infoModel.load()
            guard !Task.isCancelled, infoModel.openedReviews == nil,
                  let item = infoModel.reviewItem, let url = infoModel.imdbReviewsURL else { return }
            ReviewPreloader.shared.preload(site: .imdb, url: url, item: item, background: appearance.pageBackgroundRGB, width: 360)
        }
        .task(id: waitingForPlayback) {
            guard waitingForPlayback else {
                showsStall = false
                return
            }
            try? await Task.sleep(for: Self.stallSpinnerDelay)
            if !Task.isCancelled { showsStall = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                refreshPlaybackClock()
                if panel == nil { model.hideControlsIfIdle() }
                await model.skipAutomaticallyIfNeeded()
                await model.recordSessionSnapshot()
                updateUpNext()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the front keeps the session on the air, but its snapshot should already say where it is if the app is killed.
            if phase != .active { Task { await model.recordSessionSnapshot(force: true) } }
            // A hold, locked or not, must not carry on in the background or through a lock: the speed comes back now.
            if phase != .active {
                endPictureHold()
                model.endHeldSpeed()
            }
        }
        .fileImporter(isPresented: $importsSubtitle, allowedContentTypes: SubtitleFileTypes.subtitles) { result in
            if case .success(let url) = result { Task { await model.loadSubtitleFile(at: url) } }
        }
        .background {
            // A second importer on the same view would replace the first; this one sits on its own view.
            Color.clear.fileImporter(isPresented: $importsAudio, allowedContentTypes: SubtitleFileTypes.audio) { result in
                if case .success(let url) = result { Task { await model.loadAudioFile(at: url) } }
            }
        }
        .sheet(isPresented: $showsOpenSubtitles) { OpenSubtitlesSheet(model: model) }
        .onChange(of: model.hasFinished) { _, finished in
            if finished { Task { await handleEnd() } }
        }
        // Timeline and picture swipes share feedback, including one step per ten seconds crossed.
        .onChange(of: model.isScrubbing) { _, _ in
            Haptics.play(.playerGestures)
        }
        .onChange(of: Int(model.position / 10)) { _, _ in
            if model.isScrubbing { Haptics.play(.playerGestures) }
        }
        .onChange(of: model.heldSpeed) { old, new in
            if let old, let new, old.rate != new.rate { Haptics.play(.playerOptions) }
            if old != nil, new == nil { endPictureHold() }
        }
        .onAppear {
            // The screen is up: its session is the app's live one. A session the screen itself handed over and rebuilt (Up Next) sits
            // in `prepared`, so what presents here is already this plan's player.
            livePlayback.present(model)
        }
        .onDisappear {
            if let url = infoModel.imdbReviewsURL { ReviewPreloader.shared.discard(url: url) }
            endPictureHold()
            leaveUpNext()
            // An actual dismissal releases the session (a closed one forgets itself idempotently). A disappearance that comes with
            // the app leaving the front — backgrounding, a lock — does not: the session stays on the air at the app level, and this
            // screen or a rebuilt one reattaches to it when it comes back.
            if LivePlaybackSession.closesOnDisappear(scenePhase: scenePhase) {
                if departure != .handedOver { advanceTask?.cancel() }
                Task {
                    await model.close()
                    livePlayback.forget(model)
                    // A dismissal sets the session aside; a hand-over has already saved the next one.
                    if departure != .handedOver { await model.clearSessionSnapshot() }
                }
            }
        }
        .modifier(PlayerChrome(model: model))
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.screen")
        #if targetEnvironment(macCatalyst)
        // Moving the pointer over the player shows its controls again, as they hide when idle while playing.
        .onContinuousHover { phase in
            if case .active = phase { model.showControls() }
        }
        .background { PlayerKeyboard(model: model, onClose: escape) }
        #endif
    }

    /// An open menu keeps the controls up: the menu stands on their bar. The episodes' panel hangs from their top bar.
    var controlsAreVisible: Bool {
        (model.controlsVisible || panel != nil || showsEpisodes || showsStreams) && model.failureMessage == nil
    }

    #if targetEnvironment(macCatalyst)
    /// Escape closes the options panel or the episodes first, then the player.
    func escape() {
        if showsStreams {
            closeMenus()
        } else if showsEpisodes {
            closeEpisodes()
        } else if panel != nil {
            panel = nil
            model.showControls()
        } else {
            close()
        }
    }
    #endif

    private var controlActions: PlayerControlActions {
        PlayerControlActions(openSubtitleFile: { importsSubtitle = true }, openAudioFile: { importsAudio = true },
                             searchOpenSubtitles: { if !model.plan.isOffline { showsOpenSubtitles = true } }, toggleAmbient: { model.toggleAmbientMode() })
    }

    #if canImport(UIKit) && canImport(AVKit)
    #endif

    // Picture drag seeking is intentionally touch-only; Mac keeps its timeline and keyboard controls, as requested.
    #if !targetEnvironment(macCatalyst)

    #endif
}
#endif
