#if canImport(UIKit)
import os
import StremioKit
import SwiftUI
import UIKit

/// Each lift, swap and drop of a widget card, so a try on the phone can be read back from its log.
private let dragLog = Logger(subsystem: "app.blusion.player", category: "widgets.drag")

struct WidgetsManagerView: View {
    let services: AppServices
    @State private var model: WidgetsManagerViewModel
    @State private var creating: NewWidgetRoute?
    @State private var openedWidget: HomeWidget?
    @State private var showsGenreCollection = false
    @State private var showsImport = false
    @State private var showsReset = false
    @State private var showsPendingImport = false
    @State private var copied = false
    /// True while the toolbar's button has hidden every widget's card, leaving one line that says how many there are. Kept between
    /// visits, so a long list stays out of the way until it is shown again.
    @AppStorage("widgets.hidesRows") private var hidesWidgets = false
    @Environment(\.isLandscape) private var isLandscape

    /// The grid's order of widget ids, as the grid shows it. It follows the saved list, and a drag changes it until the drag is saved.
    @State private var order: [String] = []
    @State private var drag: GridDrag?
    /// The grid's width, measured on its container, so the slot layout never depends on its own size.
    @State private var gridWidth: CGFloat = 0
    @State private var liftCount = 0
    @State private var swapCount = 0
    /// The page's UIKit scroll view: the iPhone's press that lifts a card sits on it, and it scrolls while a card is held near an edge.
    @State private var scroller = GridScroller()
    @State private var autoScroll: Task<Void, Never>?
    /// Taps and the delete button do nothing until then: the touch that lifted and dropped a card is not also a tap.
    @State private var quietUntil = Date.distantPast
    /// True while the dragged card settles into its slot after it is let go.
    @State private var landing = false

    private static let coordinateSpace = "reorderGrid"

    init(services: AppServices) {
        self.services = services
        _model = State(initialValue: WidgetsManagerViewModel(services: services))
    }

    /// Two cards across on iPhone in portrait; more on iPhone in landscape and on the Mac, at the same 2:3 proportion.
    private var columnCount: Int {
        #if targetEnvironment(macCatalyst)
        return max(3, Int((gridWidth + WidgetSlotLayout.gutter) / (190 + WidgetSlotLayout.gutter)))
        #else
        if isLandscape { return max(3, Int((gridWidth + WidgetSlotLayout.gutter) / (160 + WidgetSlotLayout.gutter))) }
        return 2
        #endif
    }

    private var layout: WidgetSlotLayout {
        WidgetSlotLayout.fitting(width: gridWidth, columns: columnCount, count: order.count)
    }

    private var widgetsByID: [String: HomeWidget] {
        Dictionary(uniqueKeysWithValues: model.widgets.map { ($0.id, $0) })
    }

    /// The showcase, which is pinned to the top: the cards before the first ordinary one.
    private var showcaseIDs: Set<String> {
        Set(model.widgets.filter(WidgetsManagerViewModel.isShowcase).map(\.id))
    }

    private var pinnedCount: Int {
        order.prefix { showcaseIDs.contains($0) }.count
    }

    /// The plus: a menu of the widgets that can be added.
    private var addMenu: some View {
        // Adding a widget shows the cards, so the new one is not hidden with the rest.
        Menu {
            Button("New Widget", systemImage: "rectangle.stack.badge.plus") { hidesWidgets = false; creating = .widget }
            Button("Genre Collection", systemImage: "square.grid.2x2") { hidesWidgets = false; showsGenreCollection = true }
                .disabled(model.catalogChoices.allSatisfy { $0.genres.isEmpty })
            Button("Continue Watching", systemImage: "play.circle") {
                hidesWidgets = false
                Task { await model.add(HomeWidget(title: "Continue", content: .continueWatching)) }
            }
            .disabled(model.widgets.contains { $0.content == .continueWatching })
        } label: {
            Image(systemName: "plus")
        }
        .pointerFeedback()
        .accessibilityLabel("Add Widget")
        .accessibilityIdentifier("widgets.add")
    }

