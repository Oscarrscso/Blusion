#if canImport(UIKit)
import StremioKit
import SwiftUI

struct WidgetsManagerView: View {
    let services: AppServices
    @State private var model: WidgetsManagerViewModel
    @State private var adding: WidgetKind?
    @State private var showsImport = false
    @State private var showsReset = false
    @State private var showsPendingImport = false
    @State private var copied = false

    init(services: AppServices) {
        self.services = services
        _model = State(initialValue: WidgetsManagerViewModel(services: services))
    }

    var body: some View {
        List {
            Section {
                ForEach(model.widgets) { widget in
                    NavigationLink(value: widget) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(widget.title.isEmpty ? "Untitled" : widget.title)
                                Text(model.summary(of: widget)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: symbol(for: widget))
                        }
                    }
                    .accessibilityIdentifier("widgets.row.\(widget.id)")
                }
                .onDelete { offsets in Task { await model.remove(atOffsets: offsets) } }
                .onMove { offsets, destination in Task { await model.move(fromOffsets: offsets, toOffset: destination) } }
            } header: {
                Text("Home rows")
            } footer: {
                Text(model.isCustomised ? "Your own layout." : "Home follows your addons. Change anything here to make it yours.")
            }
            .accessibilityIdentifier("widgets.list")
            Section("Add") {
                Menu("Add Widget", systemImage: "plus") {
                    ForEach(WidgetKind.allCases) { kind in
                        Button(kind.rawValue) { adding = kind }
                            .disabled(model.catalogChoices.isEmpty || (kind == .collection && model.catalogChoices.allSatisfy { $0.genres.isEmpty }))
                    }
                    Button("Continue Watching") {
                        Task { await model.add(HomeWidget(title: "Continue Watching", content: .continueWatching)) }
                    }
                    .disabled(model.widgets.contains { $0.content == .continueWatching })
                }
                .accessibilityIdentifier("widgets.add")
                if model.catalogChoices.isEmpty {
                    Text("Install an addon with catalogs to add more rows.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Import & export") {
                Button("Import Widgets…") { showsImport = true }.accessibilityIdentifier("widgets.import")
                Button(copied ? "Copied" : "Copy as JSON") {
                    UIPasteboard.general.string = model.exportJSON()
                    copied = true
                }
                .accessibilityIdentifier("widgets.export")
                if let text = model.exportJSON() { ShareLink("Share JSON", item: text) }
            }
            if model.isCustomised {
                Section {
                    Button("Use Automatic Layout", role: .destructive) { showsReset = true }
                        .accessibilityIdentifier("widgets.reset")
                }
            }
            if let message = model.message {
                Text(message).font(.footnote).foregroundStyle(model.messageIsError ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("widgets.message")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("widgets.manager")
        .toolbar { EditButton().buttonStyle(.glass).foregroundStyle(.white) }
        .task { await model.load() }
        .navigationDestination(for: HomeWidget.self) { WidgetEditorView(widget: $0, model: model) }
        .sheet(item: $adding) { kind in
            NavigationStack {
                WidgetSourcePicker(model: model, genresOnly: kind == .collection) { choice, genre in
                    let widget: HomeWidget
                    switch kind {
                    case .row: widget = WidgetsManagerViewModel.makeRow(title: choice.title, choice: choice, genre: genre)
                    case .spotlight: widget = WidgetsManagerViewModel.makeHero(choice: choice, genre: genre)
                    case .collection: widget = WidgetsManagerViewModel.makeGenreCollection(title: "Genres", choice: choice)
                    }
                    Task { await model.add(widget) }
                    adding = nil
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
        .disabled(model.isWorking)
    }

    private func symbol(for widget: HomeWidget) -> String {
        switch widget.content {
        case .hero: "sparkles.tv"
        case .row: "rectangle.stack"
        case .collection: "square.grid.2x2"
        case .continueWatching: "play.circle"
        }
    }
}

private enum WidgetKind: String, CaseIterable, Identifiable {
    case row = "Catalog Row", spotlight = "Spotlight", collection = "Genre Collection"
    var id: String { rawValue }
}
#endif
