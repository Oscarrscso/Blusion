#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

// MARK: - Flow

/// `RowLayout.flow`: iPod: Cover Flow. The poster in the middle faces the viewer; the others stand turned towards it in two tight stacks, each
/// overlapping the next like records in a crate, every poster over its own reflection, with the middle one's name and details under them.
/// A poster to one side comes to the middle when tapped; the one in the middle opens its title.
struct FlowLayoutRow: View {
    let items: [MetaPreview]
    let showsRating: Bool
    @State private var centredID: String?
    @State private var entryCache = EntryCache()
    @State private var motion = ScrollMotion()
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.heroContainerWidth) private var containerWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if targetEnvironment(macCatalyst)
    @State private var isHovering = false
    #endif

    /// Starts on the first title in the middle copy, so the last titles already stand in the stack to its left.
    init(items: [MetaPreview], showsRating: Bool) {
        self.items = items
        self.showsRating = showsRating
        _centredID = State(initialValue: items.first.map { Self.entryID(copy: Self.middleCopy(of: items.count), item: $0) })
    }

    /// The shelf repeated end to end so the row loops: the user scrolls through the copies, and each time the row comes to rest it is
    /// silently put back on the same poster in the middle copy. Each side of the middle copy holds at least `runway` posters, so even a
    /// run of hard flicks never reaches an end, however short the shelf. A single title is not repeated.
    private static let runway = 400
    private static func copies(of count: Int) -> Int { count > 1 ? 2 * ((runway + count - 1) / count) + 1 : 1 }
    private static func middleCopy(of count: Int) -> Int { copies(of: count) / 2 }
    private static func entryID(copy: Int, item: MetaPreview) -> String { "\(copy)/\(item.identity)" }
    private struct Entry: Identifiable {
        let id: String
        let item: MetaPreview
        let copy: Int
        let index: Int
    }
    private var entries: [Entry] { entryCache.entries(for: items, copies: Self.copies(of: items.count)) }
    /// Where the poster with `id` stands among all the copies.
    private func position(of id: String?) -> Int? {
        id.flatMap { entryCache.position(of: $0, for: items, copies: Self.copies(of: items.count)) }
    }

    /// The copies' entries and where each stands, built again only when the titles change: the row redraws, and asks where the middle
    /// poster stands, each time another poster comes to the middle.
    @MainActor
    private final class EntryCache {
        private var items: [MetaPreview]?
        private var entries: [Entry] = []
        private var positions: [String: Int] = [:]

        func entries(for items: [MetaPreview], copies: Int) -> [Entry] {
            guard items != self.items else { return entries }
            self.items = items
            entries = (0..<copies).flatMap { copy in
                items.enumerated().map { Entry(id: FlowLayoutRow.entryID(copy: copy, item: $1), item: $1, copy: copy, index: $0) }
            }
            positions = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            return entries
        }

        func position(of id: String, for items: [MetaPreview], copies: Int) -> Int? {
            _ = entries(for: items, copies: copies)
            return positions[id]
        }
    }
    private var middleCopy: Int { Self.middleCopy(of: items.count) }

    /// Whether the row is held or still moving, kept out of the view's state so a change of phase does not redraw the row.
    @MainActor
    private final class ScrollMotion {
        var isMoving = false
    }

    static func cardWidth(_ metrics: LayoutMetrics) -> CGFloat { (metrics.posterWidth * 1.2).rounded() }
    static func reflection(_ metrics: LayoutMetrics) -> CGFloat { (cardWidth(metrics) * 1.5 * 0.12).rounded() }
    /// The posters over their reflections, above the caption.
    static func height(_ metrics: LayoutMetrics) -> CGFloat {
        cardWidth(metrics) * 1.5 + FlowCard.reflectionGap + reflection(metrics)
    }

    private var current: String? { centredID ?? entries.first { $0.copy == middleCopy }?.id }
    /// The position of the middle poster among all the copies.
    private var currentPosition: Int { position(of: current) ?? 0 }
    /// The middle poster's place in the shelf.
    private var currentIndex: Int { entries.indices.contains(currentPosition) ? entries[currentPosition].index : 0 }

    var body: some View {
        let width = Self.cardWidth(metrics)
        let height = width * 1.5
        let reflection = Self.reflection(metrics)
        // Each poster takes only `step` of the scroll, the gap between two posters in a side stack, so a drag moves the stacks with the
        // finger. The first poster to each side stands `spread` from the middle, clear of the one facing the viewer.
        let step = (width * 0.2).rounded()
        let spread = width * 0.66
        // Turns and scales about the poster's own middle, not its reflection's.
        let anchor = UnitPoint(x: 0.5, y: height / 2 / (height + FlowCard.reflectionGap + reflection))
        // Worked out once for the whole row, not again for each poster.
        let current = self.current
        let currentPosition = self.currentPosition
        let reduceMotion = self.reduceMotion
        let count = items.count
        VStack(spacing: Theme.Spacing.s) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(entries) { entry in
                        let position = entry.copy * count + entry.index
                        FlowCard(item: entry.item, width: width, height: height, reflection: reflection,
                                 isCentred: entry.id == current, showsRating: showsRating) {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.38)) { centredID = entry.id }
                        }
                        // Another poster coming to the middle redraws only it and the one that leaves.
                        .equatable()
                        .visualEffect { content, proxy in
                            // How many steps the poster is from the middle, leftwards when negative; past one step it is in a stack.
                            let distance = proxy.bounds(of: .scrollView).map { proxy.size.width / 2 - $0.midX } ?? 0
                            let side = min(max(distance / step, -1), 1)
                            // Ease both ends of the turn so a cover joins and leaves its stack without a sudden change in speed.
                            let progress = abs(side)
                            let turn = side * progress * (3 - 2 * progress)
                            return content
                                .rotation3DEffect(.degrees(reduceMotion ? 0 : -Double(turn) * 68), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.35)
                                .scaleEffect(1 - abs(turn) * 0.16, anchor: anchor)
                                .offset(x: turn * (spread - step))
                                .brightness(-Double(abs(turn)) * 0.12)
                        }
                        .frame(width: step)
                        // The poster in the middle is drawn over its neighbours, and each one in a stack over the one behind it.
                        .zIndex(-Double(abs(position - currentPosition)))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $centredID, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .onScrollPhaseChange { _, phase in
                motion.isMoving = phase != .idle
                // Put back the moment the row is at rest, before a finger can take it again.
                if phase == .idle { recentre() }
            }
            .scrollIndicators(.hidden, axes: .horizontal)
            .contentMargins(.horizontal, max(metrics.pageMargin, (containerWidth - step) / 2), for: .scrollContent)
            .scrollClipDisabled()
            .frame(height: height + FlowCard.reflectionGap + reflection)
            #if targetEnvironment(macCatalyst)
            .overlay {
                if isHovering && items.count > 1 { arrows.frame(height: height).frame(maxHeight: .infinity, alignment: .top) }
            }
            #endif
            caption
        }
        .onChange(of: centredID) { old, new in
            guard old != nil, new != old else { return }
            let shelfIndex = { (id: String?) in position(of: id).map { entries[$0].index } }
            if shelfIndex(old) != shelfIndex(new) { Haptics.play(.shelves) }
            // A tap or a chevron moves the row without a gesture: it is put back once that move has had time to finish.
            if !motion.isMoving { recentre(after: .milliseconds(600)) }
        }
        // `init` seeds the middle poster only the first time the row is made, often before its titles have loaded: without this the
        // scroll view rests on a poster other than the one marked as in the middle, and its first tap only brings it to the middle.
        .onChange(of: items, initial: true) {
            guard position(of: centredID) == nil, let first = items.first else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { centredID = Self.entryID(copy: middleCopy, item: first) }
        }
        #if targetEnvironment(macCatalyst)
        .onHover { isHovering = $0 }
        #endif
    }

    /// When the row rests on a poster in another copy, puts it back on the same poster in the middle copy, without animation: every
    /// poster stands just where it was, so nothing on screen moves. Never while the row is held or still moving.
    private func recentre(after delay: Duration = .zero) {
        guard let id = centredID, let entry = position(of: id).map({ entries[$0] }), entry.copy != middleCopy else { return }
        let target = Self.entryID(copy: middleCopy, item: entry.item)
        Task { @MainActor in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !motion.isMoving, centredID == id, position(of: target) != nil else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { centredID = target }
        }
    }

    /// Keep the selected title's information in a steady space while the covers move above it.
    private var caption: some View {
        let item = items.indices.contains(currentIndex) ? items[currentIndex] : nil
        let details = item.map {
            [layoutDetailLine($0, showsRating: showsRating), $0.runtime ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? " "
        return Self.captionLines(name: item?.name ?? " ", details: details,
                                 synopsis: item?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.pageMargin)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: item?.identity)
            .accessibilityElement(children: .combine)
            .accessibilityValue(items.isEmpty ? "" : "\(currentIndex + 1) of \(items.count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 1)
                case .decrement: move(by: -1)
                @unknown default: break
                }
            }
    }

    /// The title and tagline share a row; the synopsis uses the full width beneath them.
    static func captionLines(name: String, details: String, synopsis: String = "") -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Text(name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .layoutPriority(1)
                Text(details)
                    .font(Theme.Typography.metaLine)
                    .foregroundStyle(Theme.metaText)
                    .lineLimit(1, reservesSpace: true)
            }
            Text(synopsis)
                .font(Theme.Typography.medium)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
    }

    private func move(by step: Int) {
        guard items.count > 1 else { return }
        let target = min(max(currentPosition + step, 0), entries.count - 1)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.38)) { centredID = entries[target].id }
    }

    #if targetEnvironment(macCatalyst)
    /// Mac: a chevron at each side while the pointer is over the row, moving the next poster to the middle.
    private var arrows: some View {
        HStack {
            arrow(systemName: "chevron.left", label: "Previous title", step: -1, enabled: items.count > 1)
            Spacer()
            arrow(systemName: "chevron.right", label: "Next title", step: 1, enabled: items.count > 1)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func arrow(systemName: String, label: String, step: Int, enabled: Bool) -> some View {
        Button {
            move(by: step)
        } label: {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: 40, height: 40)
                .buttonSurface(.regular, in: ScaledCapsule(scale: metrics.circularButtonScale(for: .actionButtons)))
                .contentShape(ScaledCapsule(scale: metrics.circularButtonScale(for: .actionButtons)))
        }
        .buttonStyle(.hoverPlain)
        .disabled(!enabled)
        // A hidden chevron must not take clicks meant for the posters beneath it.
        .allowsHitTesting(enabled)
        .opacity(enabled ? 1 : 0)
        .accessibilityLabel(label)
    }
    #endif
}

