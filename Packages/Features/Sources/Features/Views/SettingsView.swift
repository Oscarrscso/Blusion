#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var infuseInstalled = true
    @State private var pendingScope: DataResetService.Scope?
    private let services: AppServices
    let fallbackEngineLinked: Bool

    init(services: AppServices) {
        _model = State(initialValue: SettingsViewModel(services: services))
        self.services = services
        fallbackEngineLinked = services.fallbackEngineLinked
    }

    var body: some View {
        Form {
            Section("Content") {
                NavigationLink(value: SettingsDestination.addons) {
                    HStack {
                        Label("Addons", systemImage: "puzzlepiece.extension")
                        Spacer()
                        Text("\(model.installedAddonCount)").foregroundStyle(.secondary)
                    }
                }
                    .accessibilityIdentifier("settings.addons")
                NavigationLink(value: SettingsDestination.widgets) { Label("Widgets", systemImage: "rectangle.3.group") }
                    .accessibilityIdentifier("settings.widgets")
            }
            playbackSection
            appearanceSection
            reviewServicesSection
            traktSection
            serverSection
            if fallbackEngineLinked { fallbackSection }
            dataSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            if let url = URL(string: "infuse://") { infuseInstalled = UIApplication.shared.canOpenURL(url) }
        }
        .confirmationDialog(pendingScope.map { "Clear \($0.title.lowercased())?" } ?? "",
                            isPresented: Binding(get: { pendingScope != nil }, set: { if !$0 { pendingScope = nil } }),
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
            Picker("Play with", selection: Binding(get: { model.settings.playerPreference }, set: { value in
                Task { await model.setPlayerPreference(value) }
            })) {
                ForEach(PlayerPreference.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings.player")
            if model.settings.playerPreference.externalPlayer != nil && !infuseInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Infuse isn’t installed on this device.").font(.footnote).foregroundStyle(.secondary)
                    if let url = ExternalPlayer.infuse.appStoreURL { Link("Get Infuse", destination: url) }
                }
                .accessibilityIdentifier("settings.player.missing")
            }
            Toggle("Play best stream automatically", isOn: Binding(get: { model.settings.autoPlayBestStream }, set: { value in
                Task { await model.setAutoPlayBestStream(value) }
            }))
            .accessibilityIdentifier("settings.autoPlay")
            Picker("Preferred quality",
                   selection: Binding(get: { model.settings.preferredResolution },
                                      set: { value in Task { await model.setPreferredResolution(value) } })) {
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
            Text("""
                If no stream matches your quality preference, the best available is used. Infuse plays formats Blusion can’t, such as \
                MKV and DTS, and returns your progress when you come back.
                """)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle("Ratings on posters", isOn: Binding(get: { model.settings.showsPosterRatings }, set: { value in
                Task { await model.setShowsPosterRatings(value) }
            }))
            .accessibilityIdentifier("settings.posterRatings")
        }
    }

    private var traktSection: some View {
        Section("Accounts") {
            NavigationLink { TraktAccountView(services: services) } label: { Label("Trakt", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("settings.trakt")
        }
    }

    private var reviewServicesSection: some View {
        Section {
            SecureField("OMDb API key", text: $model.omdbAPIKeyText)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("settings.omdbAPIKey")
            SecureField("TMDB Read Access Token", text: $model.tmdbReadTokenText)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("settings.tmdbReadToken")
            Button("Save Review Services") { Task { await model.commitReviewCredentials() } }
                .accessibilityIdentifier("settings.reviews.save")
            if let url = URL(string: "https://www.omdbapi.com/apikey.aspx") { Link("Get an OMDb key", destination: url) }
            if let url = URL(string: "https://www.themoviedb.org/settings/api") { Link("TMDB API settings", destination: url) }
        } header: {
            Text("Review services")
        } footer: {
            Text("""
                Optional. OMDb adds Rotten Tomatoes and Metacritic scores; TMDB uses a Read Access Token. Credentials stay in the \
                Keychain. Site links work without keys.
                """)
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
            Text("""
                Optional. Torrent and other non-direct streams need a streaming server on your network that you run yourself. Blusion \
                doesn't include one. Leave this empty if you don't use any.
                """)
        }
    }

    private var fallbackSection: some View {
        Section {
            Toggle("Use the fallback player", isOn: Binding(get: { model.settings.fallbackEngineEnabled },
                                    set: { value in Task { await model.setFallbackEngineEnabled(value) } }))
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
            if services.secretsInKeychain {
                Text("Addon links and account credentials are kept in the Keychain. Trakt sync sends only the items you choose to share.")
            } else {
                // A Mac build signed without a provisioning profile: the other screens still say Keychain.
                Text("""
                    This build may not use the Keychain: addon links and account credentials are kept in a private file in your Library \
                    folder instead. Trakt sync sends only the items you choose to share.
                    """)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: SettingsViewModel.appVersion)
            NavigationLink("Acknowledgements") { AcknowledgementsView(fallbackEngineLinked: fallbackEngineLinked) }
                .accessibilityIdentifier("settings.acknowledgements")
            Text("""
                Blusion includes no content or stream sources. Cinemeta provides catalogs and search; you can remove it in Settings › \
                Addons. Blusion isn’t affiliated with any addon or service.
                """)
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
                if item.name == "TMDB" {
                    Image("ReviewTMDB").resizable().scaledToFit()
                        .frame(width: 80, height: 35)
                        .accessibilityLabel("TMDB")
                }
                Text(item.name).font(.headline)
                Text(item.license).font(.subheadline).foregroundStyle(.secondary)
                Text(item.detail).font(.footnote)
                if let url = item.sourceURL { Link("Source", destination: url).font(.footnote) }
            }
            .accessibilityElement(children: .contain)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("acknowledgements.list")
    }
}
#endif
