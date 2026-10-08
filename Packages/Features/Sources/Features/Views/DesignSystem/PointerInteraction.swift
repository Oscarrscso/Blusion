#if canImport(UIKit)
import SwiftUI

/// Shared pointer feedback for custom controls; it never changes their layout or adds a separate focus target.
private struct PointerInteractionModifier: ViewModifier {
    let cornerRadius: CGFloat
    let lifts: Bool
    let highlightColor: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(highlightColor.opacity(isEnabled && isHovering ? 0.08 : 0))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(highlightColor.opacity(isEnabled && isFocused ? 0.8 : 0), lineWidth: 2)
                    }
                    .allowsHitTesting(false)
            }
            .scaleEffect(isEnabled && lifts && !reduceMotion && (isHovering || isFocused) ? 1.025 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovering)
            .hoverEffect(.highlight, isEnabled: isEnabled)
            .onHover { isHovering = isEnabled && $0 }
    }
}

extension View {
    func pointerInteraction(cornerRadius: CGFloat = Theme.Radius.card, lifts: Bool = false, highlightColor: Color = .white) -> some View {
        modifier(PointerInteractionModifier(cornerRadius: cornerRadius, lifts: lifts, highlightColor: highlightColor))
    }
}
#endif
