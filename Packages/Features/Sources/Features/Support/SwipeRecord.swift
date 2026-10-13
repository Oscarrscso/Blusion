import Foundation

/// The latest touch on a navigation stack's screens, read by the cards that play a stream. A touch that travels more than `slop` points
/// is a swipe, and a swipe plays nothing: the finger that made it lifts over a card, and the card must not take that touch-up as a tap.
/// A swipe counts while the finger is still down, and for `lingerAfterLift` after it lifts. The UIKit watcher that writes it is in
/// `ZoomTransition.swift`, and it sees every touch, so a swipe is caught even when no back swipe recognized it.
struct SwipeRecord {
    /// How far a touch may travel and still be a tap.
    static let slop: CGFloat = 10
    /// How long after a swipe lifts it still blocks a tap.
    static let lingerAfterLift: Duration = .milliseconds(400)
    /// How long a swipe still under the finger blocks a tap. Past this, the swipe has lost its end and no longer blocks anything.
    static let longestHold: Duration = .seconds(5)

    /// The most recent touch on a navigation stack's screens. Written by the UIKit watcher, read by the stream cards.
    @MainActor static var latest = SwipeRecord()

    private var began: ContinuousClock.Instant?   // set while the latest touch is down
    private var lifted: ContinuousClock.Instant?  // set once it lifts
    private var travelled = false

    mutating func touchBegan(at now: ContinuousClock.Instant) {
        began = now
        lifted = nil
        travelled = false
    }

    mutating func touchMoved(distance: CGFloat) {
        if distance > Self.slop { travelled = true }
    }

    mutating func touchEnded(at now: ContinuousClock.Instant) {
        began = nil
        lifted = now
    }

    /// True when the latest touch travelled past `slop` and is still down (for at most `longestHold`), or lifted less than
    /// `lingerAfterLift` ago.
    func isSwipe(at now: ContinuousClock.Instant) -> Bool {
        guard travelled else { return false }
        if let began { return now - began < Self.longestHold }
        guard let lifted else { return false }
        return now - lifted < Self.lingerAfterLift
    }
}
