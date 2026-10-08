#if canImport(UIKit)
import SwiftUI
import StremioKit

/// A row or section title, an optional subtitle, and a trailing chevron that reads as "See All" to VoiceOver when `onSeeAll` is set.
/// It has no horizontal padding of its own: the screen, or `MediaRow`, pads it to `Theme.screenPadding`.
struct SectionHeader: View {
    let title: String
    let subtitle: String?
    let onSeeAll: (() -> Void)?

    init(_ title: String, subtitle: String? = nil, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            if let onSeeAll {
                Button(action: onSeeAll) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.Spacing.s)
                        .padding(.leading, Theme.Spacing.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See All")
                .accessibilityIdentifier("section.seeAll.\(title)")
            }
        }
    }
}

/// A titled horizontal scroller of cards. The cards snap to the screen's edge and may bleed past it, so the row never looks cut
/// off by the screen margin.
///
/// The row's height comes from its first card: a lazy stack in a horizontal scroll cannot measure the others before they scroll
/// in. Put the tallest card first, or give the cards of one row the same size and title setting.
struct MediaRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let hideTitle: Bool
    let onSeeAll: (() -> Void)?
    let content: () -> Content
    @State private var zoomScope = UUID().uuidString

    init(_ title: String, subtitle: String? = nil, hideTitle: Bool = false, onSeeAll: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.hideTitle = hideTitle
        self.onSeeAll = onSeeAll
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !hideTitle {
                SectionHeader(title, subtitle: subtitle, onSeeAll: onSeeAll)
                    .padding(.horizontal, Theme.screenPadding)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.cardSpacing) {
                    content()
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .environment(\.zoomScope, zoomScope)
    }
}

/// A grid of titles that fills the width, with as many columns as fit. `onLastAppear` fires when the last title scrolls in, so a
/// caller can load the next page.
struct MediaGrid: View {
    let items: [MetaPreview]
    let aspect: CardAspect
    let showsRating: Bool
    let onLastAppear: (() -> Void)?
    @State private var zoomScope = UUID().uuidString

    init(items: [MetaPreview], aspect: CardAspect = .poster, showsRating: Bool = false, onLastAppear: (() -> Void)? = nil) {
        self.items = items
        self.aspect = aspect
        self.showsRating = showsRating
        self.onLastAppear = onLastAppear
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: columns.minimum, maximum: columns.maximum), spacing: Theme.cardSpacing, alignment: .top)],
                  alignment: .leading, spacing: Theme.Spacing.l + Theme.Spacing.xs) {
            ForEach(items, id: \.identity) { item in
                MediaCardLink(item: item, aspect: aspect, showsRating: showsRating)
                    .stretched()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                        if item.identity == items.last?.identity { onLastAppear?() }
                    }
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .environment(\.zoomScope, zoomScope)
    }

    /// Column widths a grid of this aspect can use. Posters fit three across a phone; wide cards and squares fit two or three.
    private var columns: (minimum: CGFloat, maximum: CGFloat) {
        switch aspect {
        case .poster: (104, 170)
        case .wide: (150, 240)
        case .square: (96, 180)
        }
    }
}
#endif