    /// Hides every widget's card at once, or shows them all again.
    private var hideToggle: some View {
        Button {
            withAnimation { hidesWidgets.toggle() }
        } label: {
            Image(systemName: hidesWidgets ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
        }
        .disabled(model.widgets.isEmpty)
        .accessibilityLabel(hidesWidgets ? "Show All Widgets" : "Hide All Widgets")
        .help(hidesWidgets ? "Show All Widgets" : "Hide All Widgets")
        .accessibilityIdentifier("widgets.hideAll")
    }

    /// The one line that stands in for the cards while they are hidden. A tap shows them again.
    private var hiddenRowsLine: some View {
        Button {
            withAnimation { hidesWidgets = false }
        } label: {
            Label(model.widgets.count == 1 ? "1 widget hidden" : "\(model.widgets.count) widgets hidden", systemImage: "eye.slash")
        }
        .accessibilityHint("Shows the widgets")
        .accessibilityIdentifier("widgets.hiddenRows")
    }

    /// The import, export and sharing actions, under the cards.
    private var importAndExport: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import & export").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Button("Import Widgets…") { showsImport = true }
                .accessibilityIdentifier("widgets.import")
            Button(copied ? "Copied" : "Copy as JSON") {
                UIPasteboard.general.string = model.exportJSON()
                copied = true
            }
            .accessibilityIdentifier("widgets.export")
            if let text = model.exportJSON() { ShareLink("Share JSON", item: text) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Order

    /// Follows the saved list, except while a card is being dragged, so a drag's order is not overwritten.
    private func syncOrder() {
        guard drag == nil else { return }
        let saved = model.widgets.map(\.id)
        if order != saved { order = saved }
    }

    /// Moves a card one place earlier or later, for VoiceOver and keyboard users, and saves it.
    private func moveCard(_ id: String, by step: Int) {
        guard let from = model.widgets.firstIndex(where: { $0.id == id }) else { return }
        let to = from + step
        guard model.widgets.indices.contains(to), !showcaseIDs.contains(id) else { return }
        // Moving down lands after the card it passes; moving up lands before it.
        let destination = step > 0 ? to + 1 : to
        Task { await model.move(fromOffsets: IndexSet(integer: from), toOffset: destination) }
    }

    // MARK: Drag

    /// Whether a touch at this point may lift a card: on a card, not the showcase, and not while another card is held or settling.
    private func canLift(at point: CGPoint) -> Bool {
        guard drag == nil, !landing, let index = layout.index(at: point), order.indices.contains(index),
              layout.frame(for: index).contains(point) else { return false }
        return !showcaseIDs.contains(order[index])
    }

    /// Starts a drag on the card under the point. The showcase and the gutters do not start one.
    private func beginDrag(at point: CGPoint) {
        guard canLift(at: point), let index = layout.index(at: point) else { return }
        let id = order[index]
        let centre = layout.center(for: index)
        liftCount += 1
        drag = GridDrag(id: id, grabOffset: CGSize(width: point.x - centre.x, height: point.y - centre.y), pointer: point, originalOrder: order)
        dragLog.notice("began \(id, privacy: .public) in slot \(index)")
        startAutoScroll()
    }

    /// Follows the pointer, and reorders as it reaches each slot. A card that is settling takes no more moves.
    private func updateDrag(to point: CGPoint) {
        guard !landing, var current = drag else { return }
        current.pointer = point
        drag = current
        retarget()
    }

    /// Puts the dragged card in the slot under the pointer. A pointer in a gutter keeps the card where it is, and the showcase keeps slot 0.
    private func retarget() {
        guard !landing, let current = drag, let from = order.firstIndex(of: current.id) else { return }
        let target = layout.target(at: current.pointer, from: from, pinned: pinnedCount)
        guard target != from else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            order = WidgetSlotLayout.moved(order, from: from, to: target)
        }
        swapCount += 1
        dragLog.notice("swap \(current.id, privacy: .public) from \(from) to \(target)")
    }

    /// Ends the drag. A drag that was not cancelled saves the order once, and settles the card into its slot. A cancelled one puts the cards
    /// back as they were.
    private func endDrag(cancelled: Bool) {
        guard !landing, let current = drag else { return }
        autoScroll?.cancel()
        autoScroll = nil
        quietUntil = Date().addingTimeInterval(0.4)
        if cancelled {
            dragLog.notice("cancelled \(current.id, privacy: .public)")
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                order = current.originalOrder
                drag = nil
            }
            syncOrder()
            return
        }
        dragLog.notice("dropped \(current.id, privacy: .public): \(order.joined(separator: ","), privacy: .public)")
        let saved = model.widgets.map(\.id)
        if let from = saved.firstIndex(of: current.id), let to = order.firstIndex(of: current.id), from != to {
            let destination = to > from ? to + 1 : to
            Task { await model.move(fromOffsets: IndexSet(integer: from), toOffset: destination) }
        }
        let slot = layout.center(for: order.firstIndex(of: current.id) ?? 0)
        landing = true
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            drag?.pointer = CGPoint(x: slot.x + current.grabOffset.width, y: slot.y + current.grabOffset.height)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            drag = nil
            landing = false
            // A save that was refused leaves the saved order as it was: the grid goes back to it.
            syncOrder()
        }
    }

    /// While a card is held near the top or bottom of what is visible, the page scrolls, and the card's place follows the pointer as the
    /// content moves under it.
    private func startAutoScroll() {
        autoScroll?.cancel()
        autoScroll = Task { @MainActor in
            while !Task.isCancelled, let current = drag, !landing {
                let moved = scroller.autoScrollStep(at: current.pointer)
                if moved != 0 {
                    drag?.pointer.y += moved
                    retarget()
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Where the dragged card's centre is drawn: under the pointer, or in its slot while it settles.
    private func overlayCentre(_ current: GridDrag) -> CGPoint {
        CGPoint(x: current.pointer.x - current.grabOffset.width, y: current.pointer.y - current.grabOffset.height)
    }

    /// Whether a tap or the delete button counts now: not while a card is held, nor just after one was dropped.
    private var takesTaps: Bool { drag == nil && Date() >= quietUntil }

    /// A card's tap opens its settings, unless the touch lifted a card.
    private func tapped(_ id: String) {
        guard takesTaps, let widget = widgetsByID[id] else { return }
        openedWidget = widget
    }

    /// The delete action of a card, or nil for Continue Watching, which Home always shows.
    private func deleteAction(for widget: HomeWidget) -> (() -> Void)? {
        guard WidgetsManagerViewModel.isRemovable(widget) else { return nil }
        return {
            guard takesTaps else { return }
            Task { await model.remove(id: widget.id) }
        }
    }

    // MARK: Grid

    private var grid: some View {
        let layout = self.layout
        return ZStack(alignment: .topLeading) {
            ForEach(order, id: \.self) { id in
                let index = order.firstIndex(of: id) ?? 0
                let isShowcase = showcaseIDs.contains(id)
                if let widget = widgetsByID[id] {
                    WidgetCard(widget: widget, services: services, onDelete: deleteAction(for: widget))
                        .frame(width: layout.cardWidth, height: layout.cardHeight)
                        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .opacity(drag?.id == id ? 0 : 1)
                        .position(layout.center(for: index))
                        .onTapGesture { tapped(id) }
                        .accessibilityActions {
                            // The showcase does not move. The card after it cannot move earlier, above it.
                            if !isShowcase {
                                if index > pinnedCount { Button("Move earlier") { moveCard(id, by: -1) } }
                                if index < order.count - 1 { Button("Move later") { moveCard(id, by: 1) } }
                            }
                        }
                }
            }
            if let current = drag, let widget = widgetsByID[current.id] {
                WidgetCard(widget: widget, services: services, onDelete: deleteAction(for: widget))
                    .frame(width: layout.cardWidth, height: layout.cardHeight)
                    .scaleEffect(landing ? 1 : 1.05)
                    .shadow(color: .black.opacity(landing ? 0 : 0.35), radius: 16, y: 10)
                    .position(overlayCentre(current))
                    .zIndex(1)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = landing ? .spring(response: 0.28, dampingFraction: 0.8) : nil }
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: order)
        .contentShape(Rectangle())
        .background(
            GridScrollAnchor(scroller: scroller, canLift: { canLift(at: $0) }, began: { beginDrag(at: $0) },
                             changed: { updateDrag(to: $0) }, ended: { endDrag(cancelled: $0) })
        )
        #if targetEnvironment(macCatalyst)
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpace))
                .onChanged { value in
                    if drag == nil { beginDrag(at: value.startLocation) }
                    updateDrag(to: value.location)
                }
                .onEnded { _ in endDrag(cancelled: false) }
        )
        .sensoryFeedback(.alignment, trigger: swapCount)
        #else
        // The press that lifts a card is on the page's scroll view (see `GridScroller`), not here.
        .sensoryFeedback(.impact(weight: .medium), trigger: liftCount)
        .sensoryFeedback(.selection, trigger: swapCount)
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if hidesWidgets && !model.widgets.isEmpty { hiddenRowsLine }
                if !hidesWidgets && !model.widgets.isEmpty {
                    grid
                        .accessibilityIdentifier("widgets.list")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Home rows").font(.title3.weight(.semibold))
                    Text(model.isCustomised ? "Your own layout." : "Home follows your addons. Change anything here to make it yours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.catalogChoices.isEmpty {
                    Text("Install an addon with catalogs, or use a Trakt list, to add more rows.").font(.footnote).foregroundStyle(.secondary)
                }
                importAndExport
                if model.isCustomised {
                    Button("Use Automatic Layout", role: .destructive) { showsReset = true }
                        .accessibilityIdentifier("widgets.reset")
                }
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(model.messageIsError ? Color.orange : Color.secondary)
                        .accessibilityIdentifier("widgets.message")
                }
            }
            .padding(16)
            .onGeometryChange(for: CGFloat.self) { max(0, $0.size.width - 32) } action: { gridWidth = $0 }
        }
        #if !targetEnvironment(macCatalyst)
        .scrollDisabled(drag != nil)
        #endif
        .readableColumn()
        .screenBackground()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("widgets.manager")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { hideToggle }
            ToolbarItem(placement: .topBarTrailing) { addMenu }
        }
        .task { await model.load() }
        .onAppear { syncOrder() }
        // The saved list has changed: the grid follows it, unless a card is being dragged. A change that makes the drag's order the saved
        // one ends the drag's own order.
        .onChange(of: model.widgets.map(\.id)) { old, new in
            syncOrder()
            if !old.isEmpty, !Set(new).isSubset(of: old) { withAnimation { hidesWidgets = false } }
        }
        .navigationDestination(item: $openedWidget) { WidgetEditorView(widget: $0, model: model, services: services) }
        .navigationDestination(item: $creating) { _ in WidgetEditorView(model: model, services: services) }
        .sheet(isPresented: $showsGenreCollection) {
            NavigationStack {
                WidgetSourcePicker(model: model, genresOnly: true, showsCancel: true) { choice, _ in
                    Task { await model.add(WidgetsManagerViewModel.makeGenreCollection(title: "Genres", choice: choice)) }
                    showsGenreCollection = false
                }
            }
        }
        .sheet(isPresented: $showsImport, onDismiss: {
            showsPendingImport = model.pendingImport != nil
        }) { NavigationStack { WidgetImportView(model: model) } }
        .confirmationDialog("Use the automatic layout?", isPresented: $showsReset, titleVisibility: .visible) {
            Button("Use Automatic Layout", role: .destructive) { Task { await model.resetToAutomatic() } }
        }
        .alert("Install Missing Addons?", isPresented: $showsPendingImport, presenting: model.pendingImport) { _ in
            Button("Install and Import") { Task { await model.installMissingAddonsAndFinishImport() } }
            Button("Import Without Them") { Task { await model.finishImportWithoutAddons() } }
            Button("Cancel", role: .cancel) { model.cancelImport() }
        } message: { pending in
            Text("This setup uses addons you don't have: \(pending.missingAddonHosts.joined(separator: ", ")).")
        }
        .overlay { if model.isWorking { ProgressView().padding().background(.regularMaterial, in: .capsule) } }
        .savedHUD(trigger: model.saveRevision)
        .disabled(model.isWorking)
    }
}

