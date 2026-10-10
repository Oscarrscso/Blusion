#if canImport(UIKit)
import SwiftUI

/// The one main action of a screen ("Play", "Resume", "Install"): the system's Liquid Glass button as a capsule, the button the
/// navigation bar draws. `.controlSize` picks its size; with none set it is the large one, level with the round actions beside it.
struct PrimaryActionButtonStyle: PrimitiveButtonStyle {
    /// False sizes the button to its label (empty states, inline calls to action) instead of the full width.
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryActionButton(configuration: configuration, fillsWidth: fillsWidth)
    }
}

/// A view of its own because a button style cannot read the environment itself.
private struct PrimaryActionButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let fillsWidth: Bool
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        Button(role: configuration.role) {
            Haptics.tap()
            configuration.trigger()
        } label: {
            configuration.label
                .fontWeight(.semibold)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        // A main action is one size up from the controls around it.
        .controlSize(controlSize == .regular ? .large : controlSize)
    }
}

/// A secondary action ("Customize", "Open on Best Blurays"): the system's Liquid Glass button as a label-sized capsule.
/// Do not stack it on other glass and do not use it for the screen's main action.
struct GlassCapsuleButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            Haptics.tap()
            configuration.trigger()
        } label: {
            configuration.label
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }
}

extension PrimitiveButtonStyle where Self == PrimaryActionButtonStyle {
    /// Full-width glass capsule: the screen's main action.
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
    /// The same button, only as wide as its label.
    static var primaryActionCompact: PrimaryActionButtonStyle { PrimaryActionButtonStyle(fillsWidth: false) }
}

extension PrimitiveButtonStyle where Self == GlassCapsuleButtonStyle {
    /// A compact glass capsule for secondary actions.
    static var glassCapsule: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle() }
}

extension View {
    /// Makes an icon button the system's round Liquid Glass button, the one the navigation bar draws.
    func glassCircleButton(_ size: ControlSize = .large) -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(size)
    }
}

/// A secondary action on a title page: the system's round Liquid Glass button with its symbol and no caption. `title` ("Add",
/// "Watched", "Trailer") is its VoiceOver label. With `isOn` it shows `onSystemImage` (default: the same symbol, filled) and
/// `onTitle` ("Added"); the symbol swaps with the system replace effect.
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
            Image(systemName: isOn ? (onSystemImage ?? systemImage) : systemImage)
                .symbolVariant(isOn && onSystemImage == nil ? .fill : .none)
                .fontWeight(.semibold)
                .contentTransition(.symbolEffect(.replace))
        }
        // The large size, like the main action beside it on the title page, so the two read as one row.
        .glassCircleButton()
        // The caption is gone, so the name is spoken here instead.
        .accessibilityLabel(isOn ? (onTitle ?? title) : title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
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
