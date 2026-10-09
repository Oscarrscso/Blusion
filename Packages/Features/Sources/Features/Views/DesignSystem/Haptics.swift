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
}

extension View {
    /// A very light tap when the view is tapped, alongside whatever the view does on tap (a link, say), and without taking the tap.
    func titleTapHaptic() -> some View {
        simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }

    /// Let a swipe travel naturally, align to cards, and tick each time a card's leading edge passes the screen's leading edge,
    /// so the tick falls in the gap between two cards. Each card in the shelf must call `reportsShelfEdge(id:)`.
    func softSnappingScroll() -> some View {
        modifier(SoftSnappingScrollModifier())
    }

    /// Tell the enclosing `softSnappingScroll` where this card sits, so it can tick between cards.
    func reportsShelfEdge<ID: Hashable>(id: ID) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ShelfEdgeKey.self,
                                       value: [ShelfEdge(id: AnyHashable(id), minX: proxy.frame(in: .named(shelfScrollSpace)).minX)])
            }
        }
    }
}

/// The coordinate space of a shelf's viewport: a card's `minX` in it is where the card's leading edge sits on screen.
private let shelfScrollSpace = "softSnappingShelf"

private struct ShelfEdge: Equatable {
    let id: AnyHashable
    let minX: CGFloat
}

private struct ShelfEdgeKey: PreferenceKey {
    static var defaultValue: [ShelfEdge] { [] }

    static func reduce(value: inout [ShelfEdge], nextValue: () -> [ShelfEdge]) {
        value += nextValue()
    }
}

private struct SoftSnappingScrollModifier: ViewModifier {
    /// The card whose leading edge last reached the screen's leading edge. It changes exactly when a card crosses it.
    @State private var leadingID: AnyHashable?
    @State private var isUserScrolling = false

    func body(content: Content) -> some View {
        content
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .coordinateSpace(name: shelfScrollSpace)
            .onPreferenceChange(ShelfEdgeKey.self) { edges in
                let leading = edges.filter { $0.minX <= 0 }.max { $0.minX < $1.minX }?.id
                guard leading != leadingID else { return }
                leadingID = leading
                if isUserScrolling, leading != nil { Haptics.scrollSnap() }
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