/// A card being dragged: which one, where the grab was, where the pointer is now, and the order before the drag.
private struct GridDrag: Equatable {
    let id: String
    /// The pointer minus the card's centre when the drag began, so the card keeps its place under the finger.
    let grabOffset: CGSize
    var pointer: CGPoint
    let originalOrder: [String]
}

/// The grid's link to the page's UIKit scroll view, found from a plain view behind the grid (`GridScrollAnchor`).
///
/// On iPhone the long press that lifts a card is put on that scroll view, outside SwiftUI's gestures. Attached to the grid, it came after the
/// cards' own taps, delete buttons and menus, which could keep it from ever starting. A quick swipe still scrolls: the press fails once
/// the finger moves 10 points before it has been held for 0.2 s. On iPhone and the Mac, the page scrolls while a held card is near the top
/// or bottom of what is visible.
@MainActor
private final class GridScroller: NSObject, UIGestureRecognizerDelegate {
    /// Whether a touch at this point, in the grid's coordinates, may lift a card.
    var canLift: (CGPoint) -> Bool = { _ in false }
    var began: (CGPoint) -> Void = { _ in }
    var changed: (CGPoint) -> Void = { _ in }
    /// Called with true when the press was cancelled, and false when it ended.
    var ended: (Bool) -> Void = { _ in }

