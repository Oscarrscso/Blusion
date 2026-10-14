#if canImport(UIKit)
import StremioKit
import SwiftUI
import UniformTypeIdentifiers

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
    /// The card being dragged, and the order the cards show while it is dragged. Nil when nothing is being dragged.
    @State private var dragging: String?
    @State private var liveOrder: [String]?

    /// Two cards across, with the same gutter between them as at the edges.
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

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

    /// The widgets in the order they show: the saved order, or the order a drag has reached while a card is being dragged.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if hidesWidgets && !model.widgets.isEmpty { hiddenRowsLine }
                if !hidesWidgets && !model.widgets.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(shownWidgets) { widget in
                            WidgetCard(widget: widget, services: services) { Task { await model.remove(id: widget.id) } }
                                // Long-press and drag: the other cards move aside as it passes them, with a tick for each step. Dropped, the
                                // order is saved. A tap still opens the widget.
                                .onDrag {
                                    dragging = widget.id
                                    liveOrder = model.widgets.map(\.id)
                                    Haptics.tap()
                                    return NSItemProvider(object: widget.id as NSString)
                                }
                                .onDrop(of: [.plainText], delegate: WidgetDropDelegate(target: widget.id, dragging: $dragging,
                                                                                       liveOrder: $liveOrder, model: model))
                                .accessibilityAction(named: "Move earlier") { move(widget.id, by: -1) }
                                .accessibilityAction(named: "Move later") { move(widget.id, by: 1) }
                        }
                    }
                    .animation(.snappy(duration: 0.3), value: shownWidgets.map(\.id))
                    .onDrop(of: [.plainText], delegate: WidgetGridDropDelegate(dragging: $dragging, liveOrder: $liveOrder, model: model))
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
        // A list that has just been imported or reset is shown too.
        .onChange(of: model.widgets.map(\.id)) { old, new in
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
                        .font(.system(size: 30, weight: .bold))
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
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
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

/// A card's drop target. A dragged card takes the place of each card it passes, with a tick each time, and the order is saved when it is
/// dropped on a card.
private struct WidgetDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?
    @Binding var liveOrder: [String]?
    let model: WidgetsManagerViewModel

    func dropEntered(info: DropInfo) {
        guard let dragged = dragging, dragged != target, var order = liveOrder,
              let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: target) else { return }
        withAnimation(.snappy(duration: 0.3)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            liveOrder = order
        }
        Haptics.selection()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        let saved = model.widgets.map(\.id)
        if let order = liveOrder, let dragged = dragging, let from = saved.firstIndex(of: dragged), let to = order.firstIndex(of: dragged),
           from != to {
            // The saved order moves the card to where the drag left it.
            let destination = to > from ? to + 1 : to
            Task { await model.move(fromOffsets: IndexSet(integer: from), toOffset: destination) }
        }
        dragging = nil
        liveOrder = nil
        return true
    }
}

/// The grid as a whole: a drop in a gap between cards saves the order the drag reached, and a drag that leaves the grid without a drop puts
/// the cards back in their saved order.
private struct WidgetGridDropDelegate: DropDelegate {
    @Binding var dragging: String?
    @Binding var liveOrder: [String]?
    let model: WidgetsManagerViewModel

    func dropExited(info: DropInfo) {
        withAnimation(.snappy(duration: 0.3)) {
            dragging = nil
            liveOrder = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        let saved = model.widgets.map(\.id)
        if let order = liveOrder, let dragged = dragging, let from = saved.firstIndex(of: dragged), let to = order.firstIndex(of: dragged),
           from != to {
            let destination = to > from ? to + 1 : to
            Task { await model.move(fromOffsets: IndexSet(integer: from), toOffset: destination) }
        }
        dragging = nil
        liveOrder = nil
        return true
    }
}

/// A screen pushed to make a new widget.
private enum NewWidgetRoute: Hashable, Identifiable {
    case widget
    var id: Self { self }
}
#endif
