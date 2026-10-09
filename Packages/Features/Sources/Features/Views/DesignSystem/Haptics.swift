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

    /// Let a swipe travel naturally, align to cards, and tick as the leading card changes.
    func softSnappingScroll<ID: Hashable>(idType: ID.Type) -> some View {
        modifier(SoftSnappingScrollModifier<ID>())
    }
}

private struct SoftSnappingScrollModifier<ID: Hashable>: ViewModifier {
    @State private var scrolledID: ID?
    @State private var isUserScrolling = false

    func body(content: Content) -> some View {
        content
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $scrolledID, anchor: .leading)
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .decelerating:
                    isUserScrolling = true
                default:
                    isUserScrolling = false
                }
            }
            .onChange(of: scrolledID) { _, newID in
                if isUserScrolling, newID != nil { Haptics.scrollSnap() }
            }
            .onDisappear { isUserScrolling = false }
    }
}

#endif
