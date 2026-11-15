#if canImport(UIKit)
import os
import StremioKit
import SwiftUI
import UIKit
// The second-finger scroll sets its own recognizer state, which only this part of UIKit allows.
// swiftlint:disable:next duplicate_imports
import UIKit.UIGestureRecognizerSubclass

/// A card being dragged: which one, where the grab was, where the pointer is now, and the order before the drag.
struct GridDrag: Equatable {
    let id: String
    /// The pointer minus the card's centre when the drag began, so the card keeps its place under the finger.
    let grabOffset: CGSize
    var pointer: CGPoint
    let originalOrder: [String]
}

/// The grid's link to the page's UIKit scroll view, found from a plain view behind the grid (`GridScrollAnchor`).
///
/// On iPhone the long press that lifts a card is put on that scroll view, outside SwiftUI's gestures. Attached to the grid, it came after the
/// cards' own taps, delete buttons and menus, which could keep it from ever starting. A quick swipe still scrolls: the press fails once
/// the finger moves 10 points before it has been held for 0.2 s. On iPhone and the Mac, the page scrolls while a held card is near the top
/// or bottom of what is visible.
@MainActor
final class GridScroller: NSObject, UIGestureRecognizerDelegate {
    /// Whether a touch at this point, in the grid's coordinates, may lift a card.
    var canLift: (CGPoint) -> Bool = { _ in false }
    /// Whether a card is held now.
    var isHolding: () -> Bool = { false }
    var began: (CGPoint) -> Void = { _ in }
    var changed: (CGPoint) -> Void = { _ in }
    /// Called with true when the press was cancelled, and false when it ended.
    var ended: (Bool) -> Void = { _ in }

    private weak var anchor: UIView?
    private weak var scrollView: UIScrollView?
    /// How far a second finger has moved the page since the drag last asked (see `takeFingerScroll`).
    private var fingerScroll: CGFloat = 0
    #if !targetEnvironment(macCatalyst)
    /// While a card is held, a second finger scrolls the page (see `SecondFingerScroll`). Intentionally iOS-only: the Mac has no touches.
    private lazy var secondFinger: SecondFingerScroll = {
        let recognizer = SecondFingerScroll(target: nil, action: nil)
        recognizer.isHolding = { [weak self] in self?.isHolding() ?? false }
        recognizer.scroll = { [weak self] delta in self?.scrollByFinger(delta) }
        return recognizer
    }()
    private lazy var press: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        recognizer.minimumPressDuration = 0.2
        recognizer.allowableMovement = 10
        recognizer.delegate = self
        return recognizer
    }()
    #endif

    /// Finds the scroll view around the anchor, and puts the press on it.
    func attach(_ anchor: UIView) {
        self.anchor = anchor
        var view = anchor.superview
        while let current = view, !(current is UIScrollView) { view = current.superview }
        let found = view as? UIScrollView
        guard found !== scrollView else { return }
        detach()
        scrollView = found
        dragLog.notice("grid \(found == nil ? "found no scroll view" : "attached to its scroll view", privacy: .public)")
        #if !targetEnvironment(macCatalyst)
        found?.addGestureRecognizer(press)
        found?.addGestureRecognizer(secondFinger)
        #endif
    }

    /// The anchor left the window, for a pushed screen or a fading grid: the press comes off the scroll view. An anchor that a newer one
    /// has replaced (a grid hidden and shown again while it faded) changes nothing, so it cannot take the newer grid's press away.
    func detach(from anchor: UIView) {
        guard anchor === self.anchor else { return }
        detach()
    }

    /// The anchor is gone for good: the press comes off, and the grid's actions are let go, so they do not keep the page's state alive.
    func release(_ anchor: UIView) {
        guard anchor === self.anchor else { return }
        detach()
        canLift = { _ in false }
        isHolding = { false }
        began = { _ in }
        changed = { _ in }
        ended = { _ in }
    }

    private func detach() {
        #if !targetEnvironment(macCatalyst)
        press.view?.removeGestureRecognizer(press)
        secondFinger.view?.removeGestureRecognizer(secondFinger)
        #endif
        scrollView = nil
        fingerScroll = 0
    }

    /// How far a second finger has moved the page since the last call, and starts counting again.
    func takeFingerScroll() -> CGFloat {
        defer { fingerScroll = 0 }
        return fingerScroll
    }

    /// Moves the page by `delta` points under a second finger, within its content, and counts how far it went.
    private func scrollByFinger(_ delta: CGFloat) {
        fingerScroll += move(by: delta)
    }

    #if !targetEnvironment(macCatalyst)
    @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
        guard let anchor else { return }
        let point = recognizer.location(in: anchor)
        switch recognizer.state {
        case .began: began(point)
        case .changed: changed(point)
        case .ended: ended(false)
        case .cancelled, .failed: ended(true)
        default: break
        }
    }

    /// Only a touch on a card that can be lifted: everywhere else, the press does not take part at all.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let anchor else { return false }
        return canLift(touch.location(in: anchor))
    }

    /// The navigation stack's swipes back wait for the press to fail, so a card carried sideways never takes the page back. The scroll
    /// view's own pan does not wait: a quick swipe scrolls at once.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard let scrollView, other is UIPanGestureRecognizer, let view = other.view else { return false }
        return !view.isDescendant(of: scrollView)
    }
    #endif

    /// Scrolls the page one step while `point`, in the grid's coordinates, is near the top or bottom of what is visible, faster nearer
    /// the edge. Returns how far the page moved, so the held card's place can follow the content under it.
    func autoScrollStep(at point: CGPoint) -> CGFloat {
        guard let anchor, let scrollView else { return 0 }
        let insets = scrollView.adjustedContentInset
        let y = anchor.convert(point, to: scrollView).y - scrollView.contentOffset.y
        let top = insets.top
        let bottom = scrollView.bounds.height - insets.bottom
        let zone: CGFloat = 70
        var step: CGFloat = 0
        if y < top + zone {
            step = -(2 + 18 * min(1, (top + zone - y) / zone))
        } else if y > bottom - zone {
            step = 2 + 18 * min(1, (y - (bottom - zone)) / zone)
        }
        guard step != 0 else { return 0 }
        return move(by: step)
    }

    /// Moves the page by `step` points, kept within its content. Returns how far it moved.
    private func move(by step: CGFloat) -> CGFloat {
        guard let scrollView else { return 0 }
        let insets = scrollView.adjustedContentInset
        let next = WidgetSlotLayout.scrolledOffset(scrollView.contentOffset.y, by: step, lowest: -insets.top,
                                                   highest: scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
        let moved = next - scrollView.contentOffset.y
        if moved != 0 { scrollView.contentOffset.y = next }
        return moved
    }
}

