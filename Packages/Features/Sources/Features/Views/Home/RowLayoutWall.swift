#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

// MARK: - Wall

/// `RowLayout.wall`: a tilted wall of small posters, three rows tall, in rows that drift past in opposite directions at different speeds,
/// in a rounded panel with a soft vignette. Each poster opens its title, and each row can be dragged along by itself; a flick glides on and
/// slows to a stop as a scrolled list does, a row caught while it glides stops under the finger, and the row drifts again from wherever it
/// is let go. The wall stands still with Reduce Motion, while its row is off screen or the app is in the background,
/// while a row is held and, on the Mac, while the pointer is over it, so a poster can be clicked.
struct WallLayout: View {
    let items: [MetaPreview]
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.heroContainerWidth) private var containerWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadsVisibleArtwork) private var sectionIsVisible
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = DriftClock()
    @State private var stripCache = WallStripCache()
    @State private var isHovering = false
    /// How far each row has been moved by hand, by its id, on top of its drift.
    @State private var shifts: [Int: CGFloat] = [:]
    /// Each flicked row's glide, by its id, worked out from the wall's own time.
    @State private var glides: [Int: WallGlide] = [:]
    /// The row being dragged, and how far along it the finger has gone.
    @State private var drag: (row: Int, distance: CGFloat)?

    static let tilt: Double = -8
    static func posterWidth(_ metrics: LayoutMetrics) -> CGFloat { (metrics.posterWidth * 0.5).rounded() }
    static func gap(_ metrics: LayoutMetrics) -> CGFloat { max(4, (metrics.cardSpacing * 0.67).rounded()) }
    static func height(_ metrics: LayoutMetrics) -> CGFloat { (posterWidth(metrics) * 1.5 * 3).rounded() }

    var body: some View {
        let width = Self.posterWidth(metrics)
        let posterHeight = width * 1.5
        let gap = Self.gap(metrics)
        let panelHeight = Self.height(metrics)
        let panelWidth = max(1, containerWidth - metrics.pageMargin * 2)
        let angle = CGFloat(abs(Self.tilt) * .pi / 180)
        // Enough rows, and enough wall past each side, that the tilted wall still covers the panel's corners.
        let needed: CGFloat = (panelHeight * cos(angle) + panelWidth * sin(angle)) / (posterHeight + gap)
        let rows = max(3, Int(needed.rounded(.up)) + 1)
        let overhang: CGFloat = (panelHeight * sin(angle)).rounded(.up) + width
        let strips = stripCache.strips(for: items, rows: rows, width: width, gap: gap, span: panelWidth + overhang * 2)
        // On the Mac the wall stops drifting under the pointer, but a row flicked there still glides to a stop.
        let gliding = glides.values.contains { $0.isMoving(at: clock.glideTime) }
        let paused = reduceMotion || !sectionIsVisible || scenePhase != .active || (isHovering && !gliding) || drag != nil
        let radius = HeroBanner.cornerRadius * metrics.cornerScale(for: .artwork)
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { context in
            let time = clock.advance(to: context.date, running: !paused, drifting: !isHovering)
            let glideTime = clock.glideTime
            VStack(alignment: .leading, spacing: gap) {
                ForEach(strips) { strip in
                    WallStripView(strip: strip, width: width, height: posterHeight, gap: gap)
                        .equatable()
                        .offset(x: strip.offset(at: time, shift: shift(of: strip.id, at: glideTime)) - overhang)
                        .gesture(WallRowPan { distance in
                            hold(strip.id, distance: distance)
                        } ended: { distance, velocity in
                            release(strip.id, distance: distance, velocity: velocity)
                        })
                }
            }
            .frame(width: panelWidth, alignment: .leading)
        }
        .rotationEffect(.degrees(Self.tilt))
        .frame(width: panelWidth, height: panelHeight)
        .overlay {
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: panelHeight * 0.3,
                           endRadius: max(panelWidth, panelHeight) * 0.75)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // The rows run past the panel; only what shows inside it takes touches.
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.artworkBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, metrics.pageMargin)
        #if targetEnvironment(macCatalyst)
        .onHover { isHovering = $0 }
        #endif
    }

    /// How far `row` has been moved by hand at `time`: the drags before, the one under way and the glide of the last flick.
    private func shift(of row: Int, at time: TimeInterval) -> CGFloat {
        let held = drag?.row == row ? drag?.distance ?? 0 : 0
        return shifts[row, default: 0] + held + (glides[row]?.distance(at: time) ?? 0)
    }

    /// The finger on `row`. A row still gliding stops where it stands, so it stays under the finger instead of jumping to where its glide
    /// would have ended.
    private func hold(_ row: Int, distance: CGFloat) {
        if drag?.row != row, let glide = glides.removeValue(forKey: row) {
            shifts[row, default: 0] += glide.distance(at: clock.glideTime)
        }
        drag = (row, distance)
    }

    /// Leaves `row` where the finger let go. A flick carries it on and slows to a stop, as a scrolled list does; with Reduce Motion it stays put.
    private func release(_ row: Int, distance: CGFloat, velocity: CGFloat) {
        shifts[row, default: 0] += distance
        if !reduceMotion, abs(velocity) > 20 {
            glides[row] = WallGlide(velocity: min(max(velocity, -4000), 4000), start: clock.glideTime)
        }
        drag = nil
    }
}

