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

/// The app's loading spinner everywhere: the thin ring, in place of the system's spoked one, always grey. It takes the system spinner's
/// room for the current control size, so a spot that showed one keeps its layout.
public struct Spinner: View {
    @Environment(\.controlSize) private var controlSize

    public init() {}

    /// The room the system spinner takes at this control size, the ring's diameter inside it, and the ring's line.
    private var metrics: (box: CGFloat, ring: CGFloat, line: CGFloat) {
        switch controlSize {
        case .mini: (12, 12, 1.5)
        case .small: (16, 16, 1.75)
        case .large, .extraLarge: (37, 30, 2.5)
        default: (20, 20, 2)
        }
    }

    public var body: some View {
        let metrics = self.metrics
        ThinSpinner(lineWidth: metrics.line)
            .frame(width: metrics.ring, height: metrics.ring)
            .frame(width: metrics.box, height: metrics.box)
            .foregroundStyle(.secondary)
    }
}
#endif
