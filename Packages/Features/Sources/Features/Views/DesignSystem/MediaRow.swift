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
            Button(action: onSeeAll) { SectionHeaderLabel(title: title, subtitle: subtitle, withChevron: true) }
                .buttonStyle(ShelfHeaderButtonStyle())
                .seeAllAccessibility(title)
        } else {
            SectionHeaderLabel(title: title, subtitle: subtitle, withChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The drawing of a shelf header: the title, then an optional grey subtitle. `SectionHeader` draws through it with or without its chevron.
private struct SectionHeaderLabel: View {
    let title: String
    let subtitle: String?
    let withChevron: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleText
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
    private var titleText: Text {
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

private extension View {
    /// The "See All" reading and identifier of a header that opens a screen.
    func seeAllAccessibility(_ title: String) -> some View {
        accessibilityLabel(title)
            .accessibilityHint("See All")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("section.seeAll.\(title)")
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
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                    ForEach(subviews: content()) { card in
                        card.id(card.id).reportsShelfEdge(id: card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .shelfIndicators()
            .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
            .softSnappingScroll()
            .scrollClipDisabled()
        }
        .environment(\.zoomScope, zoomScope)
    }
}

/// A grid of titles that fills the width: three posters across a phone, as many as fit in a Mac window. Whatever the layout, it keeps the
/// posters of the "Lazy load" buffer (see `LazyLoadLookahead`) above and below the visible titles loaded, so they are in memory before
/// they scroll on screen, and unloads them from memory once they are further away. `onLastAppear` makes it paged: it fires while the
/// viewer is within the buffer of the end, so a caller can load the next page. A paged grid also draws a blank card of the same size for
/// titles outside the buffer. What is visible comes from the grid's own geometry against its scroll view, not from its cells.
/// `usesBetterPosters` makes the posters of a poster grid take their pictures from the BetterPosters addon (see `MediaCard`).
struct MediaGrid: View {
    let items: [MetaPreview]
    let aspect: CardAspect
    let showsRating: Bool
    let onLastAppear: (() -> Void)?
    let usesBetterPosters: Bool
    @State private var zoomScope = UUID().uuidString
    /// The titles whose rows are on screen; nil before the first reading.
    @State private var visible: ClosedRange<Int>?
    @State private var prefetcher = ArtworkPrefetcher()
    /// The chosen level; reading it here makes the grid follow the slider while it is alive.
    @AppStorage(LazyLoadLookahead.defaultsKey) private var lookaheadLevel = LazyLoadLookahead.defaultLevel
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isLandscape) private var isLandscape
    @Environment(\.displayScale) private var displayScale

    init(items: [MetaPreview], aspect: CardAspect = .poster, showsRating: Bool = true, onLastAppear: (() -> Void)? = nil,
         usesBetterPosters: Bool = false) {
        self.items = items
        self.aspect = aspect
        self.showsRating = showsRating
        self.onLastAppear = onLastAppear
        self.usesBetterPosters = usesBetterPosters
    }

    /// Titles kept ready on each side of the visible ones.
    private var buffer: Int { LazyLoadLookahead.titles(atLevel: lookaheadLevel) }

    /// The indices that stay loaded: the visible ones and `buffer` titles each way. Nil before the first reading.
    private var bufferRange: ClosedRange<Int>? {
        visible.flatMap { LazyLoadLookahead.bufferRange(visible: $0, count: items.count, titles: buffer) }
    }

    var body: some View {
        // Only a paged grid blanks cards; before the first reading nothing is blanked.
        let kept = onLastAppear == nil ? nil : bufferRange
        // A poster in landscape is drawn as a wide card without a caption (see `MediaCard`), so its blank card has that shape.
        let landscapePoster = isLandscape && aspect == .poster
        let columns = metrics.gridColumns(for: aspect, inLandscape: isLandscape)
        let spacing = metrics.cardSpacing
        let count = items.count
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                Group {
                    if let kept, !kept.contains(index) {
                        UnloadedCard(artwork: landscapePoster ? .wide : aspect, showsCaption: aspect.showsCaptionByDefault)
                    } else {
                        MediaCardLink(item: item, aspect: aspect, showsRating: showsRating, usesBetterPosters: usesBetterPosters)
                            .stretched()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The reading is the range of titles whose rows meet the scroll view's viewport. It changes only when a row enters or leaves.
        .onGeometryChange(for: ClosedRange<Int>?.self) { proxy in
            guard let viewport = proxy.bounds(of: .scrollView) else { return count > 0 ? 0...(count - 1) : nil }
            return LazyLoadLookahead.visibleItems(
                viewportMinY: viewport.minY, viewportMaxY: viewport.maxY, gridHeight: proxy.size.height, rowSpacing: spacing,
                columns: Self.columnCount(of: columns, width: proxy.size.width, spacing: spacing), count: count)
        } action: { visible = $0 }
        .padding(.horizontal, metrics.pageMargin)
        .environment(\.zoomScope, zoomScope)
        .onChange(of: visible) { loadNextPageIfNear() }
        .onChange(of: items.count) { loadNextPageIfNear() }
        .onChange(of: bufferRange) { refreshPrefetch() }
        .onChange(of: items.count) { refreshPrefetch() }
        .onChange(of: items.first?.identity) { refreshPrefetch() }
        .onChange(of: lookaheadLevel) { refreshPrefetch() }
        .onChange(of: isLandscape) { refreshPrefetch() }
        .onChange(of: metrics.isRegular) { refreshPrefetch() }
        .onDisappear { prefetcher.cancelAll() }
    }

    /// How many columns SwiftUI lays `columns` out in at `width`: one per fixed or flexible item, and for an adaptive item as many
    /// minimum-width columns (plus spacing) as fit, at least one.
    private static func columnCount(of columns: [GridItem], width: CGFloat, spacing: CGFloat) -> Int {
        columns.reduce(0) { total, column in
            switch column.size {
            case .adaptive(let minimum, _): total + max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
            default: total + 1
            }
        }
    }

    /// Asks for the next page while the viewer is within the buffer of the end.
    private func loadNextPageIfNear() {
        guard let onLastAppear, let visible else { return }
        if visible.upperBound >= LazyLoadLookahead.triggerIndex(count: items.count, titles: buffer) { onLastAppear() }
    }

    private func requests(_ range: ClosedRange<Int>, skipping skipped: ClosedRange<Int>? = nil) -> [ArtworkPrefetcher.Request] {
        range.filter { !(skipped?.contains($0) ?? false) && items.indices.contains($0) }.flatMap {
            MediaCard.artworkRequests(for: items[$0], aspect: aspect, metrics: metrics, isLandscape: isLandscape, displayScale: displayScale,
                                      usesBetterPosters: usesBetterPosters)
        }
    }

    /// Tells the prefetcher to load the posters of the buffer's titles that are not on screen themselves (those load as cards).
    private func refreshPrefetch() {
        guard let visible, let range = bufferRange else { return }
        prefetcher.update(wanted: requests(range, skipping: visible), visible: requests(visible))
    }
}

/// The stand-in for a title whose artwork has been released: a blank box of its card's shape, with the two caption lines when the card
/// has them, so the grid keeps the same row heights and its scroll position.
private struct UnloadedCard: View {
    let artwork: CardAspect
    let showsCaption: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            RoundedRectangle(cornerRadius: artwork.cornerRadius, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(artwork.ratio, contentMode: .fit)
            if showsCaption {
                VStack(alignment: .leading, spacing: 2) {
                    Text(" ").font(Theme.Typography.cardTitle).lineLimit(1)
                    Text(" ").font(Theme.Typography.cardSubtitle).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
