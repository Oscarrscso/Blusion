#if canImport(UIKit)
import SwiftUI

/// The one main action of a screen ("Play", "Resume", "Install"): a white capsule with dark text, the way Apple's media apps
/// draw it on dark artwork. Everything else on the screen uses `.glass` or a plain button.
struct PrimaryActionButtonStyle: ButtonStyle {
    /// False sizes the button to its label (empty states, inline calls to action) instead of the full width.
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryActionLabel(configuration: configuration, fillsWidth: fillsWidth)
    }
}

/// A view of its own because a `ButtonStyle` cannot read the environment itself.
private struct PrimaryActionLabel: View {
    let configuration: ButtonStyleConfiguration
    let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 50)
            .background(.white.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    /// Full-width white capsule: the screen's main action.
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
    /// The same button, only as wide as its label.
    static var primaryActionCompact: PrimaryActionButtonStyle { PrimaryActionButtonStyle(fillsWidth: false) }
}
#endif
