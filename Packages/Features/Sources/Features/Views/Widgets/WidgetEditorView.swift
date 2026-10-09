#if canImport(UIKit)
import StremioKit
import SwiftUI

/// The one editor for a widget, new or existing: Source, then its title, then how it is sorted or filtered, then how it looks. Adding
/// and editing differ only in the title, the button ("Add" or "Save") and whether the widget already has a source.
struct WidgetEditorView: View {
    enum Mode { case create, edit }

    let model: WidgetsManagerViewModel
    let services: AppServices
    let mode: Mode
    @State private var widget: HomeWidget
    @State private var hasSource: Bool
    /// False while the title follows the source's name (the field then shows it as a placeholder).
    @State private var titleIsCustom: Bool
    /// A Trakt sort chosen before the list is: it is applied when the list is.
    @State private var pendingSort: TraktListSort?
    @State private var showsPicker = false
    @State private var showsTraktBrowser = false
    @State private var showsTileSource = false
    @State private var editedTile: CollectionItem?
    @Environment(\.dismiss) private var dismiss

    /// Edits `widget`.
    init(widget: HomeWidget, model: WidgetsManagerViewModel, services: AppServices) {
        self.model = model
        self.services = services
        mode = .edit
        _widget = State(initialValue: widget)
        _hasSource = State(initialValue: true)
        var isCustom = true
        if let row = WidgetEditorView.row(of: widget) { isCustom = widget.title != model.autoTitle(for: row.source) }
        _titleIsCustom = State(initialValue: isCustom)
    }

    /// Makes a new row, spotlight or banner; it has no source until one is chosen.
    init(model: WidgetsManagerViewModel, services: AppServices) {
        self.model = model
        self.services = services
        mode = .create
        _widget = State(initialValue: HomeWidget(title: "", content: .row(RowConfiguration(source: .unsupported(kind: "")))))
        _hasSource = State(initialValue: false)
        _titleIsCustom = State(initialValue: false)
    }

    private static func row(of widget: HomeWidget) -> RowConfiguration? {
        switch widget.content {
        case .row(let row), .hero(let row), .banner(let row): return row
        case .collection, .continueWatching, .unsupported: return nil
        }
    }

