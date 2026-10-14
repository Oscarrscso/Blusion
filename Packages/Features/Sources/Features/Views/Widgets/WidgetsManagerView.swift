#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

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
    @State private var contentOffsetY: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    /// The grid's top edge in the window, and the scroll content's height, for the edge scrolling.
    @State private var gridMinY: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    private static let scrollSpace = "widgetScroll"
    @State private var scrollPosition = ScrollPosition()
    @State private var autoScroll: Task<Void, Never>?
    /// Set when a drag moved the pointer, so the tap that ends it does not open the card.
    @State private var didDrag = false
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

    /// Starts a drag on the card under the point. The showcase and the gutters do not start one.
    private func beginDrag(at point: CGPoint) {
        guard drag == nil, let index = layout.index(at: point), order.indices.contains(index) else { return }
        let id = order[index]
        guard !showcaseIDs.contains(id) else { return }
        let centre = layout.center(for: index)
        didDrag = false
        liftCount += 1
        drag = GridDrag(id: id, start: point, grabOffset: CGSize(width: point.x - centre.x, height: point.y - centre.y),
                        pointer: point, originalOrder: order)
        startAutoScroll()
    }

    /// Follows the pointer, and reorders as it reaches each slot. A card that is settling takes no more moves.
    private func updateDrag(to point: CGPoint) {
        guard !landing, var current = drag else { return }
        current.pointer = point
        if abs(point.x - current.start.x) > 6 || abs(point.y - current.start.y) > 6 { didDrag = true }
        drag = current
        retarget()
    }

    /// Puts the dragged card in the slot under the pointer. A pointer in a gutter keeps the card where it is, and the showcase keeps slot 0.
    private func retarget() {
        guard let current = drag, let from = order.firstIndex(of: current.id) else { return }
        let reached = layout.index(at: current.pointer) ?? from
        let target = max(reached, pinnedCount)
        guard target != from else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            order = WidgetSlotLayout.moved(order, from: from, to: target)
        }
        swapCount += 1
    }

    /// Ends the drag. A drag that was not cancelled saves the order once, and settles the card into its slot. A cancelled one puts the cards
    /// back as they were.
    private func endDrag(cancelled: Bool) {
        guard !landing, let current = drag else { return }
        autoScroll?.cancel()
        autoScroll = nil
        if cancelled {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                order = current.originalOrder
                drag = nil
            }
            // A cancelled touch ends without a tap, so the flag is cleared here rather than left for the next tap to swallow.
            didDrag = false
            syncOrder()
            return
        }
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
            // A tap right after the drop is the drop's own, so the flag is cleared once the card has settled.
            didDrag = false
            // If the save was refused, the grid goes back to the saved order here.
            syncOrder()
        }
    }

    /// While a card is held near the top or bottom of the window, the page scrolls, and the card's place follows the pointer as the
    /// content moves under it.
    private func startAutoScroll() {
        autoScroll?.cancel()
        autoScroll = Task { @MainActor in
            let zone: CGFloat = 60
            while !Task.isCancelled, drag != nil {
                // The finger's place in the window: the grid's top edge in the window, plus the pointer's place in the grid.
                let windowY = (drag?.pointer.y ?? 0) + gridMinY
                var step: CGFloat = 0
                if windowY < zone {
                    step = -(2 + 18 * (zone - windowY) / zone)
                } else if windowY > viewportHeight - zone {
                    step = 2 + 18 * (windowY - (viewportHeight - zone)) / zone
                }
                if step != 0 {
                    let limit = max(0, contentHeight - viewportHeight)
                    let next = min(max(0, contentOffsetY + step), limit)
                    let delta = next - contentOffsetY
                    if delta != 0 {
                        scrollPosition.scrollTo(y: next)
                        contentOffsetY = next
                        drag?.pointer.y += delta
                        retarget()
                    }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Where the dragged card's centre is drawn: under the pointer, or in its slot while it settles.
    private func overlayCentre(_ current: GridDrag) -> CGPoint {
        CGPoint(x: current.pointer.x - current.grabOffset.width, y: current.pointer.y - current.grabOffset.height)
    }

    /// A card's tap opens its settings, unless the touch was a drag.
    private func tapped(_ id: String) {
        if didDrag {
            didDrag = false
            return
        }
        if let widget = widgetsByID[id] { openedWidget = widget }
    }

    // MARK: Grid

    private var grid: some View {
        let layout = self.layout
        return ZStack(alignment: .topLeading) {
            ForEach(order, id: \.self) { id in
                let index = order.firstIndex(of: id) ?? 0
                let isShowcase = showcaseIDs.contains(id)
                if let widget = widgetsByID[id] {
                    WidgetCard(widget: widget, services: services) { Task { await model.remove(id: widget.id) } }
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
                WidgetCard(widget: widget, services: services) { Task { await model.remove(id: widget.id) } }
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
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.scrollSpace)).minY } action: { gridMinY = $0 }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: order)
        .contentShape(Rectangle())
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
        .gesture(
            GridLongPress(
                began: { beginDrag(at: $0) },
                changed: { updateDrag(to: $0) },
                ended: { endDrag(cancelled: $0) }
            )
        )
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
        .coordinateSpace(name: Self.scrollSpace)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in contentOffsetY = new }
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, new in viewportHeight = new }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, new in contentHeight = new }
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
    /// Where the drag began, in the grid's coordinates.
    let start: CGPoint
    /// The pointer minus the card's centre when the drag began, so the card keeps its place under the finger.
    let grabOffset: CGSize
    var pointer: CGPoint
    let originalOrder: [String]
}

#if !targetEnvironment(macCatalyst)
/// A long press that becomes the drag on iPhone. It works alongside the scroll view, so a quick swipe still scrolls and cancels the press.
private struct GridLongPress: UIGestureRecognizerRepresentable {
    let began: (CGPoint) -> Void
    let changed: (CGPoint) -> Void
    /// Called with true when the press was cancelled, and false when it ended.
    let ended: (Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.2
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .named("reorderGrid"))
        switch recognizer.state {
        case .began: began(point)
        case .changed: changed(point)
        case .ended: ended(false)
        case .cancelled, .failed: ended(true)
        default: break
        }
    }
}
#endif

/// A widget as a card: a 2x2 collage of its own posters under a dark gradient, its name and style, and a delete button. Tapping the card
/// opens the widget's settings, where every setting of it is.
private struct WidgetCard: View {
    let widget: HomeWidget
    let services: AppServices
    let onDelete: () -> Void
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
        .contextMenu {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
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
