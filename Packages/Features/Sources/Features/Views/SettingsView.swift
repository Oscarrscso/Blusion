#if canImport(SwiftUI)
import SwiftUI
import StremioKit

struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var pendingScope: DataResetService.Scope?
    let fallbackEngineLinked: Bool

    init(services: AppServices) {
        _model = State(initialValue: SettingsViewModel(services: services))
        fallbackEngineLinked = services.fallbackEngineLinked
    }

    var body: some View {
        Form {
            playbackSection
            serverSection
            if fallbackEngineLinked { fallbackSection }
            dataSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .confirmationDialog(pendingScope.map { "Clear \($0.title.lowercased())?" } ?? "", isPresented: Binding(get: { pendingScope != nil }, set: { if !$0 { pendingScope = nil } }),
                            titleVisibility: .visible, presenting: pendingScope) { scope in
            Button("Clear \(scope.title.lowercased())", role: .destructive) { Task { await model.clear(scope) } }
                .accessibilityIdentifier("settings.confirmClear")
            Button("Cancel", role: .cancel) {}
        } message: { scope in
            Text(scope.warning)
        }
        .accessibilityIdentifier("settings.form")
    }

    private var playbackSection: some View {
        Section {
            Picker("Preferred quality", selection: Binding(get: { model.settings.preferredResolution }, set: { value in Task { await model.setPreferredResolution(value) } })) {
                ForEach(SettingsViewModel.resolutionOptions) { Text($0.label).tag($0.value) }
            }
            .accessibilityIdentifier("settings.resolution")
            Picker("Subtitles", selection: Binding(get: { model.settings.subtitleLanguage }, set: { value in Task { await model.setSubtitleLanguage(value) } })) {
                ForEach(SettingsViewModel.languageOptions) { Text($0.label).tag($0.value) }
            }
            .accessibilityIdentifier("settings.subtitleLanguage")
        } header: {
            Text("Playback")
        } footer: {
            Text("Quality is a preference, not a rule: if nothing matches, the best available stream is used. Subtitles turn on by themselves when an addon has them in your language.")
        }
    }

    private var serverSection: some View {
        Section {
            TextField("http://192.168.1.10:11470", text: $model.serverURLText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.done)
                .onSubmit { Task { await model.commitServerURL() } }
                .accessibilityLabel("Streaming server address")
                .accessibilityIdentifier("settings.serverURL")
            if let message = model.serverURLMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.serverURL.message")
            }
            Button("Save address") { Task { await model.commitServerURL() } }
                .disabled(model.serverURLMessage != nil)
                .accessibilityIdentifier("settings.serverURL.save")
        } header: {
            Text("Streaming server")
        } footer: {
            Text("Optional. Torrent and other non-direct streams need a streaming server on your network that you run yourself. Blusion doesn't include one. Leave this empty if you don't use any.")
        }
    }

    private var fallbackSection: some View {
        Section {
            Toggle("Use the fallback player", isOn: Binding(get: { model.settings.fallbackEngineEnabled }, set: { value in Task { await model.setFallbackEngineEnabled(value) } }))
                .accessibilityIdentifier("settings.fallbackToggle")
        } header: {
            Text("Fallback player")
        } footer: {
            Text("Plays formats the system player can't, such as MKV and some audio tracks. Turn it off to use only the system player.")
        }
    }

    private var dataSection: some View {
        Section {
            ForEach(DataResetService.Scope.allCases, id: \.self) { scope in
                Button(scope.title, role: .destructive) { pendingScope = scope }
                    .accessibilityIdentifier("settings.clear.\(String(describing: scope))")
            }
            if let message = model.lastMessage {
                Label(message, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.clearMessage")
            }
        } header: {
            Text("Clear data")
        } footer: {
            Text("Everything Blusion knows stays on this device. Addon links are kept in the Keychain and are removed with their addon.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: SettingsViewModel.appVersion)
            NavigationLink("Acknowledgements") { AcknowledgementsView(fallbackEngineLinked: fallbackEngineLinked) }
                .accessibilityIdentifier("settings.acknowledgements")
            Text("Blusion is a player for content you have the right to watch. It includes no content and no addons, and it isn't affiliated with any addon or service.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct AcknowledgementsView: View {
    let fallbackEngineLinked: Bool

    var body: some View {
        List(Acknowledgement.all(fallbackEngineLinked: fallbackEngineLinked)) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline)
                Text(item.license).font(.subheadline).foregroundStyle(.secondary)
                Text(item.detail).font(.footnote)
                if let url = item.sourceURL { Link("Source", destination: url).font(.footnote) }
            }
            .accessibilityElement(children: .contain)
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("acknowledgements.list")
    }
}

/// The gear that opens Settings as a sheet from any tab.
struct SettingsButton: ViewModifier {
    let services: AppServices
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowing = true } label: { Label("Settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("settings.open")
                }
            }
            .sheet(isPresented: $isShowing) {
                NavigationStack {
                    SettingsView(services: services)
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { isShowing = false }.accessibilityIdentifier("settings.done") } }
                }
            }
    }
}

extension View {
    func settingsButton(services: AppServices) -> some View {
        modifier(SettingsButton(services: services))
    }
}
#endif
