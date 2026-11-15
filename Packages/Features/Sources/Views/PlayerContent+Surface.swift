#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI

extension PlayerContent {
    /// AI upscaling, for the Info menu. Passed as the object, so its status and frame count redraw Info alone.
    var upscalingRenderer: SuperResolutionRenderer? {
        #if canImport(UIKit) && canImport(AVKit)
        superResolution
        #else
        nil
        #endif
    }

    private var hasVideoFrame: Bool {
        guard let engine = model.coordinator?.engine else { return false }
        #if canImport(AVKit)
        if engine is AVEngine { return nativeFrameEngineID == ObjectIdentifier(engine) }
        #endif
        return model.state.hasVideoFrame
    }

    /// The picture is on screen, or the film plays on another screen over AirPlay. Until then the player shows only its spinner and Close:
    /// no poster, no play button, no timeline. A new stream (next episode, another stream) waits for its own first frame the same way.
    var isVideoReady: Bool {
        hasVideoFrame || model.state.isExternalPlaybackActive
    }

    /// A single buffering indication: in the play button when controls are up, otherwise over the video.
    var waitingForPlayback: Bool { model.isStalled || playbackClockStalled }

    var showsStandaloneSpinner: Bool {
        showsStall && waitingForPlayback && isVideoReady &&
            (!controlsAreVisible || panel != nil || showsEpisodes || showsStreams || !model.hasStartedPlayback)
    }

    /// Detect an engine whose status stays at 'playing' even though its clock has stopped.
    /// Reset on pauses, seeks, backgrounding and the end of a title; never mistake those for buffering.
    func refreshPlaybackClock() {
        let state = model.state
        guard model.wantsPlayback, state.isPlaying, isVideoReady, model.failureMessage == nil,
              !model.hasFinished, !model.isScrubbing, seekSwipeFraction == nil, !isPinching,
              scenePhase == .active, state.position.isFinite,
              !(state.duration.map { $0.isFinite && $0 - state.position < 1 } ?? false) else {
            lastPlaybackPosition = nil
            playbackAdvancedAt = nil
            playbackClockStalled = false
            return
        }
        let now = Date()
        if let lastPlaybackPosition, abs(state.position - lastPlaybackPosition) < 0.05 {
            if let playbackAdvancedAt, now.timeIntervalSince(playbackAdvancedAt) >= 1.5 {
                playbackClockStalled = true
            }
        } else {
            playbackAdvancedAt = now
            playbackClockStalled = false
        }
        lastPlaybackPosition = state.position
    }

    /// How long a stall lasts before a spinner shows.
    static let stallSpinnerDelay = Duration.milliseconds(500)

    /// The player's spinner, at start-up and for a stall.
    var spinner: some View {
        Spinner().controlSize(.large)
            .frame(width: 64, height: 64).glassEffect(.regular, in: ScaledCapsule(scale: metrics.circularButtonScale(for: .playerControls)))
    }

    /// Covers the renderer with black until its first frame, with the spinner in the middle.
    var startupSpinner: some View {
        ZStack {
            Color.black
            spinner
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading video")
        .accessibilityIdentifier("player.preparing")
    }

    func skipButton(_ marker: SkipMarker) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    Haptics.play(.playerControls)
                    if model.skipEndsMedia(marker) && model.hasNextEpisode {
                        playNextEpisode()
                    } else {
                        Task { await model.skip(marker) }
                    }
                } label: {
                    Label(marker.kind == .credits && model.hasNextEpisode ? "Next Episode" : marker.kind.buttonTitle,
                          systemImage: "forward.fill")
                        .appFont(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .buttonSurface(.regular.interactive(), in: ScaledCapsule(scale: metrics.cornerScale(for: .playerControls)))
                        .pointerInteraction(cornerRadius: 22 * metrics.cornerScale(for: .playerControls))
                }
                .buttonStyle(.hoverPlain)
                .foregroundStyle(.white)
                .keyboardShortcut("s", modifiers: [])
                .accessibilityIdentifier("player.skipMarker")
            }
            .padding(.trailing, 24)
            .padding(.bottom, model.controlsVisible ? 190 : 40)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    var surface: some View {
        #if canImport(UIKit) && canImport(AVKit)
        configuredSurface
            .equatable()
            #if DEBUG
            .modifier(PlayerSurfaceTestAccessibility(geometry: testVideoGeometry))
            #endif
            // The picture stays put: no animation of the controls or anything else carries over to it.
            .transaction { $0.animation = nil }
            .onDisappear {
                superResolution.tearDown()
                picture.stop()
            }
        #else
        Color.black
        #endif
    }

