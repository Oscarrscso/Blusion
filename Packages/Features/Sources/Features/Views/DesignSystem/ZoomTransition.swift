#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// A title opened from a card: the value a `MediaCardLink` pushes. `sourceID` names the exact card, so the title's screen zooms
/// out of that artwork even when the same title is on screen in two rows.
struct TitleDestination: Hashable {
    let preview: MetaPreview
    let sourceID: String
    var artwork: TMDbArtwork?
}

extension EnvironmentValues {
    /// The namespace cards and the screens they open share. Set once per navigation stack by `zoomTransitions()`.
    @Entry var zoomNamespace: Namespace.ID?
    /// Tells apart the cards of different rows that show the same title. `MediaRow` and `MediaGrid` set it; a custom container
    /// of `MediaCardLink`s should set its own.
    @Entry var zoomScope: String = ""
}

private struct ZoomNamespaceProvider: ViewModifier {
    @Namespace private var namespace

    func body(content: Content) -> some View {
        content.environment(\.zoomNamespace, namespace)
    }
}

extension View {
    /// Lets the cards in a navigation stack zoom into the screens they open. Apply to the `NavigationStack` itself.
    func zoomTransitions() -> some View {
        modifier(ZoomNamespaceProvider())
    }

    /// Marks the artwork a screen zooms out of. `cornerRadius` rounds the artwork while it morphs into the screen, so a card keeps its
    /// corners; leave it nil for full-bleed artwork. Does nothing without a namespace (outside a stack that called `zoomTransitions()`).
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID?, cornerRadius: CGFloat? = nil) -> some View {
        if let namespace, let cornerRadius {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            matchedTransitionSource(id: id, in: namespace) { $0.clipShape(shape) }
        } else if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Makes a pushed screen zoom out of the artwork marked with the same id. A back swipe closes it at once (see `SwipeBackCloses`).
    @ViewBuilder
    func zoomDestination(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
                .modifier(SwipeBackCloses())
        } else {
            self
        }
    }
}

/// A zoomed screen closes on a back swipe the way it does from the back button: at once, without following the finger. The system's
/// own swipe drags the screen and lets it settle after the finger lifts. Until that settle ends, about a second, the screen is still
/// the one on top: its back button stays, the screen underneath takes no touches, and a new touch catches the closing screen again.
private struct SwipeBackCloses: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.background {
            SwipeBackCatcher { dismiss() }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct SwipeBackCatcher: UIViewRepresentable {
    let onSwipe: () -> Void

    func makeUIView(context: Context) -> SwipeBackProbe {
        let probe = SwipeBackProbe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: SwipeBackProbe, context: Context) {
        probe.swipe.onSwipe = onSwipe
    }
}

/// Sits unseen in a pushed screen to find that screen's view controller, which SwiftUI does not hand out.
private final class SwipeBackProbe: UIView {
    let swipe = SwipeBack()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        swipe.attach(to: window == nil ? nil : pushedController)
    }

    /// The view controller the navigation controller pushed for the screen this view is in.
    private var pushedController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder, !(current is UIViewController) { responder = current.next }
        var controller = responder as? UIViewController
        while let parent = controller?.parent, !(parent is UINavigationController) { controller = parent }
        return controller?.parent is UINavigationController ? controller : nil
    }
}

/// One pan recognizer on a pushed screen's view. A swipe towards the trailing edge pops the screen, and the system's own back
/// gestures wait for this one, so they never start their drag for that touch.
@MainActor
private final class SwipeBack: NSObject, UIGestureRecognizerDelegate {
    var onSwipe: () -> Void = {}
    private lazy var pan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(swiped))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        return pan
    }()
    private weak var page: UIViewController?
    private weak var touched: UIView?
    private var startsAtEdge = false
    /// The system's back gestures, switched off from the swipe until the screen has gone.
    private var suspended: [UIGestureRecognizer] = []

    /// A swipe that starts this close to the leading edge closes the screen even over a shelf that has been scrolled.
    private static let edgeWidth: CGFloat = 24

    func attach(to page: UIViewController?) {
        pan.view?.removeGestureRecognizer(pan)
        resume()
        self.page = page
        page?.view.addGestureRecognizer(pan)
    }

    @objc private func swiped() {
        guard pan.state == .began, let page, page.transitionCoordinator == nil else { return }
        // Off at once: a touch that lands while the screen zooms away reaches the screen underneath instead of catching this one.
        page.view.isUserInteractionEnabled = false
        suspended = systemBackGestures(of: page).filter { $0.isEnabled }
        suspended.forEach { $0.isEnabled = false }
        onSwipe()
        // The screen leaving its window undoes this (`attach`). Should the pop not happen, the screen works again.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.recover()
        }
    }

    private func recover() {
        if let page, page.view.window != nil { page.view.isUserInteractionEnabled = true }
        resume()
    }

    private func resume() {
        suspended.forEach { $0.isEnabled = true }
        suspended = []
    }

    /// The system's own ways out of the screen: the navigation controller's edge and content swipes and the zoom's drag. They are
    /// private classes, so they are known by where they sit (on the screen's view or above it, up to the navigation controller's)
    /// and by not being SwiftUI's or a scroll view's.
    private func isSystemBackGesture(_ other: UIGestureRecognizer, of page: UIViewController) -> Bool {
        guard other !== pan, let owner = other.view, !(owner is UIScrollView), page.view.isDescendant(of: owner),
              let stack = page.navigationController?.view, owner.isDescendant(of: stack) else { return false }
        let name = NSStringFromClass(type(of: other))
        guard !name.contains("SwiftUI") else { return false }
        return other is UIPanGestureRecognizer || ["Zoom", "Transform", "Dismiss", "Pop"].contains { name.contains($0) }
    }

    private func systemBackGestures(of page: UIViewController) -> [UIGestureRecognizer] {
        var found: [UIGestureRecognizer] = []
        var view: UIView? = page.view
        while let current = view {
            found += (current.gestureRecognizers ?? []).filter { isSystemBackGesture($0, of: page) }
            if current === page.navigationController?.view { break }
            view = current.superview
        }
        return found
    }

    /// A sideways shelf that has been scrolled keeps the swipe: it scrolls back first, as it does under the system's gesture.
    private var isOverScrolledShelf: Bool {
        var view = touched
        while let current = view, current !== pan.view {
            if let shelf = current as? UIScrollView, shelf.isScrollEnabled, shelf.contentSize.width > shelf.bounds.width + 1,
               shelf.contentOffset.x > 1 - shelf.adjustedContentInset.left {
                return true
            }
            view = current.superview
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = gestureRecognizer.view else { return false }
        touched = touch.view
        startsAtEdge = touch.location(in: view).x < Self.edgeWidth
        return true
    }

    /// Only a swipe that is more sideways than vertical, towards the trailing edge, on the top screen and with no transition running.
    /// Anything else fails here, and the system's gestures and the page's scrolling carry on as they would without this recognizer.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let page, let view = pan.view, view.effectiveUserInterfaceLayoutDirection == .leftToRight,
              page.navigationController?.topViewController === page, page.transitionCoordinator == nil else { return false }
        let movement = pan.translation(in: view)
        guard movement.x > abs(movement.y) else { return false }
        return startsAtEdge || !isOverScrolledShelf
    }

    /// Scrolling is left alone: the page and its shelves track the same touch, so they start no later than before.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer.view is UIScrollView || NSStringFromClass(type(of: otherGestureRecognizer)).contains("SwiftUI")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let page else { return false }
        return isSystemBackGesture(otherGestureRecognizer, of: page)
    }
}
#endif