#if !targetEnvironment(macCatalyst)
/// While a card is held, a second finger anywhere on the page scrolls it, as the page's own scrolling would, while the card stays under the
/// first finger. The page's own scrolling is off during a drag (it would follow the held card's finger), so this moves the page itself. It
/// never takes part otherwise: it never recognizes, never stops another gesture or a tap, and ignores the finger that holds the card.
private final class SecondFingerScroll: UIGestureRecognizer {
    var isHolding: () -> Bool = { false }
    var scroll: (CGFloat) -> Void = { _ in }
    private weak var finger: UITouch?
    private var lastY: CGFloat = 0

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Only a finger that comes down while a card is already held by another one.
        guard finger == nil, isHolding(), let touch = touches.first, (event.allTouches?.count ?? 0) > 1 else { return }
        finger = touch
        lastY = touch.location(in: nil).y
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let finger, touches.contains(finger) else { return }
        // The card was put down: the finger stops scrolling, so nothing builds up for the next card.
        guard isHolding() else {
            self.finger = nil
            return
        }
        // Read in the window's coordinates, which the page's scrolling does not move. A finger moving up moves the page down.
        let y = finger.location(in: nil).y
        scroll(lastY - y)
        lastY = y
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finished(touches, event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finished(touches, event) }

    /// The second finger lifting stops the scroll. Once every finger is up, the recognizer is done until the next touch.
    private func finished(_ touches: Set<UITouch>, _ event: UIEvent) {
        if let finger, touches.contains(finger) { self.finger = nil }
        if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) ?? true { state = .failed }
    }

    override func reset() {
        finger = nil
    }
}
#endif

/// A plain view behind the grid, the same size, that hands `GridScroller` the page's scroll view and the grid's coordinates. It takes no
/// touches itself.
struct GridScrollAnchor: UIViewRepresentable {
    let scroller: GridScroller
    let canLift: (CGPoint) -> Bool
    let isHolding: () -> Bool
    let began: (CGPoint) -> Void
    let changed: (CGPoint) -> Void
    let ended: (Bool) -> Void

    final class AnchorView: UIView {
        weak var scroller: GridScroller?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { scroller?.detach(from: self) } else { scroller?.attach(self) }
        }
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.scroller = scroller
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.scroller = scroller
        scroller.canLift = canLift
        scroller.isHolding = isHolding
        scroller.began = began
        scroller.changed = changed
        scroller.ended = ended
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        view.scroller?.release(view)
    }
}
#endif
