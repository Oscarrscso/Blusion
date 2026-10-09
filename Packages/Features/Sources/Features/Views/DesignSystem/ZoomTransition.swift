#if canImport(UIKit)
import SwiftUI
import StremioKit

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

    /// Makes a pushed screen zoom out of the artwork marked with the same id.
    @ViewBuilder
    func zoomDestination(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
#endif
