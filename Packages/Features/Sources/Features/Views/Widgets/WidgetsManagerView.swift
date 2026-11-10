#if canImport(UIKit)
import os
import StremioKit
import SwiftUI
import UIKit
// The second-finger scroll sets its own recognizer state, which only this part of UIKit allows.
// swiftlint:disable:next duplicate_imports
import UIKit.UIGestureRecognizerSubclass

/// Each lift, swap and drop of a widget card, so a try on the phone can be read back from its log.
let dragLog = Logger(subsystem: "app.blusion.player", category: "widgets.drag")

struct WidgetsManagerView: View {
    @Environment(\.layoutMetrics) private var metrics
    let services: AppServices
    @State private var model: WidgetsManagerViewModel
    @State private var openedWidget: HomeWidget?
    /// True while Add Widget is pushed.
    @State private var showsGallery = false
    @State private var showsImport = false
    @State private var showsReset = false
    @State private var showsPendingImport = false
    @State private var copied = false
    @AppStorage(OptimisationSettings.lowPerformanceWidgetsKey) private var lowPerformanceMode = false
    /// True while the toolbar's button has hidden every widget's card, leaving one line that says how many there are. Kept between
    /// visits to the Mac's Widgets tab, so a long list stays out of the way until it is shown again.
    @AppStorage("widgets.hidesRows") private var storedHidesWidgets = false
    /// Opened from Settings, the cards start hidden on every visit; nil follows the stored choice.
    @State private var visitHidesWidgets: Bool?
    private var hidesWidgets: Bool {
        get { visitHidesWidgets ?? storedHidesWidgets }
        nonmutating set {
            if visitHidesWidgets != nil { visitHidesWidgets = newValue } else { storedHidesWidgets = newValue }
        }
    }
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