    private weak var anchor: UIView?
    private weak var scrollView: UIScrollView?
    #if !targetEnvironment(macCatalyst)
    private lazy var press: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        recognizer.minimumPressDuration = 0.2
        recognizer.allowableMovement = 10
        recognizer.delegate = self
        return recognizer
    }()
    #endif

    /// Finds the scroll view around the anchor, and puts the press on it.
    func attach(_ anchor: UIView) {
        self.anchor = anchor
        var view = anchor.superview
        while let current = view, !(current is UIScrollView) { view = current.superview }
        let found = view as? UIScrollView
        guard found !== scrollView else { return }
        detach()
        scrollView = found
        dragLog.notice("grid \(found == nil ? "found no scroll view" : "attached to its scroll view", privacy: .public)")
        #if !targetEnvironment(macCatalyst)
        found?.addGestureRecognizer(press)
        #endif
    }

    /// The anchor left the window, for a pushed screen or a fading grid: the press comes off the scroll view. An anchor that a newer one
    /// has replaced (a grid hidden and shown again while it faded) changes nothing, so it cannot take the newer grid's press away.
    func detach(from anchor: UIView) {
        guard anchor === self.anchor else { return }
        detach()
    }

    /// The anchor is gone for good: the press comes off, and the grid's actions are let go, so they do not keep the page's state alive.
    func release(_ anchor: UIView) {
        guard anchor === self.anchor else { return }
        detach()
        canLift = { _ in false }
        began = { _ in }
        changed = { _ in }
        ended = { _ in }
    }

    private func detach() {
        #if !targetEnvironment(macCatalyst)
        press.view?.removeGestureRecognizer(press)
        #endif
        scrollView = nil
    }

    #if !targetEnvironment(macCatalyst)
    @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
        guard let anchor else { return }
        let point = recognizer.location(in: anchor)
        switch recognizer.state {
        case .began: began(point)
        case .changed: changed(point)
        case .ended: ended(false)
        case .cancelled, .failed: ended(true)
        default: break
        }
    }

    /// Only a touch on a card that can be lifted: everywhere else, the press does not take part at all.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let anchor else { return false }
        return canLift(touch.location(in: anchor))
    }

    /// The navigation stack's swipes back wait for the press to fail, so a card carried sideways never takes the page back. The scroll
    /// view's own pan does not wait: a quick swipe scrolls at once.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard let scrollView, other is UIPanGestureRecognizer, let view = other.view else { return false }
        return !view.isDescendant(of: scrollView)
    }
    #endif

    /// Scrolls the page one step while `point`, in the grid's coordinates, is near the top or bottom of what is visible, faster nearer
    /// the edge. Returns how far the page moved, so the held card's place can follow the content under it.
    func autoScrollStep(at point: CGPoint) -> CGFloat {
        guard let anchor, let scrollView else { return 0 }
        let insets = scrollView.adjustedContentInset
        let y = anchor.convert(point, to: scrollView).y - scrollView.contentOffset.y
        let top = insets.top
        let bottom = scrollView.bounds.height - insets.bottom
        let zone: CGFloat = 70
        var step: CGFloat = 0
        if y < top + zone {
            step = -(2 + 18 * min(1, (top + zone - y) / zone))
        } else if y > bottom - zone {
            step = 2 + 18 * min(1, (y - (bottom - zone)) / zone)
        }
        guard step != 0 else { return 0 }
        let lowest = -insets.top
        let highest = max(lowest, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
        let next = min(max(scrollView.contentOffset.y + step, lowest), highest)
        let moved = next - scrollView.contentOffset.y
        if moved != 0 { scrollView.contentOffset.y = next }
        return moved
    }
}

