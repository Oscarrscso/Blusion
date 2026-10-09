#if canImport(UIKit)
import SwiftUI
import StremioKit

/// A shelf header the way the TV app draws it: the title in bold 22 pt white and, when `onSeeAll` is set, a small grey chevron
/// right after the last word. The whole header is then the "See All" button. An optional grey subtitle sits under the title.
/// It has no horizontal padding of its own: the screen, or `MediaRow`, pads it to the page margin.
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
        if let onSeeAll {
            Button(action: onSeeAll) { header(withChevron: true) }
                .buttonStyle(ShelfHeaderButtonStyle())
                .accessibilityLabel(title)
                .accessibilityHint("See All")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("section.seeAll.\(title)")
        } else {
            header(withChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func header(withChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            titleText(withChevron: withChevron)
                .font(Theme.Typography.shelfTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The chevron is part of the text, so it stays glued to the last word when a long title wraps.
    private func titleText(withChevron: Bool) -> Text {
        guard withChevron else { return Text(title) }
        let chevron = Text(Image(systemName: "chevron.right"))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .baselineOffset(2)
        return Text("\(title) \(chevron)")
    }
}

/// Dims the header while it is pressed, like a system text button.
private struct ShelfHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A titled horizontal shelf of cards. The cards snap to the page margin and may bleed past the screen's edge, so the row never
/// looks cut off by the margin. Margins and gaps come from `LayoutMetrics`, so a shelf is right on a phone and in a Mac window.
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
    @Environment(\.layoutMetrics) private var metrics

    init(_ title: String, subtitle: String? = nil, hideTitle: Bool = false, onSeeAll: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.hideTitle = hideTitle
        self.onSeeAll = onSeeAll
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            if !hideTitle {
                SectionHeader(title, subtitle: subtitle, onSeeAll: onSeeAll)
                    .padding(.horizontal, metrics.pageMargin)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                    content()
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .environment(\.zoomScope, zoomScope)
    }
}

/// A grid of titles that fills the width: three posters across a phone, as many as fit in a Mac window. `onLastAppear` fires
/// when the last title scrolls in, so a caller can load the next page.
struct MediaGrid: View {
    let items: [MetaPreview]
    let aspect: CardAspect
    let showsRating: Bool
    let onLastAppear: (() -> Void)?
    @State private var zoomScope = UUID().uuidString
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape

    init(items: [MetaPreview], aspect: CardAspect = .poster, showsRating: Bool = true, onLastAppear: (() -> Void)? = nil) {
        self.items = items
        self.aspect = aspect
        self.showsRating = showsRating
        self.onLastAppear = onLastAppear
    }

    var body: some View {
        LazyVGrid(columns: metrics.gridColumns(for: aspect, inLandscape: isLandscape), alignment: .leading, spacing: metrics.gridRowSpacing) {
            ForEach(items, id: \.identity) { item in
                MediaCardLink(item: item, aspect: aspect, showsRating: showsRating)
                    .stretched()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                        if item.identity == items.last?.identity { onLastAppear?() }
                    }
            }
        }
        .padding(.horizontal, metrics.pageMargin)
        .environment(\.zoomScope, zoomScope)
    }
}
#endif
