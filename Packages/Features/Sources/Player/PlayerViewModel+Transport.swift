import Foundation
import Observation
import Persistence
import PlayerKit
import StremioKit

extension PlayerViewModel {
    // MARK: Transport

    func togglePlayPause() {
        endHeldSpeed()
        // The button's glyph decides: during a stall it shows Pause, so a tap pauses.
        if wantsPlayback { coordinator?.pause() } else { coordinator?.play() }
        showControls()
        Task { await recordSessionSnapshot(force: true) }
    }

    func skip(by seconds: TimeInterval) async {
        showControls()
        await coordinator?.skip(by: seconds)
        await recordSessionSnapshot(force: true)
    }

    func seek(to position: TimeInterval) async {
        showControls()
        await coordinator?.seek(to: position)
        await recordSessionSnapshot(force: true)
    }

    func nextStream() async {
        endHeldSpeed()
        showControls()
        await coordinator?.advance()
    }

    /// Selection is explicit: opening the stream menu itself never switches or plays media.
    func selectStream(at index: Int) async {
        endHeldSpeed()
        showControls()
        await coordinator?.selectCandidate(at: index)
    }

    func setRate(_ rate: Float) {
        if let held = heldSpeed {
            // A speed chosen during a hold is the one the hold returns to; the speed held now stays as it is.
            heldSpeed = HeldSpeed(restoreRate: rate, rate: held.rate, isLocked: held.isLocked)
        } else {
            coordinator?.setRate(rate)
        }
        showControls()
    }

    /// The press-and-hold speed-up while a finger holds the picture: the speed it plays at now, and the speed the film was at before,
    /// which comes back exactly on release.
    struct HeldSpeed: Equatable, Sendable {
        let restoreRate: Float
        /// Never above `heldSpeedMaximum`: the speed the engine is asked for, which is also what the badge shows.
        let rate: Float
        /// Set by a drag down: the speed stays after the finger lifts, until `endHeldSpeed` returns the film to `restoreRate`.
        var isLocked = false
    }

    /// The fastest a hold goes on the engine playing: `SpeedHoldRules.ceilingRate`, or lower where that engine cannot play faster.
    var heldSpeedMaximum: Float { min(SpeedHoldRules.ceilingRate, coordinator?.maximumRate ?? 1) }

    /// Starts a hold at `SpeedHoldRules.startRate`, keeping the speed the film was at for release. A paused film, or one not yet
    /// playing, takes no hold (returns false), so the press keeps its ordinary handling. The controls stay as they are.
    @discardableResult
    func beginHeldSpeed() -> Bool {
        guard heldSpeed == nil, isPlaying, let coordinator else { return false }
        let rate = min(SpeedHoldRules.startRate, heldSpeedMaximum)
        heldSpeed = HeldSpeed(restoreRate: coordinator.rate, rate: rate)
        coordinator.setRate(rate)
        return true
    }

    /// Moves the held speed to a step. Only a change of step reaches the engine: a finger moving within one step makes no call.
    /// A locked hold keeps its speed.
    func setHeldSpeed(_ rate: Float) {
        guard let held = heldSpeed, !held.isLocked, let coordinator else { return }
        guard rate.isFinite else { return }
        let target = min(max(SpeedHoldRules.startRate, rate), heldSpeedMaximum)
        guard target != held.rate else { return }
        heldSpeed = HeldSpeed(restoreRate: held.restoreRate, rate: target)
        coordinator.setRate(target)
    }

    /// A drag down locks the hold at the speed it has: the film keeps that speed after the finger lifts, until `endHeldSpeed`.
    func lockHeldSpeed() {
        guard let held = heldSpeed, !held.isLocked else { return }
        heldSpeed = HeldSpeed(restoreRate: held.restoreRate, rate: held.rate, isLocked: true)
    }

    /// Ends the hold and returns to the speed it began at. Idempotent: a lift, a cancelled touch, leaving the app, the end of the film
    /// and closing the player may all call it, and only the first has anything to undo.
    func endHeldSpeed() {
        guard let held = heldSpeed else { return }
        heldSpeed = nil
        coordinator?.setRate(held.restoreRate)
    }

    /// The Mac's ↑ and ↓ keys, in tenths of the full level.
    func adjustVolume(by delta: Float) {
        coordinator?.setVolume(((volume + delta) * 10).rounded() / 10)
        showControls()
    }

    /// The swipe on the right of the picture.
    func setVolume(_ level: Float) {
        coordinator?.setVolume(level)
        if isMuted, level > 0 { coordinator?.setMuted(false) }
    }

    func toggleMute() {
        coordinator?.setMuted(!isMuted)
        showControls()
    }

