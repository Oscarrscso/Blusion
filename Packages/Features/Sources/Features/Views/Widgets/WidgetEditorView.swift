#if canImport(UIKit)
import StremioKit
import SwiftUI

struct WidgetEditorView: View {
    let model: WidgetsManagerViewModel
    @State private var widget: HomeWidget
    @State private var showsSource = false
    @State private var editedTile: CollectionItem?
    @Environment(\.dismiss) private var dismiss

    init(widget: HomeWidget, model: WidgetsManagerViewModel) {
        self.model = model
        _widget = State(initialValue: widget)
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $widget.title).accessibilityIdentifier("widgetEditor.title")
                Toggle("Hide title", isOn: $widget.hideTitle)
            }
            switch widget.content {
            case .row, .hero:
                rowFields
            case .collection(let tiles):
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
                    Button("Add Tile") { showsSource = true }
                }
            case .continueWatching:
                EmptyView()
            case .unsupported:
                Section {
                    Text("Blusion can't show this kind of row yet, so it has no settings here. It is kept so your layout stays intact.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Remove Widget", role: .destructive) {
                    Task { await model.remove(id: widget.id); dismiss() }
                }
                .accessibilityIdentifier("widgetEditor.remove")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Edit Widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await model.update(widget); dismiss() } }
                    .buttonStyle(.glass).foregroundStyle(.white)
                    .accessibilityIdentifier("widgetEditor.save")
            }
            if case .collection = widget.content { ToolbarItem(placement: .topBarTrailing) { EditButton().buttonStyle(.glass).foregroundStyle(.white) } }
        }
        .sheet(isPresented: $showsSource) {
            NavigationStack {
                WidgetSourcePicker(model: model, chooseTrakt: { source in
                    useSource(source, title: WidgetsManagerViewModel.traktTitle(source))
                }) { choice, genre in
                    var reference = choice.reference
                    reference.genre = genre
                    useSource(.addonCatalog(reference), title: genre ?? choice.title)
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

    /// Puts a source into the widget being edited: a row or spotlight takes it, a collection adds it as a tile named `title`.
    private func useSource(_ source: WidgetSource, title: String) {
        switch widget.content {
        case .row(var row): row.source = source; widget.content = .row(row)
        case .hero(var row): row.source = source; widget.content = .hero(row)
        case .collection(var tiles):
            tiles.append(CollectionItem(title: title, sources: [source]))
            widget.content = .collection(tiles)
        case .continueWatching, .unsupported: break
        }
        showsSource = false
    }

    private var row: Binding<RowConfiguration> {
        Binding {
            switch widget.content {
            case .row(let row), .hero(let row): return row
            default: return RowConfiguration(source: .unsupported(kind: ""))
            }
        } set: { value in
            if case .hero = widget.content { widget.content = .hero(value) } else { widget.content = .row(value) }
        }
    }

    @ViewBuilder
    private var rowFields: some View {
        Section("Source") {
            Button(model.describe(row.wrappedValue.source)) { showsSource = true }
                .accessibilityIdentifier("widgetEditor.source")
            if row.wrappedValue.source.usesTrakt {
                Text("Trakt lists and feeds need a Trakt client ID in Settings.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if case .row = widget.content {
            Section("Appearance") {
                Picker("Shape", selection: row.presentation.aspectRatio) {
                    ForEach(WidgetPresentation.AspectRatio.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Size", selection: row.presentation.cardStyle) {
                    ForEach(WidgetPresentation.CardStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Show ratings", isOn: row.presentation.showsRatings)
                Toggle("Numbered (top list)", isOn: row.presentation.showsRank)
                    .accessibilityIdentifier("widgetEditor.numbered")
            }
        }
        Section {
            Stepper("Items: \(row.wrappedValue.limit)", value: row.limit, in: 5...100, step: 5)
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
                .buttonStyle(.glass).foregroundStyle(.white)
            }
        }
    }
}
#endif
