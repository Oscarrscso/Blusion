import CoreGraphics
import Testing
@testable import Features

@Suite struct BackSwipeRuleTests {
    /// An iPhone held upright: a quarter of it is 100.5 points.
    private let width: CGFloat = 402

    @Test func aNudgeOnThePageKeepsIt() {
        #expect(BackSwipeRule.mayBegin(forward: 12, vertical: 2, fromEdge: false), "a sideways start may track")
        #expect(!BackSwipeRule.goesBack(forward: 12, vertical: 2, fromEdge: false, width: width), "but a few points do not go back")
        #expect(!BackSwipeRule.goesBack(forward: 90, vertical: 5, fromEdge: false, width: width), "nor most of a quarter")
    }

    @Test func aLongSidewaysSwipeOnThePageGoesBack() {
        #expect(BackSwipeRule.goesBack(forward: 101, vertical: 10, fromEdge: false, width: width))
        #expect(BackSwipeRule.goesBack(forward: 200, vertical: 100, fromEdge: false, width: width), "exactly twice as far across still counts")
    }

    @Test func aScrollThatDriftsSidewaysNeverGoesBack() {
        #expect(!BackSwipeRule.mayBegin(forward: 12, vertical: 8, fromEdge: false), "more down than twice across: the page scrolls")
        #expect(!BackSwipeRule.goesBack(forward: 150, vertical: 120, fromEdge: false, width: width), "far, but not clearly sideways")
        #expect(!BackSwipeRule.mayBegin(forward: -20, vertical: 0, fromEdge: false), "towards the leading edge")
        #expect(!BackSwipeRule.goesBack(forward: -150, vertical: 0, fromEdge: true, width: width))
    }

    @Test func anEdgeSwipeGoesBackAtOnce() {
        #expect(BackSwipeRule.edgeWidth == 30)
        #expect(BackSwipeRule.mayBegin(forward: 10, vertical: 8, fromEdge: true), "from the edge, more across than down is enough")
        #expect(BackSwipeRule.goesBack(forward: 10, vertical: 8, fromEdge: true, width: width))
        #expect(!BackSwipeRule.goesBack(forward: 8, vertical: 10, fromEdge: true, width: width), "a mostly vertical drag from the edge")
    }
}
