import CoreGraphics

/// When a swipe on a pushed screen (a title's page) goes back. A swipe from the leading edge goes back at once, as the system's does. A
/// swipe that starts on the page has to mean it: it travels a quarter of the page's width and is clearly sideways, at least twice as far
/// across as up or down, so a nudge, or a scroll that drifts sideways, keeps the page.
public enum BackSwipeRule {
    /// A swipe that starts this close to the leading edge is an edge swipe.
    public static let edgeWidth: CGFloat = 30
    /// The share of the page's width a swipe that starts on the page travels before it goes back.
    public static let pageTravel: CGFloat = 0.25
    /// How many times further across than up or down a swipe that starts on the page goes.
    public static let sidewaysRatio: CGFloat = 2

    /// Whether the swipe may start, `forward` towards the trailing edge and `vertical` down so far: an edge swipe more across than up or
    /// down, a swipe on the page `sidewaysRatio` times more, so a scroll that drifts sideways never starts one.
    public static func mayBegin(forward: CGFloat, vertical: CGFloat, fromEdge: Bool) -> Bool {
        forward > (fromEdge ? 1 : sidewaysRatio) * abs(vertical)
    }

    /// Whether the swipe goes back now, `forward` towards the trailing edge and `vertical` down so far, on a page `width` wide.
    public static func goesBack(forward: CGFloat, vertical: CGFloat, fromEdge: Bool, width: CGFloat) -> Bool {
        guard forward > 0 else { return false }
        if fromEdge { return forward > abs(vertical) }
        return forward >= width * pageTravel && forward >= sidewaysRatio * abs(vertical)
    }
}