    var body: some View {
        Form {
            switch widget.content {
            case .row, .hero, .banner:
                rowFields
            case .collection(let tiles):
                titleSection
                tilesSection(tiles)
            case .continueWatching:
                titleSection
            case .unsupported:
                Section {
                    Text("Blusion can't show this kind of row yet, so it has no settings here. It is kept so your layout stays intact.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if mode == .edit {
                Section {
                    Button("Remove Widget", role: .destructive) {
                        Task { await model.remove(id: widget.id); dismiss() }
                    }
                    .accessibilityIdentifier("widgetEditor.remove")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(mode == .create ? "New Widget" : "Edit Widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(mode == .create ? "Add" : "Save", action: commit)
                    .disabled(!canCommit)
                    .accessibilityIdentifier("widgetEditor.save")
            }
            if case .collection = widget.content { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        }
        .navigationDestination(isPresented: $showsPicker) {
            WidgetSourcePicker(model: model, openTraktLists: { showsTraktBrowser = true }, chooseTrakt: { source in
                applySource(source)
                showsPicker = false
            }) { choice, _ in
                applySource(.addonCatalog(choice.reference))
                showsPicker = false
            }
        }
        .navigationDestination(isPresented: $showsTraktBrowser) {
            TraktListBrowserView(services: services, navigationTitle: mode == .create ? "New Widget" : "Edit Widget",
                                 actionTitle: mode == .create ? "Add" : "Save", title: titleBinding,
                                 titlePlaceholder: model.autoTitle(for: row.wrappedValue.source), sort: sortBinding,
                                 selectedID: selectedTraktListID, canAdd: selectedTraktListID != nil,
                                 select: { applySource(.traktList($0.reference(sort: pendingSort))) }, commit: commit)
        }
        .sheet(isPresented: $showsTileSource) {
            NavigationStack {
                WidgetSourcePicker(model: model, genresOnly: true, showsCancel: true) { choice, genre in
                    var reference = choice.reference
                    reference.genre = genre
                    applySource(.addonCatalog(reference), tileTitle: genre ?? choice.title)
                    showsTileSource = false
                }
            }
        }
        .sheet(item: $editedTile) { tile in
            NavigationStack {
                CollectionTileEditor(tile: tile) { changed in
                    guard case .collection(var tiles) = widget.content, let index = tiles.firstIndex(where: { $0.id == changed.id }) else { return }
                    tiles[index] = changed
                    widget.content = .collection(tiles)
                    editedTile = nil
                }
            }
        }
    }

    // MARK: Saving

    private var canCommit: Bool {
        switch widget.content {
        case .row, .hero, .banner: return hasSource
        case .collection, .continueWatching, .unsupported: return true
        }
    }

    private func commit() {
        guard canCommit else { return }
        var saved = widget
        if saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let row = WidgetEditorView.row(of: saved) {
            saved.title = model.autoTitle(for: row.source)
        }
        Task {
            if mode == .create { await model.add(saved) } else { await model.update(saved) }
            dismiss()
        }
    }

    // MARK: Source

    /// Puts a source into the widget: a row, spotlight or banner takes it (and its name as the title, unless the user typed one);
    /// a collection adds it as a tile named `tileTitle`.
    private func applySource(_ source: WidgetSource, tileTitle: String? = nil) {
        switch widget.content {
        case .row(var row): row.source = source; widget.content = .row(row)
        case .hero(var row): row.source = source; widget.content = .hero(row)
        case .banner(var row): row.source = source; widget.content = .banner(row)
        case .collection(var tiles):
            tiles.append(CollectionItem(title: tileTitle ?? model.autoTitle(for: source), sources: [source]))
            widget.content = .collection(tiles)
        case .continueWatching, .unsupported: return
        }
        hasSource = true
        if !titleIsCustom, WidgetEditorView.row(of: widget) != nil { widget.title = model.autoTitle(for: source) }
    }

    private var row: Binding<RowConfiguration> {
        Binding {
            WidgetEditorView.row(of: widget) ?? RowConfiguration(source: .unsupported(kind: ""))
        } set: { value in
            switch widget.content {
            case .hero: widget.content = .hero(value)
            case .banner: widget.content = .banner(value)
            default: widget.content = .row(value)
            }
        }
    }

    /// The field shows only a title the user typed; an empty field means "named after the source", which the placeholder shows.
    private var titleBinding: Binding<String> {
        Binding {
            titleIsCustom ? widget.title : ""
        } set: { text in
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleIsCustom = false
                if let row = WidgetEditorView.row(of: widget) { widget.title = hasSource ? model.autoTitle(for: row.source) : "" }
            } else {
                titleIsCustom = true
                widget.title = text
            }
        }
    }

    private var sortBinding: Binding<TraktListSort?> {
        Binding {
            if case .traktList(let list) = row.wrappedValue.source { return list.sort }
            return pendingSort
        } set: { sort in
            pendingSort = sort
            guard case .traktList(var list) = row.wrappedValue.source else { return }
            list.sort = sort
            row.wrappedValue.source = .traktList(list)
        }
    }

    private var selectedTraktListID: Int? {
        guard hasSource, case .traktList(let list) = row.wrappedValue.source else { return nil }
        return list.traktID
    }

    // MARK: Sections

    private var titleSection: some View {
        Section("Title") {
            TextField(titlePlaceholder, text: titleBinding).accessibilityIdentifier("widgetEditor.title")
            Toggle("Hide title on Home", isOn: $widget.hideTitle)
        }
    }

    private var titlePlaceholder: String {
        if let row = WidgetEditorView.row(of: widget), hasSource { return model.autoTitle(for: row.source) }
        return "Widget title (optional)"
    }

    @ViewBuilder
    private var rowFields: some View {
        Section("Source") {
            Button { showsPicker = true } label: {
                HStack {
                    Text(hasSource ? model.describe(row.wrappedValue.source) : "Choose a source")
                        .foregroundStyle(hasSource ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("widgetEditor.source")
            if hasSource, case .traktList = row.wrappedValue.source {
                Button("Browse Trakt Lists") { showsTraktBrowser = true }.accessibilityIdentifier("widgetEditor.browseTrakt")
            }
        }
        titleSection
        if hasSource { sortAndFilter }
        appearance
    }

    @ViewBuilder
    private var sortAndFilter: some View {
        switch row.wrappedValue.source {
        case .traktList:
            Section {
                ChipRow {
                    GlassChip("List Default", isSelected: sortBinding.wrappedValue == nil) { sortBinding.wrappedValue = nil }
                    ForEach(TraktListSort.allCases) { option in
                        GlassChip(option.title, isSelected: sortBinding.wrappedValue == option) { sortBinding.wrappedValue = option }
                    }
                }
                .padding(.vertical, Theme.Spacing.s)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Sort")
            } footer: {
                Text("List Default keeps the order the list's owner chose.")
            }
        case .addonCatalog(let reference):
            let genres = model.genres(for: row.wrappedValue.source)
            if !genres.isEmpty {
                Section("Filter") {
                    Picker("Genre", selection: Binding<String?>(get: { reference.genre }, set: { setGenre($0) })) {
                        Text("All genres").tag(String?.none)
                        ForEach(genres, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .accessibilityIdentifier("widgetEditor.genre")
                }
            }
        case .traktFeed, .unsupported:
            EmptyView()
        }
    }

    private func setGenre(_ genre: String?) {
        guard case .addonCatalog(var reference) = row.wrappedValue.source else { return }
        reference.genre = genre
        applySource(.addonCatalog(reference))
    }

    private var style: Binding<WidgetStyle> {
        Binding {
            WidgetStyle(widget.content) ?? .row
        } set: { widget = WidgetStyle.restyled(widget, as: $0) }
    }

    @ViewBuilder
    private var appearance: some View {
        Section("Appearance") {
            Picker("Style", selection: style) {
                ForEach(WidgetStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("widgetEditor.style")
            Toggle("Show ratings", isOn: row.presentation.showsRatings)
            DisclosureGroup("More options") {
                if style.wrappedValue == .row {
                    Picker("Shape", selection: row.presentation.aspectRatio) {
                        ForEach(WidgetPresentation.AspectRatio.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Size", selection: row.presentation.cardStyle) {
                        ForEach(WidgetPresentation.CardStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Numbered (top list)", isOn: row.presentation.showsRank)
                        .accessibilityIdentifier("widgetEditor.numbered")
                }
                Picker("Items", selection: row.limit) {
                    ForEach(WidgetEditorView.limits(including: row.wrappedValue.limit), id: \.self) { Text("\($0)").tag($0) }
                }
                .accessibilityIdentifier("widgetEditor.items")
            }
        }
    }

    /// The item counts on offer, and the widget's own when it is not one of them (an import can carry any count from 1 to 100).
    private static func limits(including current: Int) -> [Int] {
        Array(Set([5, 10, 15, 20, 30, 40, 50, 75, 100, current])).sorted()
    }

    private func tilesSection(_ tiles: [CollectionItem]) -> some View {
        Section("Tiles") {
            ForEach(tiles) { tile in
                Button { editedTile = tile } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.title)
                        if let source = tile.sources.first {
                            Text(model.describe(source)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in widget.content = .collection(tiles.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)) }
            .onMove { offsets, destination in
                var moved = tiles
                moved.move(fromOffsets: offsets, toOffset: destination)
                widget.content = .collection(moved)
            }
            Button("Add Tile") { showsTileSource = true }
        }
    }
}

private struct CollectionTileEditor: View {
    @State private var tile: CollectionItem
    @State private var imageURL: String
    let save: (CollectionItem) -> Void
    @Environment(\.dismiss) private var dismiss

    init(tile: CollectionItem, save: @escaping (CollectionItem) -> Void) {
        _tile = State(initialValue: tile)
        _imageURL = State(initialValue: tile.imageURL?.absoluteString ?? "")
        self.save = save
    }

    var body: some View {
        Form {
            TextField("Title", text: $tile.title)
            Toggle("Hide title", isOn: $tile.hideTitle)
            Picker("Shape", selection: $tile.imageAspect) {
                ForEach(WidgetPresentation.AspectRatio.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            TextField("Image URL (optional)", text: $imageURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Edit Tile")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let text = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    tile.imageURL = text.isEmpty ? nil : URL(string: text)
                    save(tile)
                }
            }
        }
    }
}
#endif