private struct FlowCard: View, Equatable {
    let item: MetaPreview
    let width: CGFloat
    let height: CGFloat
    let reflection: CGFloat
    let isCentred: Bool
    let showsRating: Bool
    let onCentre: () -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.zoomScope) private var zoomScope
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.loadsVisibleArtwork) private var sectionIsVisible
    /// Optional, as the rating badges read it: a screen without the store simply does not prewarm.
    @Environment(PosterRatingsStore.self) private var ratings: PosterRatingsStore?
    #if targetEnvironment(macCatalyst)
    @State private var isHovering = false
    #endif

    /// Only the selected cover looks its title page up in advance, as `prewarmsHeroArtwork` does for a card: under the pointer on Mac.
    private var prewarms: Bool {
        #if targetEnvironment(macCatalyst)
        isCentred && sectionIsVisible && isHovering
        #else
        isCentred && sectionIsVisible
        #endif
    }

    /// `onCentre` is left out: it only ever brings this poster to the middle.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.item == rhs.item && lhs.width == rhs.width && lhs.height == rhs.height && lhs.reflection == rhs.reflection
                && lhs.isCentred == rhs.isCentred && lhs.showsRating == rhs.showsRating
        }
    }

    /// The gap between a poster and its reflection.
    static let reflectionGap: CGFloat = 1

    private var sourceID: String { "\(zoomScope)/\(item.identity)" }

    var body: some View {
        let radius = Theme.Radius.poster
        let item = self.item
        let ratings = self.ratings
        let prewarms = self.prewarms
        let button = Button {
            if isCentred { openTitle() } else { onCentre() }
        } label: {
            LayoutPoster(item: item, width: width, height: height)
                .overlay(alignment: .bottom) {
                    if showsRating { PosterRatingsOverlay(item: item) }
                }
                .mediaArtwork(cornerRadius: radius)
                .zoomSource(id: sourceID, in: zoomNamespace, cornerRadius: radius * metrics.cornerScale(for: .artwork))
        }
        .buttonStyle(PressableCardStyle.poster)
        VStack(spacing: Self.reflectionGap) {
            // The same view whether or not the cover is selected, so a cover passing through the middle keeps its poster and ratings
            // instead of building them again. The selected cover is always on screen, so its lookup needs no visibility observer.
            button
                #if targetEnvironment(macCatalyst)
                .onHover { isHovering = $0 }
                #endif
                .task(id: "\(item.identity)|\(prewarms)", priority: .low) {
                    guard prewarms, let ratings, ratings.canLookUpHeroArtwork else { return }
                    // `.task` is cancelled when another cover takes the middle, which ends the wait before any lookup starts.
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await ratings.prewarmHeroArtwork(for: item)
                }
                .help(item.name)
                .titleCardMenu(item)
                .accessibilityLabel(item.name)
                // VoiceOver opens the title straight away, wherever the poster is.
                .accessibilityAction(.default) { openTitle() }
            // The reflection: the poster's foot upside down, fading into the page.
            LayoutPoster(item: item, width: width, height: height)
                .mediaArtwork(cornerRadius: radius)
                .scaleEffect(x: 1, y: -1)
                .frame(width: width, height: reflection, alignment: .top)
                .clipped()
                .mask {
                    LinearGradient(stops: [.init(color: .white.opacity(0.34), location: 0),
                                           .init(color: .white.opacity(0.08), location: 0.65),
                                           .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                }
                // Drawn once into a single picture, so the stacks' turning on every frame of a scroll does not mask it again.
                .drawingGroup()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func openTitle() {
        Haptics.play(.titles)
        router.homePath.append(TitleDestination(preview: item, sourceID: sourceID))
    }
}
#endif
