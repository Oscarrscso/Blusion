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
    /// True while the toolbar's button has hidden every widget's row, leaving one line that says how many there are. Kept between
    /// visits, so a long list stays out of the way until it is shown again.
    @AppStorage("widgets.hidesRows") private var hidesWidgets = false
    @Environment(\.editMode) private var editMode

    init(services: AppServices) {
        self.services = services
        _model = State(initialValue: WidgetsManagerViewModel(services: services))
    }

    /// The plus: a menu of the widgets that can be added.
    private var addMenu: some View {
        // Adding a widget shows the rows, so the new one is not hidden with the rest.
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

    /// The wrench: turns reordering and deleting on and off, in place of the Edit text button.
    private var editToggle: some View {
        let isEditing = editMode?.wrappedValue.isEditing == true
        return Button {
            withAnimation {
                // Reordering and deleting need the rows, so editing shows them.
                if !isEditing { hidesWidgets = false }
                editMode?.wrappedValue = isEditing ? .inactive : .active
            }
        } label: {
            Image(systemName: isEditing ? "wrench.adjustable.fill" : "wrench.adjustable")
        }
        .accessibilityLabel(isEditing ? "Done Editing" : "Edit Widgets")
        .help(isEditing ? "Done Editing" : "Edit Widgets")
        .accessibilityIdentifier("widgets.edit")
    }

    /// Hides every widget's row at once, or shows them all again. The rows themselves go, not just the settings each one drops down.
    private var hideToggle: some View {
        Button {
            withAnimation { setWidgetsHidden(!hidesWidgets) }
        } label: {
            Image(systemName: hidesWidgets ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
        }
        .disabled(model.widgets.isEmpty)
        .accessibilityLabel(hidesWidgets ? "Show All Widgets" : "Hide All Widgets")
        .help(hidesWidgets ? "Show All Widgets" : "Hide All Widgets")
        .accessibilityIdentifier("widgets.hideAll")
    }

    /// Hidden rows cannot be reordered or deleted, so hiding them ends editing.
    private func setWidgetsHidden(_ hidden: Bool) {
        hidesWidgets = hidden
        if hidden { editMode?.wrappedValue = .inactive }
    }

    /// The one line that stands in for the rows while they are hidden. A tap shows them again.
    private var hiddenRowsLine: some View {
        Button {
            withAnimation { setWidgetsHidden(false) }
        } label: {
            Label(model.widgets.count == 1 ? "1 widget hidden" : "\(model.widgets.count) widgets hidden", systemImage: "eye.slash")
        }
        .accessibilityHint("Shows the widgets")
        .accessibilityIdentifier("widgets.hiddenRows")
    }

    var body: some View {
        List {
            Section {
                if hidesWidgets && !model.widgets.isEmpty { hiddenRowsLine }
                ForEach(hidesWidgets ? [] : model.widgets) { widget in
                    // A row drops down in place to show every setting of its widget, and its Edit Widget link sits at the foot of them.
                    DisclosureGroup {
                        ForEach(model.details(of: widget)) { detail in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(detail.label)
                                Spacer(minLength: 8)
                                Text(detail.value)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                            .accessibilityIdentifier("widgets.detail.\(widget.id).\(detail.id)")
                        }
                        NavigationLink(value: widget) {
                            Label("Edit Widget", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("widgets.edit.\(widget.id)")
                    } label: {
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
                    #if targetEnvironment(macCatalyst)
                    .contextMenu {
                        Button(role: .destructive) { Task { await model.remove(id: widget.id) } } label: { Label("Delete", systemImage: "trash") }
                            .accessibilityIdentifier("widgets.menu.delete.\(widget.id)")
                    }
                    #endif
                }
                .onDelete { offsets in Task { await model.remove(atOffsets: offsets) } }
                .onMove { offsets, destination in Task { await model.move(fromOffsets: offsets, toOffset: destination) } }
            } header: {
                Text("Home rows")
            } footer: {
                Text(model.isCustomised ? "Your own layout." : "Home follows your addons. Change anything here to make it yours.")
            }
            .accessibilityIdentifier("widgets.list")
            if model.catalogChoices.isEmpty {
                Section {
                    Text("Install an addon with catalogs, or use a Trakt list, to add more rows.").font(.footnote).foregroundStyle(.secondary)
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
        .readableColumn()
        .screenBackground()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("widgets.manager")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { hideToggle }
            ToolbarItem(placement: .topBarTrailing) { addMenu }
            ToolbarItem(placement: .topBarTrailing) { editToggle }
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

    private func symbol(for widget: HomeWidget) -> String {
        switch widget.content {
        case .hero: "sparkles.tv"
        case .banner: "rectangle.topthird.inset.filled"
        case .row: "rectangle.stack"
        case .collection: "square.grid.2x2"
        case .continueWatching: "play.circle"
        case .unsupported: "questionmark.square.dashed"
        }
    }
}

/// A screen pushed to make a new widget.
private enum NewWidgetRoute: Hashable, Identifiable {
    case widget
    var id: Self { self }
}
#endif
