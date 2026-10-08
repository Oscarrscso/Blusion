#if canImport(UIKit)
import SwiftUI

/// The one main action of a screen ("Play", "Resume", "Install"): a white capsule with dark text, the way the TV app draws its
/// Play button. Everything else on the screen uses a glass style or a plain button. `.controlSize` picks the height:
/// 50 pt regular, 56 large (the hero's button on a Mac), 40 small and 32 mini.
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
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(.black)
            .padding(.horizontal, controlSize == .mini || controlSize == .small ? Theme.Spacing.l : Theme.Spacing.xl)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height)
            .background(.white.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .pointerInteraction(cornerRadius: 999, highlightColor: .black)
    }

    private var height: CGFloat {
        switch controlSize {
        case .mini: 32
        case .small: 40
        case .large, .extraLarge: 56
        default: 50
        }
    }

    private var font: Font {
        switch controlSize {
        case .mini, .small: .subheadline.weight(.semibold)
        default: Theme.Typography.button
        }
    }
}

/// A secondary action as a compact Liquid Glass capsule ("Trailer", "Customize", "Try again"): label-sized, semibold subheadline.
/// Do not stack it on other glass and do not use it for the screen's main action.
struct GlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s + 1)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
            .pointerInteraction(cornerRadius: 999)
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    /// Full-width white capsule: the screen's main action.
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
    /// The same button, only as wide as its label.
    static var primaryActionCompact: PrimaryActionButtonStyle { PrimaryActionButtonStyle(fillsWidth: false) }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    /// A compact glass capsule for secondary actions.
    static var glassCapsule: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle() }
}

/// The TV app's secondary action on a title page: a round Liquid Glass button with a small grey caption under it ("Add",
/// "Watched", "Trailer"). With `isOn` it shows `onSystemImage` (default: the same symbol, filled) and `onTitle` ("Added"); the
/// symbol swaps with the system replace effect. The circle and the caption are one button, one VoiceOver element.
///
/// Several in a row belong in one `GlassEffectContainer` (or `CircleActionRow`) so the glass is composed once.
struct CircleActionButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let onTitle: String?
    let onSystemImage: String?
    let action: () -> Void

    init(title: String, systemImage: String, isOn: Bool = false, onTitle: String? = nil, onSystemImage: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.onTitle = onTitle
        self.onSystemImage = onSystemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s - 2) {
                Image(systemName: isOn ? (onSystemImage ?? systemImage) : systemImage)
                    .symbolVariant(isOn && onSystemImage == nil ? .fill : .none)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.diameter, height: Self.diameter)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .pointerInteraction(cornerRadius: Self.diameter / 2)
                Text(isOn ? (onTitle ?? title) : title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.diameter + 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }

    /// The height of the primary action beside it on the title page, so the two read as one row.
    static let diameter: CGFloat = 50
}

/// A row of `CircleActionButton`s the way a title page lays them out: one glass container, even gaps, leading aligned.
struct CircleActionRow<Content: View>: View {
    var spacing: CGFloat = Theme.Spacing.xl
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(alignment: .top, spacing: spacing) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