/// A plain view behind the grid, the same size, that hands `GridScroller` the page's scroll view and the grid's coordinates. It takes no
/// touches itself.
private struct GridScrollAnchor: UIViewRepresentable {
    let scroller: GridScroller
    let canLift: (CGPoint) -> Bool
    let began: (CGPoint) -> Void
    let changed: (CGPoint) -> Void
    let ended: (Bool) -> Void

    final class AnchorView: UIView {
        weak var scroller: GridScroller?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { scroller?.detach(from: self) } else { scroller?.attach(self) }
        }
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.scroller = scroller
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.scroller = scroller
        scroller.canLift = canLift
        scroller.began = began
        scroller.changed = changed
        scroller.ended = ended
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        view.scroller?.release(view)
    }
}

/// A widget as a card: a 2x2 collage of its own posters under a dark gradient, its name and style, and a delete button. Tapping the card
/// opens the widget's settings, where every setting of it is.
private struct WidgetCard: View {
    let widget: HomeWidget
    let services: AppServices
    /// Nil for Continue Watching, which has no delete button: Home always shows it.
    let onDelete: (() -> Void)?
    /// The posters the card shows, read when the card first appears.
    @State private var items: [MetaPreview] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            collage
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(widget.title.isEmpty ? "Untitled" : widget.title)
                    .font(.system(size: Self.titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(styleName)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: Self.trashSize * 0.39, weight: .semibold))
                        .frame(width: Self.trashSize, height: Self.trashSize)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(12)
                .accessibilityLabel("Delete \(widget.title)")
                .accessibilityIdentifier("widgets.menu.delete.\(widget.id)")
            }
        }
        #if targetEnvironment(macCatalyst)
        // A right click on the Mac. iPhone has no menu here: its long press lifts the card, and a menu under the finger with Delete in it
        // was one slide away from removing the card.
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("widgets.row.\(widget.id)")
        .task(id: widget.id) { await loadItems() }
    }

    /// The name's size, and the delete button's: a little smaller on the Mac, where the cards are.
    private static var titleSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        20
        #else
        30
        #endif
    }

    private static var trashSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        36
        #else
        44
        #endif
    }

    /// Two rows of two with a thin gap: the top row the widget's backdrops, the bottom row its posters. Empty tiles stay the card's colour.
    private var collage: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    tile(0, backdrop: true)
                    tile(1, backdrop: true)
                }
                HStack(spacing: gap) {
                    tile(2, backdrop: false)
                    tile(3, backdrop: false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(white: 0.14))
    }

    /// One picture of the collage, small enough to load quickly. A backdrop falls back to the poster when the title has none.
    private func tile(_ index: Int, backdrop: Bool) -> some View {
        let item = items.indices.contains(index) ? items[index] : nil
        let url = item.flatMap { backdrop ? ($0.background ?? $0.poster) : $0.poster }
        return ArtworkImage(url: url, title: item?.name ?? "", maxPixelSize: 300, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    /// The widget's style, as its editor names it.
    private var styleName: String {
        switch widget.content {
        case .hero: "Hero"
        case .banner: "Banner"
        case .row(let row): row.presentation.showsRank ? "Row Numbered" : "Row Classic"
        case .collection: "Collection"
        case .continueWatching: "Continue Watching"
        case .unsupported: "Unsupported"
        }
    }

    /// The posters a row or banner shows, from the copy Home keeps when there is one, else a short fetch from the same source.
    private func loadItems() async {
        guard let row = rowConfiguration else { return }
        if let known = await services.widgetContent.lastKnownItems(for: row.source, limit: 4), !known.isEmpty {
            items = Array(known.prefix(4))
            return
        }
        if let fresh = try? await services.widgetContent.items(for: row.source, limit: 4, cacheTTL: row.cacheTTL) {
            items = Array(fresh.prefix(4))
        }
    }

    private var rowConfiguration: RowConfiguration? {
        switch widget.content {
        case .hero(let row), .banner(let row), .row(let row): row
        default: nil
        }
    }
}

/// A screen pushed to make a new widget.
private enum NewWidgetRoute: Hashable, Identifiable {
    case widget
    var id: Self { self }
}
#endif
