import Foundation
import Testing
@testable import Features

/// A swipe over a card plays nothing: the touch that a swipe ends on is not a tap, while the finger is down and for a moment after.
@Suite struct SwipeRecordTests {
    private let t0 = ContinuousClock.now

    @Test func noTouchIsNotASwipe() {
        #expect(!SwipeRecord().isSwipe(at: t0))
    }

    @Test func aTapWithinSlopIsNotASwipe() {
        for distance: CGFloat in [0, SwipeRecord.slop] {
            var record = SwipeRecord()
            record.touchBegan(at: t0)
            record.touchMoved(distance: distance)
            #expect(!record.isSwipe(at: t0.advanced(by: .milliseconds(100))), "down, moved \(distance)")
            record.touchEnded(at: t0.advanced(by: .milliseconds(100)))
            #expect(!record.isSwipe(at: t0.advanced(by: .milliseconds(200))), "lifted, moved \(distance)")
        }
    }

    @Test func aSwipeCountsWhileTheFingerIsDown() {
        var record = SwipeRecord()
        record.touchBegan(at: t0)
        record.touchMoved(distance: 25)
        #expect(record.isSwipe(at: t0.advanced(by: .milliseconds(100))))
    }

    @Test func aSwipeCountsForAMomentAfterTheFingerLifts() {
        var record = SwipeRecord()
        record.touchBegan(at: t0)
        record.touchMoved(distance: 25)
        record.touchEnded(at: t0.advanced(by: .milliseconds(100)))
        #expect(record.isSwipe(at: t0.advanced(by: .milliseconds(400))), "lifted 300 ms ago")
        #expect(!record.isSwipe(at: t0.advanced(by: .milliseconds(500))), "lifted 400 ms ago")
    }

    @Test func aSwipeStillUnderTheFingerLosesItsEndAfterTheLongestHold() {
        var record = SwipeRecord()
        record.touchBegan(at: t0)
        record.touchMoved(distance: 25)
        #expect(record.isSwipe(at: t0.advanced(by: .milliseconds(4900))))
        #expect(!record.isSwipe(at: t0.advanced(by: .seconds(5))))
    }

    @Test func aNewTouchClearsTheSwipeBeforeIt() {
        var record = SwipeRecord()
        record.touchBegan(at: t0)
        record.touchMoved(distance: 25)
        record.touchEnded(at: t0.advanced(by: .milliseconds(100)))
        let tap = t0.advanced(by: .milliseconds(150))
        record.touchBegan(at: tap)
        #expect(!record.isSwipe(at: tap), "a tap right after a swipe")
        #expect(!record.isSwipe(at: tap.advanced(by: .milliseconds(50))))
    }

    @Test func aStationaryTouchAfterALongAgoSwipeIsNotASwipe() {
        var record = SwipeRecord()
        record.touchBegan(at: t0)
        record.touchMoved(distance: 25)
        record.touchEnded(at: t0.advanced(by: .milliseconds(100)))
        let later = t0.advanced(by: .seconds(2))
        record.touchBegan(at: later)
        #expect(!record.isSwipe(at: later.advanced(by: .milliseconds(100))), "down, without moving")
        record.touchEnded(at: later.advanced(by: .milliseconds(100)))
        #expect(!record.isSwipe(at: later.advanced(by: .milliseconds(200))), "lifted, without moving")
    }
}
