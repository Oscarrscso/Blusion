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
}

extension View {
    /// A very light tap when the view is tapped, alongside whatever the view does on tap (a link, say), and without taking the tap.
    func titleTapHaptic() -> some View {
        simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }
}
#endif
