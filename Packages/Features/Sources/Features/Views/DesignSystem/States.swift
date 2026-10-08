#if canImport(UIKit)
import SwiftUI

/// A centred empty or unavailable state with an optional primary action.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, systemImage: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        EmptyStateLayout(title: title, systemImage: systemImage, message: message) {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primaryActionCompact)
                    .padding(.top, Theme.Spacing.s)
                    .accessibilityIdentifier("emptyState.action")
            }
        }
    }
}

/// The layout every empty state shares: a symbol, a title, an optional message and an optional action. Screens that need a
/// particular identifier on their button use this directly.
struct EmptyStateLayout<Action: View>: View {
    let title: String
    let systemImage: String
    let message: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A compact inline failure: a warning icon and the text, with a "Try again" button when `retry` is set. It sits on a neutral
/// surface, not a coloured block, so an error reads as news on the screen rather than as an alarm.
struct InlineErrorView: View {
    let text: String
    let retry: (() -> Void)?

    init(_ text: String, retry: (() -> Void)? = nil) {
        self.text = text
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityIdentifier("inlineError.retry")
            }
        }
        .padding(Theme.Spacing.m)
        .cardSurface(cornerRadius: Theme.Radius.poster)
    }
}

/// A grey placeholder shaped like one card, shown while its content loads. It does not shimmer itself: put `shimmering()` on the
/// container of a group, as `SkeletonRow` does, so a long grid does not run one highlight per item.
struct SkeletonCard: View {
    let aspect: CardAspect
    let size: CardSize

    init(aspect: CardAspect = .poster, size: CardSize = .medium) {
        self.aspect = aspect
        self.size = size
    }

    var body: some View {
        SkeletonShapes(aspect: aspect, size: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

/// A row of grey card placeholders with the same margins as `MediaRow`. One shimmer sweeps the whole row.
struct SkeletonRow: View {
    let aspect: CardAspect
    let size: CardSize
    let count: Int

    init(aspect: CardAspect = .poster, size: CardSize = .medium, count: Int = 6) {
        self.aspect = aspect
        self.size = size
        self.count = count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.cardSpacing) {
                ForEach(0..<max(count, 0), id: \.self) { _ in
                    SkeletonShapes(aspect: aspect, size: size)
                }
            }
            .shimmering()
        }
        .scrollDisabled(true)
        .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
        .scrollClipDisabled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// The grey shapes of one card without any motion, so a row can share a single shimmer across them.
private struct SkeletonShapes: View {
    let aspect: CardAspect
    let size: CardSize

    var body: some View {
        let width = size.width(for: aspect)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            RoundedRectangle(cornerRadius: aspect.cornerRadius, style: .continuous)
                .fill(Theme.surfaceStrong)
                .frame(width: width, height: width / aspect.ratio)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.surfaceStrong)
                .frame(width: width * 0.8, height: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.surfaceStrong)
                .frame(width: width * 0.45, height: 8)
        }
    }
}

extension View {
    /// A slow highlight that sweeps across the view for loading placeholders. It sweeps a few times and then rests, so a
    /// placeholder never animates forever. Does nothing when Reduce Motion is on.
    func shimmering(_ active: Bool = true) -> some View {
        modifier(Shimmer(active: active))
    }
}

private struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion {
                GeometryReader { proxy in
                    let band: CGFloat = 140
                    LinearGradient(colors: [.clear, .white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: band)
                        // Starts just left of the view and ends just right of it, so the sweep enters and leaves cleanly.
                        .offset(x: -band + (proxy.size.width + band) * travel)
                }
                // The highlight only shows where the placeholder shapes are, never on the background around them.
                .mask(content)
                .allowsHitTesting(false)
                .onAppear {
                    travel = 0
                    withAnimation(.linear(duration: 1.6).repeatCount(3, autoreverses: false)) {
                        travel = 1
                    }
                }
            }
        }
    }
}
#endif
