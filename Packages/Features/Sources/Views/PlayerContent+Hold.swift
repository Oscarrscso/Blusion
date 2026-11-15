#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI

extension PlayerContent {
    // MARK: Press and hold

    /// The press rested for `SpeedHoldRules.holdDelay`. It is a hold if the film is playing and no menu is open; otherwise it keeps its
    /// ordinary handling, so a drag from a paused film still seeks. Either way it is no tap when it lifts.
    func pictureHoldBegan(_ point: CGPoint) {
        holdTrack.restedLong = true
        guard panel == nil, !showsEpisodes, !showsStreams, !isDragging, !isPinching else { return }
        let locked = model.heldSpeed?.isLocked == true
        // A press on a locked hold starts no hold of its own: dragged down, it releases the lock (`pictureHoldMoved`).
        guard locked || model.beginHeldSpeed() else { return }
        holdTrack.ownsTouch = true
        holdTrack.hold = (baselineY: point.y, unlocking: locked)
        // Confirms the hold has taken. A hold the film cannot take stays silent.
        if !locked { Haptics.play(.playerControls) }
    }

    /// The held finger moved: its height from where the hold began steps the speed up, and a drag down far enough locks it
    /// (`SpeedHoldRules`). Nothing else reads the movement.
    func pictureHoldMoved(_ point: CGPoint) {
        guard let hold = holdTrack.hold else { return }
        let displacement = Double(point.y - hold.baselineY)
        if hold.unlocking {
            // A drag down from a locked hold's press returns the film to the speed it was at: the lock is released.
            guard SpeedHoldRules.unlocks(displacement: displacement) else {
                holdProgress.update(SpeedHoldRules.unlockProgress(displacement: displacement))
                return
            }
            holdTrack.hold?.unlocking = false
            holdProgress.update(0)
            model.endHeldSpeed()
            Haptics.play(.playerGestures)
            return
        }
        guard let held = model.heldSpeed, !held.isLocked else { return }
        if SpeedHoldRules.locks(displacement: displacement, at: held.rate) {
            holdProgress.update(0)
            model.lockHeldSpeed()
            Haptics.play(.playerControls)
            return
        }
        holdProgress.update(SpeedHoldRules.lockProgress(displacement: displacement, at: held.rate))
        model.setHeldSpeed(SpeedHoldRules.rate(displacement: displacement, maximum: model.heldSpeedMaximum, current: held.rate))
    }

    /// The press ended: it lifted, the system took it, or it moved too far before the hold began. A hold returns the film to the speed it
    /// was at, unless it is locked: a locked hold stays until a hold dragged down, a pause, or the film ending returns it. Idempotent, so
    /// leaving the app, the screen going and the film ending may call it too.
    func endPictureHold() {
        holdProgress.update(0)
        if holdTrack.hold != nil {
            holdTrack.hold = nil
            pictureGestureEndedAt = Date()
            if model.heldSpeed?.isLocked != true { model.endHeldSpeed() }
        }
        if holdTrack.restedLong {
            holdTrack.restedLong = false
            holdEndedAt = Date()
        }
    }

    /// A sideways swipe seeks once the film plays on screen and has a length, with no panel open.
    private var canSwipeSeek: Bool {
        model.hasStartedPlayback && isVideoReady && (model.duration ?? 0) > 0 && model.failureMessage == nil && panel == nil
    }

    func swipeChanged(_ value: DragGesture.Value, in size: CGSize) {
        // An open menu owns its own scrolling.
        guard panel == nil, !showsEpisodes, !showsStreams else { return }
        // A hold owns its finger: a drag that follows it neither seeks nor sets a level.
        guard !holdTrack.ownsTouch else { return }
        if drag == .idle { drag = isPinching ? .pinch : .undecided }
        if drag == .pinch { return }
        if drag == .undecided {
            // Wait for a clear axis instead of permanently classifying a slightly
            // diagonal first movement as vertical. The user's starting point can
            // be anywhere, even over the visible transport controls.
            let dx = abs(value.translation.width)
            let dy = abs(value.translation.height)
            if dx >= 14 && dx > dy * 1.2 {
                drag = canSwipeSeek ? seekSwipe(from: 0) : .horizontal
            } else if dy >= 14 && dy > dx * 1.2 {
                drag = .vertical
            } else {
                return
            }
        }
        // A centre swipe may start upwards, then turn sideways to seek.
        // Side-origin vertical drags remain brightness/volume gestures.
        let third = size.width / 3
        if drag == .vertical,
           value.startLocation.x >= third, value.startLocation.x <= 2 * third,
           value.translation.height < 0, abs(value.translation.width) >= 14, canSwipeSeek {
            drag = seekSwipe(from: value.translation.width)
        }
        if case .seeking(let start, let translation) = drag {
            let fraction = SwipeSeek.fraction(from: start, translation: value.translation.width - translation,
                                              width: size.width, duration: model.duration ?? 0,
                                              heightFraction: value.location.y / max(1, size.height))
            drag = .seeking(fraction: fraction, translation: value.translation.width)
            guard fraction != start else { return }
            model.updateScrub(fraction: fraction, seekImmediately: true)
            return
        }
        guard model.preferences.swipeGestures else { return }
        if drag == .vertical {
            // Up or down on the left: brightness; on the right: device volume.
            guard abs(value.translation.height) > abs(value.translation.width) * 1.5 else { return }
            if value.startLocation.x < third {
                drag = .level(kind: .brightness, start: Double(ScreenBrightness.value))
            } else if value.startLocation.x > 2 * third {
                #if os(iOS) && !targetEnvironment(macCatalyst)
                drag = .level(kind: .volume, start: systemVolume.value)
                #else
                drag = .level(kind: .volume, start: Double(model.volume))
                #endif
            } else {
                return
            }
        }
        guard case .level(let kind, let startValue) = drag else { return }
        let start = (kind: kind, value: startValue)
        let level = min(1, max(0, start.value - value.translation.height / (size.height * 0.7)))
        switch start.kind {
        case .brightness: ScreenBrightness.value = CGFloat(level)
        case .volume:
            #if os(iOS) && !targetEnvironment(macCatalyst)
            systemVolume.value = level
            #else
            model.setVolume(Float(level))
            #endif
        }
        // A step at each 10% boundary, rather than a buzz on every finger movement.
        if Int((swipeLevel?.value ?? start.value) * 10) != Int(level * 10) {
            Haptics.play(.playerGestures)
        }
        swipeLevel = SwipeLevel(kind: start.kind, value: level)
    }

