#if canImport(UIKit)
import SwiftUI

/// A filter chip as iOS 26 draws it: a Liquid Glass capsule, and the selected one a solid white capsule with dark text (the
/// same inversion as the TV app's category filters). Semibold in both states, so selecting never shifts the neighbours.
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s + 1)
                .background { if isSelected { Capsule().fill(.white) } }
                .glassEffect(isSelected ? .identity : .regular.interactive(), in: .capsule)
                .contentShape(Capsule())
                .pointerInteraction(cornerRadius: 999, highlightColor: isSelected ? .black : .white)
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
    @Environment(\.layoutMetrics) private var metrics

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
        .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
        .scrollClipDisabled()
    }
}

/// A small non-interactive label such as "4K", "HDR", "Dolby Vision" or "Watched". `.quality` is the TV app's capability glyph:
/// grey text in a thin outline.
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
            .font(style == .quality ? .system(size: 10, weight: .bold) : .caption2.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, style == .quality ? 6 : 7)
            .padding(.vertical, style == .quality ? 2 : 3)
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
        case .neutral: .primary
        case .quality: .white.opacity(0.62)
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
        case .quality: RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
        }
    }
}

/// A row of capability badges ("4K", "Dolby Vision", "HDR") under a title's name. Draws nothing for an empty list.
struct CapabilityBadges: View {
    let names: [String]

    init(_ names: [String]) {
        self.names = names
    }

    var body: some View {
        if !names.isEmpty {
            HStack(spacing: Theme.Spacing.s - 2) {
                ForEach(names, id: \.self) { Badge($0, style: .quality) }
            }
        }
    }
}

/// "★ 8.4" in quiet semibold white, for a place where one number is enough. Has no backdrop of its own: it assumes dark artwork
/// or a fade behind it. Posters carry `PosterRatingsOverlay` instead (IMDb and Letterboxd).
struct RatingBadge: View {
    let rating: Double

    init(_ rating: Double) {
        self.rating = rating
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text(rating.formatted(.number.precision(.fractionLength(1))))
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating \(rating.formatted(.number.precision(.fractionLength(1))))")
    }
}

/// Dot-separated metadata such as "Drama · 2008 · 2 hr 32 min". Nil and empty parts are skipped, and it renders nothing when every
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
                .font(Theme.Typography.metaLine)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(parts.joined(separator: ", "))
        }
    }
}
#endif
