#if canImport(UIKit)
import SwiftUI

/// A filter chip: the system's Liquid Glass button as a capsule, and the selected one its prominent form in white with dark text
/// (the same inversion as the TV app's category filters). Semibold in both states, so selecting never shifts the neighbours.
struct GlassChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let fillsWidth: Bool
    /// The small size, for a row of removable filters that sits above a list.
    let isCompact: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isSelected: Bool = false, fillsWidth: Bool = false, isCompact: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.fillsWidth = fillsWidth
        self.isCompact = isCompact
        self.action = action
    }

    var body: some View {
        Group {
            if isSelected {
                button.buttonStyle(.glassProminent).tint(.white)
            } else {
                button.buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(isCompact ? .small : fillsWidth ? .large : .regular)
        .pointerFeedback()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("chip.\(title)")
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var button: some View {
        Button(action: action) {
            label
                .font(.subheadline.weight(.semibold))
                .lineLimit(fillsWidth ? 1 : nil)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
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
    let fittingColumns: Int?
    @Environment(\.layoutMetrics) private var metrics

    init(fittingColumns: Int? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.fittingColumns = fittingColumns
    }

    @ViewBuilder var body: some View {
        if let fittingColumns {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: max(1, fittingColumns)),
                          spacing: Theme.Spacing.s) { content() }
            }
            .padding(.horizontal, metrics.pageMargin)
        } else {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    content()
                }
            }
        }
        .shelfIndicators()
        .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
        .scrollClipDisabled()
        }
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
    /// The space kept on each side of a dot when the parts are spread, so a dot never touches the text beside it.
    private static let minimumGap: CGFloat = 4
    /// The fewest parts that are spread across the width. Fewer would leave wide gaps between them, so they are joined as usual.
    private static let minimumSpreadParts = 5

    private let parts: [String]
    /// The accessibility identifier of the line, for UI tests. Nil leaves it unset.
    private let identifier: String?
    /// True spreads the parts across the whole width the line is given, with the dots between them, so the line is as wide as what sits
    /// under it. When the parts do not fit on one line that way, the line is drawn as usual.
    private let spreads: Bool

    init(_ parts: [String?], identifier: String? = nil, spreads: Bool = false) {
        self.parts = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.identifier = identifier
        self.spreads = spreads
    }

    var body: some View {
        if !parts.isEmpty {
            let line = partsLine
                .font(Theme.Typography.metaLine)
                .foregroundStyle(Theme.metaText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(parts.joined(separator: ", "))
            if let identifier {
                line.accessibilityIdentifier(identifier)
            } else {
                line
            }
        }
    }

    /// The parts as drawn: spread across the width when `spreads` is set and there are at least `minimumSpreadParts`, otherwise joined by dots
    /// on one wrapped line.
    @ViewBuilder
    private var partsLine: some View {
        let joinedLine = Text(parts.joined(separator: " · "))
            .fixedSize(horizontal: false, vertical: true)
        if spreads && parts.count >= Self.minimumSpreadParts {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        if index > 0 {
                            Spacer(minLength: Self.minimumGap)
                            Text("·")
                            Spacer(minLength: Self.minimumGap)
                        }
                        Text(part)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity)
                joinedLine
            }
        } else {
            joinedLine
        }
    }
}
#endif