    private var configuredSurface: PlayerSurface {
        let engine = model.coordinator?.engine
        var picture = PlayerSurface(engine: engine, pip: pip, layout: model.videoLayout, upscaling: model.processing.upscaling,
                      hdrBrightness: model.processing.hdrBrightness,
                      embeddedSubtitlesOn: { if case .embedded = model.subtitleChoice { return true } else { return false } }(),
                      ambientMode: model.preferences.ambientMode, superResolution: superResolution, sampler: picture,
                      pictureReady: isVideoReady, paused: !model.isPlaying,
                      onFirstVideoFrame: {
                          guard let engine, model.coordinator?.engine === engine else { return }
                          (engine as? AVEngine)?.markVideoFrameReady()
                          nativeFrameEngineID = ObjectIdentifier(engine)
                      })
        #if DEBUG
        picture.onTestGeometry = { testVideoGeometry = $0 }
        #endif
        return picture
    }

    var pipAvailable: Bool {
        #if canImport(UIKit) && canImport(AVKit)
        return model.canPictureInPicture && pip.isPossible
        #else
        return false
        #endif
    }

    func pipToggle() {
        #if canImport(UIKit) && canImport(AVKit)
        pip.toggle()
        #endif
    }

    private var acceptsPictureTap: Bool {
        !holdTrack.ownsTouch && !isPinching && !isDragGestureActive && !isDragging
            && (pictureGestureEndedAt.map { Date().timeIntervalSince($0) >= 0.25 } ?? true)
    }

    /// Tap toggles the controls; double-tap on the left or right third skips back or forward 10 s; press and hold plays at double speed
    /// until the finger lifts (the Mac: click and hold). While held, dragging up steps the speed 1× per 40 points, to 4× where the
    /// engine allows it, and dragging down 40 points locks the hold at its speed, which stays after the finger lifts until a hold dragged
    /// down returns the film to the speed before (`SpeedHoldRules`). A hold owns the finger: nothing else acts on its movement until it lifts. On iPhone and iPad a sideways drag anywhere on the picture seeks live,
    /// coarsely at the top and finely at the bottom (`SwipeSeek`); a vertical swipe on the left third sets the brightness
    /// (Settings can turn it off), a swipe down in the middle closes, and a pinch zooms. a vertical swipe on the right third sets system volume.
    /// The layer covers the whole screen, edges included, under the controls: a drag that starts on a control (the timeline, the menu
    /// bar, a button) stays that control's own, so the system slider and segmented control keep their native touch handling.
    var gestureLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(PictureTapGesture { location, tapCount in
                    guard acceptsPictureTap else { return }
                    if tapCount == 1 {
                        // The release that ends a hold (or a press that rested as one) is not a tap. A lock does not swallow taps.
                        if model.heldSpeed?.isLocked == false || holdTrack.restedLong || holdEndedAt.map({ Date().timeIntervalSince($0) < 0.5 }) == true { return }
                        model.toggleControls()
                    } else if tapCount == 2 {
                        Haptics.play(.playerControls)
                        // Settings → Player can turn the skips off: the whole picture then plays and pauses, as its middle does.
                        let third = proxy.size.width / 3
                        if model.preferences.doubleTapSkips && location.x < third {
                            Task { await model.skipBack() }
                        } else if model.preferences.doubleTapSkips && location.x > 2 * third {
                            Task { await model.skipForward() }
                        } else {
                            model.togglePlayPause()
                        }
                    }
                })
                // The UIKit delegate lets both recognizers track the finger. Ownership lasts through the final swipe callback.
                .gesture(PictureHoldGesture(minimumDuration: SpeedHoldRules.holdDelay,
                                                        touchBegan: {
                                                            endPictureHold()
                                                            holdTrack.ownsTouch = false
                                                        },
                                                        began: { pictureHoldBegan($0) },
                                                        moved: { pictureHoldMoved($0) },
                                                        ended: {
                                                            if holdTrack.hold != nil { Haptics.play(.playerGestures) }
                                                            endPictureHold()
                                                        }))
                #if !targetEnvironment(macCatalyst)
                .simultaneousGesture(DragGesture(minimumDistance: 12)
                    .updating($isDragGestureActive) { _, active, _ in active = true }
                    .onChanged { swipeChanged($0, in: proxy.size) }
                    .onEnded { swipeEnded($0, in: proxy.size) })
                #endif
                .simultaneousGesture(MagnifyGesture()
                    .updating($isPinching) { _, pinching, _ in pinching = true }
                    .onEnded { value in
                        pictureGestureEndedAt = Date()
                        // A hold owns the picture while it lasts: a pinch during it changes no zoom.
                        guard !holdTrack.ownsTouch else { return }
                        let previousZoom = model.zoomMode
                        // A shortcut for the saved Zoom Mode: pinch out for Fill, pinch in for Normal.
                        if value.magnification > 1.08 {
                            model.pinchZoom(in: true)
                        } else if value.magnification < 0.92 {
                            model.pinchZoom(in: false)
                        }
                        if model.zoomMode != previousZoom { Haptics.play(.playerOptions) }
                    })
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
#endif
