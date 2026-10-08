#if canImport(UIKit)
import SwiftUI

/// A Liquid Glass capsule button for filters and quick actions. The selected chip is a solid white capsule with dark text.
struct GlassChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background { if isSelected { Capsule().fill(.white) } }
                .glassEffect(isSelected ? .identity : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("chip.\(title)")
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

/// A horizontal scroller of chips. The chips share one `GlassEffectContainer`, so neighbouring glass shapes blend together.
struct ChipRow<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    content()
                }
            }
        }
        .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
        .scrollClipDisabled()
    }
}

/// A small non-interactive label such as "4K", "HDR", "Dolby Vision" or "Watched".
struct Badge: View {
    enum Style {
        case neutral, accent, quality, warning
    }

    let text: String
    let systemImage: String?
    let style: Style

    init(_ text: String, systemImage: String? = nil, style: Style = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        label
            .font(.caption2.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background { surface }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(text, systemImage: systemImage)
        } else {
            Text(text)
        }
    }

    private var foreground: Color {
        switch style {
        case .neutral, .quality: .primary
        case .accent: .white
        case .warning: .orange
        }
    }

    /// A warning differs from a neutral badge only in its text colour: no coloured block, in keeping with the design bar.
    @ViewBuilder
    private var surface: some View {
        switch style {
        case .neutral, .warning: Capsule().fill(Color.white.opacity(0.14))
        case .accent: Capsule().fill(Theme.brandGradient)
        case .quality: RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        }
    }
}

/// "★ 8.4" on a dark translucent capsule. Sits on artwork, so it is dark whatever the picture is.
struct RatingBadge: View {
    let rating: Double

    init(_ rating: Double) {
        self.rating = rating
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text(rating.formatted(.number.precision(.fractionLength(1))))
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating \(rating.formatted(.number.precision(.fractionLength(1))))")
    }
}

/// Dot-separated metadata such as "2023 · 2 h 49 min · ★ 8.4". Nil and empty parts are skipped, and it renders nothing when every
/// part is skipped.
struct MetaLine: View {
    private let parts: [String]

    init(_ parts: [String?]) {
        self.parts = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(parts.joined(separator: ", "))
        }
    }
}
#endif