/// A flicked row of the wall gliding on and slowing to a stop as a scrolled list does. It is worked out from the wall's own time rather
/// than animated, so where the row stands is known at every moment and a finger can catch it there.
private struct WallGlide {
    let velocity: CGFloat
    let start: TimeInterval

    /// UIScrollView's normal deceleration as a time constant: the speed falls by a factor of e every half second.
    static let decay: TimeInterval = 0.5

    /// How far the row has glided by `time`.
    func distance(at time: TimeInterval) -> CGFloat {
        let elapsed = max(0, time - start)
        return velocity * CGFloat(Self.decay * (1 - exp(-elapsed / Self.decay)))
    }

    /// Whether the row is still visibly moving at `time`.
    func isMoving(at time: TimeInterval) -> Bool {
        abs(velocity) * CGFloat(exp(-max(0, time - start) / Self.decay)) > 4
    }
}

/// A sideways drag on one of the wall's rows (or the Deck's top card): `moved` with how far the finger has gone along it, `ended` with that
/// distance and its speed in points a second. It starts only when the finger moves more sideways than up or down, and the page's scroll waits for it to give up,
/// so a vertical swipe over the wall still scrolls the page. A drag that starts on a poster does not open it. On the Mac a two-finger
/// trackpad swipe moves the row too.
struct WallRowPan: UIGestureRecognizerRepresentable {
    let moved: (CGFloat) -> Void
    let ended: (_ distance: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        #if targetEnvironment(macCatalyst)
        recognizer.allowedScrollTypesMask = .continuous
        #endif
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {}

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let distance = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began:
            // Measured from where the drag is recognised, not where the finger came down, so the row does not jump by the distance the
            // finger moved before it counted as a drag.
            recognizer.setTranslation(.zero, in: recognizer.view)
            moved(0)
        case .changed: moved(distance)
        case .ended: ended(distance, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: ended(distance, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// The wall's own time. It runs only while the wall moves, so after a pause the wall carries on from where it stood rather than jumping.
/// The rows' drift and their glides keep separate times, so a row can glide while the wall's drift stands still under the Mac's pointer.
@MainActor
private final class DriftClock {
    private var elapsed: TimeInterval = 0
    private var last: Date?
    /// The time the rows' glides were last drawn at.
    private(set) var glideTime: TimeInterval = 0

    /// The drift's time at `date`. `running` false keeps both times where they are, for a wall drawn again while it stands still (a row
    /// held); `drifting` false keeps only the drift's.
    func advance(to date: Date, running: Bool = true, drifting: Bool = true) -> TimeInterval {
        if running, let last {
            // The first frame after a pause moves the wall no further than a frame would.
            let step = min(max(date.timeIntervalSince(last), 0), 1.0 / 30)
            glideTime += step
            if drifting { elapsed += step }
        }
        last = date
        return elapsed
    }
}

/// The wall's rows, built again only when its titles or its size change: a drag or a flick redraws the wall on every move, and its rows
/// stay the same through it.
@MainActor
private final class WallStripCache {
    private var items: [MetaPreview] = []
    private var size: [CGFloat] = []
    private var strips: [WallStrip] = []

    func strips(for items: [MetaPreview], rows: Int, width: CGFloat, gap: CGFloat, span: CGFloat) -> [WallStrip] {
        let size = [CGFloat(rows), width, gap, span]
        if size != self.size || items != self.items {
            self.items = items
            self.size = size
            strips = WallStrip.strips(for: items, rows: rows, width: width, gap: gap, span: span)
        }
        return strips
    }
}

/// One row of the wall: its titles, repeated until the row is longer than the panel by a whole lap, so it loops without a seam.
private struct WallStrip: Identifiable {
    struct Entry: Identifiable {
        let id: String
        let item: MetaPreview
        /// The repeat of the title that VoiceOver reads; the others are hidden from it.
        let isOriginal: Bool
        /// Tells this repeat's zoom source apart from the others.
        let copy: String
    }

    let id: Int
    let entries: [Entry]
    /// Identifies the entries, so a frame of the wall can tell that the row itself has not changed.
    let key: String
    /// The width of one lap: the row's own titles, each with its gap.
    let lap: CGFloat
    /// Points a second; leftwards when negative.
    let speed: CGFloat

    /// How far the row has drifted at `time`, plus `shift` moved by hand, within one lap, so it always covers the panel.
    func offset(at time: TimeInterval, shift: CGFloat = 0) -> CGFloat {
        guard lap > 0 else { return 0 }
        let travelled = (CGFloat(time) * speed + shift).truncatingRemainder(dividingBy: lap)
        return (travelled < 0 ? travelled + lap : travelled) - lap
    }

    /// `rows` rows covering `span` points each. With enough titles each row takes its own share in turn; with fewer, each row takes just
    /// as many as it needs to cross the panel without a title showing twice, starting at its own place in the shelf, and with fewer still
    /// every row shows them all. A row never carries more posters than it needs, as every one of them moves on every frame.
    static func strips(for items: [MetaPreview], rows: Int, width: CGFloat, gap: CGFloat, span: CGFloat) -> [WallStrip] {
        guard !items.isEmpty else { return [] }
        let speeds: [CGFloat] = [-14, 11, -17, 9, -12, 15]
        // Each row takes its own share only when that share is long enough to cross the panel without a title showing twice in the row.
        let shared = CGFloat(items.count / rows) * (width + gap) >= span
        let crossing = min(items.count, Int((span / (width + gap)).rounded(.up)))
        // VoiceOver reads each title once, where it first appears.
        var read = Set<String>()
        return (0..<rows).map { row in
            let own: [MetaPreview]
            if shared {
                own = stride(from: row, to: items.count, by: rows).map { items[$0] }
            } else {
                let start = row * items.count / rows
                own = (0..<crossing).map { items[(start + $0) % items.count] }
            }
            let lap = CGFloat(own.count) * (width + gap)
            let laps = Int((span / lap).rounded(.up)) + 1
            var entries: [Entry] = []
            for copy in 0..<laps {
                for item in own {
                    let isOriginal = copy == 0 && read.insert(item.identity).inserted
                    entries.append(Entry(id: "\(copy)/\(item.identity)", item: item, isOriginal: isOriginal, copy: "\(row).\(copy)/"))
                }
            }
            return WallStrip(id: row, entries: entries, key: entries.map(\.id).joined(separator: "|"), lap: lap,
                             speed: speeds[row % speeds.count])
        }
    }
}

/// A row of the wall's posters. Equatable, so the wall's frames move the row without rebuilding its posters.
private struct WallStripView: View, Equatable {
    let strip: WallStrip
    let width: CGFloat
    let height: CGFloat
    let gap: CGFloat

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.strip.id == rhs.strip.id && lhs.strip.key == rhs.strip.key && lhs.width == rhs.width && lhs.height == rhs.height
                && lhs.gap == rhs.gap
        }
    }

    var body: some View {
        HStack(spacing: gap) {
            ForEach(strip.entries) { entry in
                LayoutTitleLink(item: entry.item, copy: entry.copy, prewarms: false, cornerRadius: Theme.Radius.small * 0.8) {
                    LayoutPoster(item: entry.item, width: width, height: height)
                }
                .accessibilityHidden(!entry.isOriginal)
            }
        }
        .fixedSize()
    }
}
#endif