    func swipeEnded(_ value: DragGesture.Value, in size: CGSize) {
        pictureGestureEndedAt = Date()
        guard !holdTrack.ownsTouch else { dragFinished(); return }
        guard panel == nil, !showsEpisodes, !showsStreams else { return }
        // Use the existing seek state to include the final movement before clearing the gesture.
        if seekSwipeFraction != nil { swipeChanged(value, in: size) }
        let ended = drag
        drag = .idle
        // Only a drag that classified as a swipe can dismiss: a release after a hold (which never classified) must not close the player.
        let wasSwiping: Bool
        let wasLevel: Bool
        switch ended {
        case .seeking:
            // Finish at the live drag's final target.
            Task { await model.endScrub() }
            return
        case .pinch:
            return
        case .idle, .undecided:
            wasSwiping = false
            wasLevel = false
        case .horizontal, .vertical:
            wasSwiping = true
            wasLevel = false
        case .level:
            wasSwiping = true
            wasLevel = true
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.4)) { swipeLevel = nil }
        let third = size.width / 3
        let inMiddle = value.startLocation.x >= third && value.startLocation.x <= 2 * third
        if wasSwiping, !wasLevel, value.translation.height > 140, inMiddle || !model.preferences.swipeGestures {
            Haptics.play(.playerControls)
            close()
        }
    }

    /// A pinch takes over a drag: keep the last live position and stop issuing seeks.
    func pinchBegan() {
        switch drag {
        case .idle, .pinch: return
        case .seeking: model.cancelScrub()
        // The level it was setting stays where it is, and its indicator fades.
        case .level: withAnimation(.easeOut(duration: 0.3).delay(0.4)) { swipeLevel = nil }
        case .undecided, .horizontal, .vertical: break
        }
        drag = .pinch
    }

    /// A sideways drag starts seeking from where playback is now.
    private func seekSwipe(from translation: Double) -> PictureDrag {
        let startingFraction = model.fraction
        model.beginScrub()
        return .seeking(fraction: startingFraction, translation: translation)
    }

    /// The drag is over, ended or cancelled (the system can take the touch and skip `onEnded`). After a normal end there is nothing left
    /// to do. Otherwise a seek still open is made where the swipe left the timeline, whichever of the two runs first, and a level indicator
    /// fades, so the next drag starts clean.
    func dragFinished() {
        switch drag {
        case .seeking: Task { await model.endScrub() }
        case .level: withAnimation(.easeOut(duration: 0.3).delay(0.4)) { swipeLevel = nil }
        case .idle, .undecided, .pinch, .horizontal, .vertical: break
        }
        drag = .idle
    }

    func close() {
        advanceTask?.cancel()
        leaveUpNext()
        Task {
            await model.close()
            await model.clearSessionSnapshot()
            livePlayback.forget(model)
            dismiss()
        }
    }

    /// Moves to the next episode: with the player Up Next readied, which then plays at once, or else by finding its stream now.
    func playNextEpisode() {
        guard departure == .staying else { return }
        departure = .movingOn
        stopCountdown()
        advanceTask = Task {
            await model.close()
            livePlayback.forget(model)
            // A readying under way finishes first: it is the quicker start.
            if case .readying(let task) = nextEpisode { await task.value }
            guard !Task.isCancelled else { return }
            if case .ready(let ready) = nextEpisode {
                await model.saveSessionSnapshot(for: ready.plan, candidateIndex: ready.model.currentStreamIndex)
                guard !Task.isCancelled else { await ready.model.close(); return }
                nextEpisode = .handedOver
                departure = .handedOver
                onNextPlan(ready.plan, ready.model)
            } else if let next = await model.prepareNextEpisode() {
                guard !Task.isCancelled else { return }
                await model.saveSessionSnapshot(for: next)
                guard !Task.isCancelled else { return }
                departure = .handedOver
                onNextPlan(next, nil)
            } else {
                guard !Task.isCancelled else { return }
                // No auto-selectable stream: back to the picker, with no session for the episode that just ended.
                if model.plan.queue != nil {
                    departure = .staying
                    channelAdvanceFailed = true
                } else {
                    await model.clearSessionSnapshot()
                    dismiss()
                }
            }
        }
    }

    func handleEnd() async {
        if model.hasNextEpisode {
            playNextEpisode()
        } else {
            // Watched through: there is nothing to walk back into.
            await model.clearSessionSnapshot()
            model.showControls()
        }
    }

    /// Moves to the episode chosen in the picker, whose plan is ready: its panel closes first, then this player gives way to the new one,
    /// so the panel is never left over a player that is being replaced.
    func playChosenEpisode(_ plan: PlaybackPlan) {
        leaveUpNext()
        if showsEpisodes { popOut = .closed }
        departure = .handedOver
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await model.close()
            await model.saveSessionSnapshot(for: plan)
            livePlayback.forget(model)
            onNextPlan(plan, nil)
        }
    }
}
#endif
