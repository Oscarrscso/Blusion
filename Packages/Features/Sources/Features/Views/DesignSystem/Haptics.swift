#if canImport(UIKit)
import SwiftUI
import UIKit

/// Haptics for the places a view cannot reach with `.sensoryFeedback`: a setter that runs when the user changes a value. Use
/// `.sensoryFeedback` where the trigger is a value the view already has. The system's haptic setting still applies to both.
@MainActor
enum Haptics {
    /// A tick for a choice changing: a toggle, a picker or a filter.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A very light tap for opening a title. Fired on a completed tap, so a scroll that starts on a poster stays silent.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }

    /// A distinct click when a user scrolls to a new card.
    static func scrollSnap() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
    }

    /// The gentler click of a shelf card's edge crossing (see `softSnappingScroll()`).
    static func scrollSnapSoft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
    }

    /// The most ticks one run of `lines` gives. More than this in the time a text takes to unfold runs together into a buzz.
    private static let maximumLineTicks = 12
    /// The run of ticks that is going, so a new one takes its place.
    private static var lineRun: Task<Void, Never>?

    /// A run of light ticks under text that is unfolding or folding: one for each line that comes into view or leaves it, spread over
    /// the time the text takes to move, the first at once. At least two, so a short text still reads as a run, and never more than
    /// `maximumLineTicks`. A new run stops one that is still going. Nothing for no lines.
    static func lines(_ count: Int, over duration: Duration) {
        lineRun?.cancel()
        guard count > 0 else { return }
        let ticks = min(max(count, 2), maximumLineTicks)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        lineRun = Task { @MainActor in
            let gap = duration / ticks
            for tick in 0..<ticks {
                generator.impactOccurred(intensity: 0.5)
                guard tick < ticks - 1 else { return }
                do { try await Task.sleep(for: gap) } catch { return }
            }
        }
    }
}

extension View {
    /// A very light tap when the view is tapped, alongside whatever the view does on tap (a link, say), and without taking the tap.
    func titleTapHaptic() -> some View {
        simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }

    /// Let a swipe travel naturally, align to cards, and tick each time a card's leading edge passes the screen's leading edge,
    /// so the tick falls in the gap between two cards. Each card in the shelf must call `reportsShelfEdge(id:)`. Every horizontal
    /// shelf uses this one feel: the actor shelf's.
    func softSnappingScroll() -> some View {
        modifier(SoftSnappingScrollModifier())
    }

    /// Tell the enclosing `softSnappingScroll` where this card sits, so it can tick between cards.
    func reportsShelfEdge<ID: Hashable>(id: ID) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ShelfEdgeKey.self,
                                       value: [ShelfEdge(id: AnyHashable(id), minX: proxy.frame(in: .named(shelfScrollSpace)).minX,
                                                           height: proxy.size.height)])
            }
        }
    }
}

/// The one horizontal card shelf: a row of cards that snaps to the page margin, bleeds past the screen's edge, and ticks as cards cross the
/// leading edge. Every card shelf is built with this, so they all scroll and tick alike. Each card must call `reportsShelfEdge(id:)` and have
/// a stable `id`.
///
/// By default the row is lazy, which builds only the cards near the screen. A lazy stack cannot size itself from the cards it has not built,
/// and a card that changes height (an opened review) or is taller than the first would spill over the section below. So every card reports
/// its height and the shelf takes the tallest of those built so far. That height only grows, since the tallest card may not be built yet. When
/// `resetKey` changes (a different season, a different card width) the height starts again from the cards then built.
///
/// `lazy: false` is for a short shelf whose cards all exist already. A plain row is exactly as tall as its tallest card, so the shelf changes
/// height with that card's own animation, and no height is measured.
struct ShelfScroll<Content: View>: View {
    let margin: CGFloat
    let spacing: CGFloat
    let lazy: Bool
    let resetKey: String
    let content: Content
    @State private var height: CGFloat?
    @State private var measuredKey: String?

    init(margin: CGFloat, spacing: CGFloat, lazy: Bool = true, resetKey: String = "", @ViewBuilder content: () -> Content) {
        self.margin = margin
        self.spacing = spacing
        self.lazy = lazy
        self.resetKey = resetKey
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal) {
            if lazy {
                LazyHStack(alignment: .top, spacing: spacing) { content }
                    .scrollTargetLayout()
            } else {
                HStack(alignment: .top, spacing: spacing) { content }
                    .scrollTargetLayout()
            }
        }
        .shelfIndicators()
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .softSnappingScroll()
        .scrollClipDisabled()
        .frame(height: height)
        .onPreferenceChange(ShelfEdgeKey.self) { edges in
            // A plain row sizes itself, so there is nothing to measure.
            guard lazy else { return }
            let tallest = edges.map(\.height).max() ?? 0
            guard tallest > 0 else { return }
            let previous = measuredKey == resetKey ? height : nil
            let next = max(previous ?? 0, tallest)
            if measuredKey != resetKey { measuredKey = resetKey }
            if abs(next - (height ?? -1)) > 0.5 { height = next }
        }
    }
}

/// The coordinate space of a shelf's viewport: a card's `minX` in it is where the card's leading edge sits on screen.
private let shelfScrollSpace = "softSnappingShelf"

private struct ShelfEdge: Equatable {
    let id: AnyHashable
    let minX: CGFloat
    let height: CGFloat
}

private struct ShelfEdgeKey: PreferenceKey {
    static var defaultValue: [ShelfEdge] { [] }

    static func reduce(value: inout [ShelfEdge], nextValue: () -> [ShelfEdge]) {
        value += nextValue()
    }
}

private struct SoftSnappingScrollModifier: ViewModifier {
    /// How far the shelf must travel from the last tick before another card crossing ticks. Only enough to keep a card resting on the
    /// edge from chattering: a swipe that goes back over the gap it just crossed ticks again, in either direction.
    private static let minimumTravel: CGFloat = 12

    /// The card whose leading edge last reached the screen's leading edge. It changes exactly when a card crosses it.
    @State private var leadingID: AnyHashable?
    @State private var isUserScrolling = false
    @State private var offset: CGFloat = 0
    @State private var offsetAtLastTick: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .coordinateSpace(name: shelfScrollSpace)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, new in offset = new }
            .onPreferenceChange(ShelfEdgeKey.self) { edges in
                let leading = edges.filter { $0.minX <= 0 }.max { $0.minX < $1.minX }?.id
                guard leading != leadingID else { return }
                leadingID = leading
                guard isUserScrolling, leading != nil, abs(offset - offsetAtLastTick) >= Self.minimumTravel else { return }
                offsetAtLastTick = offset
                Haptics.scrollSnapSoft()
            }
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .decelerating:
                    isUserScrolling = true
                default:
                    isUserScrolling = false
                }
            }
            .onDisappear { isUserScrolling = false }
    }
}

#endif
