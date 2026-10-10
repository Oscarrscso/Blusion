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

/// A zoomed screen closes on a back swipe the way it does from the back button: at once, without following the finger.
///
/// UIKit gives a zoomed screen a dismiss interaction of its own (edge swipe, swipe on the content, pinch), on the screen's view. It
/// drags the screen and lets it settle after the finger lifts. Until that settle ends, about a second, the screen is still the one
/// on top: its back button stays, the screen underneath takes no touches, and a new touch catches the closing screen again. Its
/// recognizers also make every other pan wait for them, so nothing can be put in front of them. That interaction is switched off
/// here, and one plain swipe pops the screen instead.
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

/// Sits unseen in a pushed screen to find that screen's own view, which SwiftUI does not hand out.
private final class SwipeBackProbe: UIView {
    let swipe = SwipeBack()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        swipe.attach(to: window == nil ? nil : pageView)
        guard window != nil, swipe.isDetached else { return }
        // The screen may not be in its navigation controller yet on the first pass.
        Task { @MainActor [weak self] in
            guard let self, self.window != nil, self.swipe.isDetached else { return }
            self.swipe.attach(to: self.pageView)
        }
    }

    /// The view of the view controller the navigation controller pushed for the screen this view is in. UIKit puts the zoom's
    /// dismiss interaction on that view, which also tells it apart.
    private var pageView: UIView? {
        var view = superview
        while let current = view {
            if let controller = current.next as? UIViewController, controller.parent is UINavigationController { return current }
            if current.interactions.contains(where: { SwipeBack.isDismissal($0) }) { return current }
            view = current.superview
        }
        return nil
    }
}

/// One pan recognizer on a pushed screen's view, with UIKit's own ways out of that screen switched off. A swipe towards the
/// trailing edge pops the screen.
@MainActor
private final class SwipeBack: NSObject, UIGestureRecognizerDelegate {
    var onSwipe: () -> Void = {}
    private lazy var pan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(swiped))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        return pan
    }()
    private weak var page: UIView?
    private weak var touched: UIView?
    private var startsAtEdge = false
    /// The navigation controller's back gestures, off while this screen is the one showing.
    private var silenced: [UIGestureRecognizer] = []

    /// A swipe that starts this close to the leading edge closes the screen even over a shelf that has been scrolled.
    private static let edgeWidth: CGFloat = 24

    var isDetached: Bool { page == nil }

    func attach(to page: UIView?) {
        pan.view?.removeGestureRecognizer(pan)
        silenced.forEach { $0.isEnabled = true }
        silenced = []
        self.page = page
        page?.addGestureRecognizer(pan)
        silenceSystemGestures()
    }

    private var controller: UIViewController? { page?.next as? UIViewController }

    private var isRightToLeft: Bool { page?.effectiveUserInterfaceLayoutDirection == .rightToLeft }

    /// The zoom's dismiss interaction and its parts are private classes, known here by name.
    nonisolated static func isDismissal(_ object: Any) -> Bool {
        let name = NSStringFromClass(type(of: object as AnyObject))
        return name.contains("Dismiss") && name.contains("Interaction")
    }

    /// Switches off UIKit's ways out of the screen: the zoom's dismiss interaction with its recognizers, on the screen's view, and
    /// the navigation controller's edge and content swipes. UIKit can switch them back on, so every touch does this again.
    private func silenceSystemGestures() {
        guard let page else { return }
        for interaction in page.interactions where Self.isDismissal(interaction) {
            guard let interaction = interaction as? NSObject, interaction.responds(to: NSSelectorFromString("setIsEnabled:")) else { continue }
            interaction.setValue(false, forKey: "isEnabled")
        }
        for recognizer in page.gestureRecognizers ?? [] where recognizer !== pan && recognizer.isEnabled {
            if let delegate = recognizer.delegate, Self.isDismissal(delegate) { recognizer.isEnabled = false }
        }
        let stack = controller?.navigationController
        for recognizer in [stack?.interactivePopGestureRecognizer, stack?.interactiveContentPopGestureRecognizer] {
            guard let recognizer, recognizer.isEnabled else { continue }
            recognizer.isEnabled = false
            silenced.append(recognizer)
        }
    }

    @objc private func swiped() {
        guard pan.state == .began, let page, controller?.transitionCoordinator == nil else { return }
        // Off at once: a touch that lands while the screen zooms away goes to the screen underneath.
        page.isUserInteractionEnabled = false
        onSwipe()
        // Should the pop not happen, the screen works again.
        Task { [weak page] in
            try? await Task.sleep(for: .seconds(1.5))
            if let page, page.window != nil { page.isUserInteractionEnabled = true }
        }
    }

    /// A sideways shelf that has been scrolled keeps the swipe: it scrolls back to its start first.
    private var isOverScrolledShelf: Bool {
        var view = touched
        while let current = view, current !== page {
            if let shelf = current as? UIScrollView, shelf.isScrollEnabled, shelf.contentSize.width > shelf.bounds.width + 1 {
                let start = -shelf.adjustedContentInset.left
                let end = shelf.contentSize.width - shelf.bounds.width + shelf.adjustedContentInset.right
                if isRightToLeft ? shelf.contentOffset.x < end - 1 : shelf.contentOffset.x > start + 1 { return true }
            }
            view = current.superview
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let page else { return false }
        silenceSystemGestures()
        touched = touch.view
        let x = touch.location(in: page).x
        startsAtEdge = isRightToLeft ? x > page.bounds.width - Self.edgeWidth : x < Self.edgeWidth
        return true
    }

    /// Only a swipe that is more sideways than vertical, towards the trailing edge, on the top screen and with no transition running.
    /// Anything else fails here, and the page's scrolling carries on as it would without this recognizer.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let page else { return false }
        let movement = pan.translation(in: page)
        let forward = isRightToLeft ? -movement.x : movement.x
        let stack = controller?.navigationController
        let isOnTop = stack == nil || stack?.topViewController === controller
        guard isOnTop, controller?.transitionCoordinator == nil, forward > abs(movement.y) else { return false }
        return startsAtEdge || !isOverScrolledShelf
    }

    /// Scrolling and SwiftUI's own gestures are left alone: they track the same touch, so they start no later than before.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer.view is UIScrollView || NSStringFromClass(type(of: otherGestureRecognizer)).contains("SwiftUI")
    }
}
#endif
