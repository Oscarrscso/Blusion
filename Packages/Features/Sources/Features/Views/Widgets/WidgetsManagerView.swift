#if canImport(UIKit)
import StremioKit
import SwiftUI

struct WidgetsManagerView: View {
    let services: AppServices
    @State private var model: WidgetsManagerViewModel
    @State private var creating: NewWidgetRoute?
    @State private var showsGenreCollection = false
    @State private var showsImport = false
    @State private var showsReset = false
    @State private var showsPendingImport = false
    @State private var copied = false
    /// True while the toolbar's button has hidden every widget's card, leaving one line that says how many there are. Kept between
    /// visits, so a long list stays out of the way until it is shown again.
    @AppStorage("widgets.hidesRows") private var hidesWidgets = false
    /// The card being dragged, its centre where the drag began, how far the pointer has moved, and the order the cards show meanwhile.
    @State private var dragID: String?
    @State private var dragStart: CGPoint = .zero
    @State private var pointer: CGSize = .zero
    @State private var liveOrder: [String]?
    /// Each card's frame in the grid's own coordinate space, so a drag knows which card the pointer has reached.
    @State private var frames: [String: CGRect] = [:]

    private let gridSpace = "widgetGrid"

    /// Two cards across on iPhone. On the Mac as many as fit, at a size that keeps the card's proportions.
    private var columns: [GridItem] {
        #if targetEnvironment(macCatalyst)
        [GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 16)]
        #else
        [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        #endif
    }

    init(services: AppServices) {
        self.services = services
        _model = State(initialValue: WidgetsManagerViewModel(services: services))
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

    /// The widgets in the order they show: the saved order, or the order a drag has reached.
    private var shownWidgets: [HomeWidget] {
        guard let liveOrder else { return model.widgets }
        let byID = Dictionary(uniqueKeysWithValues: model.widgets.map { ($0.id, $0) })
        return liveOrder.compactMap { byID[$0] }
    }

    /// Moves a widget one place earlier or later. VoiceOver and keyboard users reorder this way, as dragging does for everyone else.
    private func move(_ id: String, by step: Int) {
        guard let from = model.widgets.firstIndex(where: { $0.id == id }) else { return }
        let to = from + step
        guard model.widgets.indices.contains(to) else { return }
        // Moving down lands after the card it passes; moving up lands before it.
        let destination = step > 0 ? to + 1 : to
        Task { await model.move(fromOffsets: IndexSet(integer: from), toOffset: destination) }
    }

    /// The card's drag: the card follows the pointer, and when its centre reaches another card, the two swap places, with a tick on iPhone.
    private func dragChanged(_ id: String, translation: CGSize) {
        if dragID == nil {
            guard let frame = frames[id] else { return }
            dragID = id
            dragStart = CGPoint(x: frame.midX, y: frame.midY)
            liveOrder = model.widgets.map(\.id)
        }
        guard dragID == id, let order = liveOrder, let from = order.firstIndex(of: id) else { return }
        pointer = translation
        let point = CGPoint(x: dragStart.x + translation.width, y: dragStart.y + translation.height)
        guard let target = order.first(where: { $0 != id && (frames[$0]?.contains(point) ?? false) }),
              let to = order.firstIndex(of: target), to != from else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            var next = order
            next.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            liveOrder = next
        }
        #if !targetEnvironment(macCatalyst)
        Haptics.selection()
        #endif
    }

    /// Saves the order the drag reached, and settles the dragged card into its place.
    private func dragEnded() {
        guard let id = dragID else { return }
        let saved = model.widgets.map(\.id)
        if let order = liveOrder, let from = saved.firstIndex(of: id), let to = order.firstIndex(of: id), from != to {
            let destination = to > from ? to + 1 : to
            Task { await model.move(fromOffsets: IndexSet(integer: from), toOffset: destination) }
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            dragID = nil
            pointer = .zero
        }
        // The order stays on screen until the saved list shows it, so the cards do not jump back and forth.
        let reached = liveOrder
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if liveOrder == reached { withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { liveOrder = nil } }
        }
    }

    /// The dragged card follows the pointer, wherever the grid has laid it out.
    private func dragOffset(for id: String) -> CGSize {
        guard dragID == id, let frame = frames[id] else { return .zero }
        return CGSize(width: dragStart.x + pointer.width - frame.midX, height: dragStart.y + pointer.height - frame.midY)
    }

    /// The card with the drag that reorders it. On the Mac a drag starts at once; on iPhone a press first, so the page still scrolls.
    @ViewBuilder
    private func reorderable<Card: View>(_ card: Card, id: String) -> some View {
        #if targetEnvironment(macCatalyst)
        card.simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(gridSpace))
                .onChanged { dragChanged(id, translation: $0.translation) }
                .onEnded { _ in dragEnded() })
        #else
        card.simultaneousGesture(
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(coordinateSpace: .named(gridSpace)))
                .onChanged { value in
                    if case .second(true, let drag?) = value { dragChanged(id, translation: drag.translation) }
                }
                .onEnded { _ in dragEnded() })
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if hidesWidgets && !model.widgets.isEmpty { hiddenRowsLine }
                if !hidesWidgets && !model.widgets.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(shownWidgets) { widget in
                            reorderable(
                                WidgetCard(widget: widget, services: services) { Task { await model.remove(id: widget.id) } }
                                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(gridSpace)) } action: { frames[widget.id] = $0 }
                                    .offset(dragOffset(for: widget.id))
                                    .scaleEffect(dragID == widget.id ? 1.05 : 1)
                                    .shadow(color: .black.opacity(dragID == widget.id ? 0.35 : 0), radius: 16, y: 10)
                                    .zIndex(dragID == widget.id ? 1 : 0)
                                    .accessibilityAction(named: "Move earlier") { move(widget.id, by: -1) }
                                    .accessibilityAction(named: "Move later") { move(widget.id, by: 1) },
                                id: widget.id)
                        }
                    }
                    .coordinateSpace(name: gridSpace)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: shownWidgets.map(\.id))
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
        }
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
        // The saved order has caught up with the order the drag reached, so the drag's order is no longer needed.
        .onChange(of: model.widgets.map(\.id)) { old, new in
            if let liveOrder, new == liveOrder { self.liveOrder = nil }
            if !old.isEmpty, !Set(new).isSubset(of: old) { withAnimation { hidesWidgets = false } }
        }
        .navigationDestination(for: HomeWidget.self) { WidgetEditorView(widget: $0, model: model, services: services) }
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

/// A widget as a card: a 2x2 collage of its own posters under a dark gradient, its name and style, and a delete button. Tapping the card
/// opens the widget's settings, where every setting of it is.
private struct WidgetCard: View {
    let widget: HomeWidget
    let services: AppServices
    let onDelete: () -> Void
    /// The posters the card shows, read when the card first appears.
    @State private var items: [MetaPreview] = []

    var body: some View {
        NavigationLink(value: widget) {
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
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
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
        }
        .buttonStyle(.plain)
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
