#if canImport(UIKit)
import StremioKit
import SwiftUI
import UniformTypeIdentifiers

private struct SettingsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsBackupControls: View {
    let services: AppServices
    let model: SettingsViewModel
    @State private var document = SettingsBackupDocument(data: Data())
    @State private var exports = false
    @State private var imports = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Section {
            Button("Export Settings", systemImage: "square.and.arrow.up") {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        document = SettingsBackupDocument(data: try SettingsBackup.export(
                            settings: await services.settings.load(), widgets: await services.widgets.load(),
                            shuffle: await services.widgetShuffle.settings()))
                        exports = true
                    } catch { message = error.localizedDescription }
                }
            }
            Button("Import Settings", systemImage: "square.and.arrow.down") { imports = true }
        }
        #if targetEnvironment(macCatalyst)
        .buttonStyle(.settingsHover)
        #else
        .buttonStyle(.hoverPlain)
        #endif
        .disabled(isWorking)
        .fileExporter(isPresented: $exports, document: document, contentType: .json, defaultFilename: "Blusion Settings") { result in
            switch result {
            case .success: message = "Settings exported."
            case .failure(let error): message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $imports, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await importSettings(from: url) }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .alert("Settings", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func importSettings(from url: URL) async {
        isWorking = true
        defer { isWorking = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let imported = try SettingsBackup.decode(data, current: await services.settings.load())
            let restored = imported.settings
            _ = await services.settings.update { settings in
                var value = restored
                value.streamingServerURL = settings.streamingServerURL
                value.traktClientID = settings.traktClientID
                value.omdbAPIKey = settings.omdbAPIKey
                value.tmdbReadToken = settings.tmdbReadToken
                value.openSubtitlesAPIKey = settings.openSubtitlesAPIKey
                value.openSubtitlesUsername = settings.openSubtitlesUsername
                value.openSubtitlesPassword = settings.openSubtitlesPassword
                settings = value
            }
            if let appearance = imported.appearance { UserDefaults.standard.set(appearance.rawValue, forKey: AppearancePreferences.defaultsKey) }
            for (key, value) in imported.general { UserDefaults.standard.set(value, forKey: key) }
            if imported.includesWidgets { await services.widgets.save(imported.widgets) }
            if let shuffle = imported.shuffle { await services.widgetShuffle.save(shuffle) }
            await model.load()
            message = imported.skipped == 0 ? "Settings imported." : "Settings imported. Skipped \(imported.skipped) unsupported entries."
        } catch { message = "Could not import settings. \(error.localizedDescription)" }
    }
}
#endif