    func beginScrub() {
        // Capture the live position before fraction starts reading scrubFraction.
        // Otherwise touching the timeline jumps its thumb to the previous drag.
        // Picture swipes use this too: refresh the idle delay without revealing hidden controls.
        let currentFraction = fraction
        scrubFraction = currentFraction
        isScrubbing = true
        lastInteraction = now()
    }

    func updateScrub(fraction: Double, seekImmediately: Bool = false) {
        scrubFraction = min(1, max(0, fraction))
        lastInteraction = now()
        guard seekImmediately, isScrubbing, !isClosed, let duration = state.duration, duration > 0 else { return }
        pendingScrubSeek = scrubFraction * duration
        guard scrubSeekTask == nil else { return }
        scrubSeekTask = Task {
            while let target = pendingScrubSeek {
                pendingScrubSeek = nil
                await coordinator?.seek(to: target)
            }
            scrubSeekTask = nil
        }
    }

    func endScrub() async {
        await scrubSeekTask?.value
        guard isScrubbing else { return }
        // With no length known there is no time to go to: letting go must not send the film back to its start.
        guard let duration = state.duration, duration > 0 else {
            isScrubbing = false
            return
        }
        await coordinator?.seek(to: scrubFraction * duration)
        isScrubbing = false
        await recordSessionSnapshot(force: true)
    }

    /// Stops scrubbing and drops queued seeks. A live seek already sent to the engine keeps its position.
    func cancelScrub() {
        pendingScrubSeek = nil
        isScrubbing = false
    }

    /// Plays this stream in the fallback engine from here, for what only it draws (full ASS styling, picture subtitles).
    func openInAdvancedPlayer() async {
        showControls()
        await coordinator?.reopenInFallbackEngine()
    }

    // MARK: Controls visibility

    func showControls() {
        // The pointer hover calls this on every move, so the observed flag is written only when it changes.
        if !controlsVisible { controlsVisible = true }
        lastInteraction = now()
    }

    func toggleControls() {
        if controlsVisible { controlsVisible = false } else { showControls() }
    }

    /// Call periodically. Hides the controls after a few idle seconds (Settings → Player's Hide controls, three by default, as
    /// `controlsHideDelay`; never when set to zero), but only while playing (or stalled while meant to play, so the picture is clear and the spinner
    /// stands alone) and not scrubbing.
    func hideControlsIfIdle() {
        let seconds = settings.player.controlsHideSeconds
        guard seconds > 0, controlsVisible, wantsPlayback, !isScrubbing,
              now().timeIntervalSince(lastInteraction) >= TimeInterval(seconds) else { return }
        controlsVisible = false
    }

    /// How far Back and Forward jump, in seconds (Settings → Player).
    var skipBackSeconds: TimeInterval { TimeInterval(settings.player.skipBackSeconds) }

    var skipForwardSeconds: TimeInterval { TimeInterval(settings.player.skipForwardSeconds) }

    func skipBack() async { await skip(by: -skipBackSeconds) }

    func skipForward() async { await skip(by: skipForwardSeconds) }

    // MARK: Chapters and skipping

    var chapters: [Chapter] { state.chapters }

    /// The chapter playing now.
    var currentChapter: Chapter? { chapters.last { $0.start <= state.position + 0.5 } }

    func seek(toChapter chapter: Chapter) async {
        await seek(to: chapter.start)
    }

    func previousChapter() async {
        // Within the first seconds of a chapter, back goes to the one before, as on a disc player.
        guard let current = currentChapter, let index = chapters.firstIndex(of: current) else { return }
        let target = state.position - current.start < 3 && index > 0 ? chapters[index - 1] : current
        await seek(toChapter: target)
    }

    func nextChapter() async {
        guard let next = chapters.first(where: { $0.start > state.position + 0.5 }) else { return }
        await seek(toChapter: next)
    }

    var skipMarkers: [SkipMarker] { SkipMarkers.markers(chapters: chapters, duration: duration) }

    /// The marked intro, recap or credits playing now, for the Skip button. Hidden in its last second, where skipping does nothing.
    var activeSkipMarker: SkipMarker? {
        guard settings.player.showsSkipButtons else { return nil }
        let position = state.position
        return skipMarkers.first { $0.contains(position) && $0.end - position > 1 }
    }

    /// True when skipping it ends the media: the caller then moves to the next episode instead.
    func skipEndsMedia(_ marker: SkipMarker) -> Bool {
        guard let duration else { return false }
        return marker.end >= duration - 2
    }

    func skip(_ marker: SkipMarker) async {
        skippedMarkers.insert(marker)
        await seek(to: marker.end)
    }

    /// Call periodically: skips marked intros and recaps once each when Settings asks for it.
    func skipAutomaticallyIfNeeded() async {
        guard settings.player.skipsIntrosAutomatically, isPlaying, let marker = activeSkipMarker,
              marker.kind == .intro || marker.kind == .recap, !skippedMarkers.contains(marker) else { return }
        await skip(marker)
    }
}
