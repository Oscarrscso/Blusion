#if canImport(UIKit)
import SwiftUI

/// A thin turning ring, lighter than the system's spoked spinner: for a small control that is waiting, such as Shuffle while its
/// episode's streams load. It takes the size it is given and the current foreground style, and turns once every 0.8 s.
struct ThinSpinner: View {
    var lineWidth: CGFloat = 1.75

    var body: some View {
        // Driven by the clock rather than a repeating animation, so it never drags the views around it into the animation.
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(turn * 360))
        }
        .accessibilityLabel("Loading")
    }
}
#endif