    init(services: AppServices, startsHidden: Bool = false) {
        self.services = services
        _model = State(initialValue: WidgetsManagerViewModel(services: services))
        _visitHidesWidgets = State(initialValue: startsHidden ? true : nil)
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

    /// The plus: Add Widget, a page of every widget that can be added, each drawn as Home draws it.
    private var addButton: some View {
        Button { showsGallery = true } label: {
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

    /// The import, export and sharing actions, under the cards: one group of rows, each with its symbol.
    private var importAndExport: some View {
        WidgetsPageGroup("Import & Export") {
            Button { showsImport = true } label: {
                WidgetsPageRow("Import Widgets", systemImage: "square.and.arrow.down") {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("widgets.import")
            Divider().padding(.leading, WidgetsPageRow<EmptyView>.textInset)
            Button {
                UIPasteboard.general.string = model.exportJSON()
                copied = true
            } label: {
                WidgetsPageRow(copied ? "Copied" : "Copy as JSON", systemImage: copied ? "checkmark" : "doc.on.doc") { EmptyView() }
            }
            .accessibilityIdentifier("widgets.export")
            if let text = model.exportJSON() {
                Divider().padding(.leading, WidgetsPageRow<EmptyView>.textInset)
                ShareLink(item: text) {
                    WidgetsPageRow("Share JSON", systemImage: "square.and.arrow.up") { EmptyView() }
                }
            }
        }
    }

    /// Back to the layout that follows the addons, asked for in a dialog.
    private var resetRow: some View {
        WidgetsPageGroup(nil) {
            Button(role: .destructive) { showsReset = true } label: {
                WidgetsPageRow("Use Automatic Layout", systemImage: "arrow.counterclockwise") { EmptyView() }
                    .foregroundStyle(.red)
                    .tint(.red)
            }
            .accessibilityIdentifier("widgets.reset")
        }
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

    /// While a card is held near the top or bottom of what is visible, or a second finger drags the page, the page scrolls, and the card's
    /// place follows the pointer as the content moves under it.
    private func startAutoScroll() {
        autoScroll?.cancel()
        // A new card starts with no scroll counted from before it was held.
        _ = scroller.takeFingerScroll()
        autoScroll = Task { @MainActor in
            while !Task.isCancelled, let current = drag, !landing {
                // The page moves near its edges, and under a second finger: the card's place follows the content either way.
                let moved = scroller.autoScrollStep(at: current.pointer) + scroller.takeFingerScroll()
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

    /// The duplicate action of a card, or nil for Continue Watching and the showcase, which are one of a kind. The copy goes straight after
    /// the card, with a light tap.
    private func duplicateAction(for widget: HomeWidget) -> (() -> Void)? {
        guard WidgetsManagerViewModel.isDuplicable(widget) else { return nil }
        return {
            guard takesTaps else { return }
            Haptics.play(.buttons)
            Task { await model.duplicate(id: widget.id) }
        }
    }

    /// Shuffle for every widget without its own (see a widget's Shuffle setting), and for the order of Home's widgets.
    private var shuffleSettings: some View {
        WidgetsPageGroup("Shuffle") {
            WidgetsPageRow("Shuffle titles", systemImage: "shuffle") {
                Picker("Shuffle titles", selection: Binding(get: { model.shuffle.schedule }, set: { schedule in
                    var settings = model.shuffle
                    settings.schedule = schedule
                    Task { await model.setShuffle(settings) }
                })) {
                    ForEach(WidgetShuffle.choices, id: \.self) { Text(WidgetBuilderModel.shuffleText($0, compact: true)).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                // The menu's label keeps to one line; the row's title takes what is left.
                .fixedSize()
                .accessibilityIdentifier("widgets.shuffle")
            }
            Divider().padding(.leading, WidgetsPageRow<EmptyView>.textInset)
            WidgetsPageRow("Shuffle widget order", systemImage: "arrow.up.arrow.down") {
                Toggle("Shuffle widget order", isOn: Binding(get: { model.shuffle.shufflesOrder }, set: { on in
                    var settings = model.shuffle
                    settings.shufflesOrder = on
                    Task { await model.setShuffle(settings) }
                }))
                .labelsHidden()
                .accessibilityIdentifier("widgets.shuffleOrder")
            }
            .disabled(model.shuffle.schedule == .off)
        }
    }

    /// Everything under the cards. On the Mac the grid takes the whole window, as the Mac's other grids do, and only these keep to the
    /// readable column.
    private var settingsGroups: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            WidgetsPageGroup(nil) {
                WidgetsPageRow("Low Performance Mode", systemImage: "leaf") {
                    Toggle("Low Performance Mode", isOn: $lowPerformanceMode)
                        .labelsHidden()
                        .accessibilityIdentifier("widgets.lowPerformanceMode")
                }
            }
            if model.catalogChoices.isEmpty {
                Text("Install an addon with catalogs, or use a Trakt list, to add more rows.").font(.footnote).foregroundStyle(.secondary)
            }
            shuffleSettings
            importAndExport
            if model.isCustomised { resetRow }
            if let message = model.message {
                Text(message).font(.footnote).foregroundStyle(model.messageIsError ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("widgets.message")
            }
        }
        #if targetEnvironment(macCatalyst)
        .readableColumn()
        #endif
    }

    // MARK: Grid

    private var grid: some View {
        let layout = self.layout
        return ZStack(alignment: .topLeading) {
            ForEach(order, id: \.self) { id in
                let index = order.firstIndex(of: id) ?? 0
                let isShowcase = showcaseIDs.contains(id)
                if let widget = widgetsByID[id] {
                    WidgetCard(widget: widget, services: services, onDelete: deleteAction(for: widget),
                               onDuplicate: duplicateAction(for: widget))
                        .frame(width: layout.cardWidth, height: layout.cardHeight)
                        .contentShape(RoundedRectangle(cornerRadius: 28 * metrics.cornerScale(for: .panels), style: .continuous))
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
                WidgetCard(widget: widget, services: services, onDelete: deleteAction(for: widget),
                           onDuplicate: duplicateAction(for: widget))
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
            GridScrollAnchor(scroller: scroller, canLift: { canLift(at: $0) }, isHolding: { drag != nil && !landing },
                             began: { beginDrag(at: $0) }, changed: { updateDrag(to: $0) }, ended: { endDrag(cancelled: $0) })
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
        // A tick as two cards change places, in the Pickers & switches place, so the Haptics page reaches it. The lift above stays
        // SwiftUI's medium impact, a weight the drag's own gesture owns, and the Mac's drag gives its own in the branch above.
        .onChange(of: swapCount) { _, _ in Haptics.play(.choices) }
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                #if targetEnvironment(macCatalyst)
                HStack {
                    Spacer()
                    hideToggle
                    addButton
                }
                #endif
                if hidesWidgets && !model.widgets.isEmpty { hiddenRowsLine }
                if !hidesWidgets && !model.widgets.isEmpty {
                    grid
                        .accessibilityIdentifier("widgets.list")
                }
                settingsGroups
            }
            .padding(16)
            .onGeometryChange(for: CGFloat.self) { max(0, $0.size.width - 32) } action: { gridWidth = $0 }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        #if !targetEnvironment(macCatalyst)
        .scrollDisabled(drag != nil)
        .readableColumn()
        #endif
        .screenBackground()
        .navigationTitle("Widgets")
        .macRootNavigation()
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("widgets.manager")
        #if !targetEnvironment(macCatalyst)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { hideToggle }
            ToolbarItem(placement: .topBarTrailing) { addButton }
        }
        #endif
        .task { await model.load() }
        .task { await model.loadShuffle() }
        .onAppear { syncOrder() }
        // The saved list has changed: the grid follows it, unless a card is being dragged. A change that makes the drag's order the saved
        // one ends the drag's own order.
        .onChange(of: model.widgets.map(\.id)) { old, new in
            syncOrder()
            if !old.isEmpty, !Set(new).isSubset(of: old) { withAnimation { hidesWidgets = false } }
        }
        .navigationDestination(item: $openedWidget) { WidgetEditorView(widget: $0, model: model, services: services) }
        // Adding a widget shows the cards, so the new one is not hidden with the rest. Leaving Add Widget also leaves the settings opened
        // from it, back to the cards.
        .navigationDestination(isPresented: $showsGallery) {
            WidgetGalleryView(model: model, services: services) {
                hidesWidgets = false
                showsGallery = false
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
        .overlay { if model.isWorking { Spinner().padding().background(.regularMaterial, in: ScaledCapsule(scale: metrics.cornerScale(for: .panels))) } }
        .savedHUD(trigger: model.saveRevision)
        .disabled(model.isWorking)
    }
}
#endif
