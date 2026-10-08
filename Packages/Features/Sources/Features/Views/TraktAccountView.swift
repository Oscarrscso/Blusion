#if canImport(UIKit)
import SwiftUI
import StremioKit

struct TraktAccountView: View {
    @State private var model: TraktAccountViewModel

    init(services: AppServices) { _model = State(initialValue: TraktAccountViewModel(services: services)) }

    var body: some View {
        Form {
            credentialsSection
            accountSection
            if model.isSignedIn { syncSection }
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(.secondary).accessibilityIdentifier("trakt.error") }
            }
            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("trakt.message") }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Trakt")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .task(id: model.deviceCode?.deviceCode) { await model.pollForSignIn() }
        .onDisappear { model.cancelSignIn() }
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView().padding().glassEffect() } }
        .accessibilityIdentifier("trakt.form")
    }

    private var credentialsSection: some View {
        Section {
            TextField("Client ID", text: $model.clientIDText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.traktClientID")
            SecureField("Client Secret", text: $model.clientSecretText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("trakt.clientSecret")
            Button("Save credentials") { Task { await model.saveCredentials() } }
                .accessibilityIdentifier("settings.traktClientID.save")
            if let url = URL(string: "https://trakt.tv/oauth/applications") {
                Link("Create a Trakt API app", destination: url).accessibilityIdentifier("trakt.apiApp")
            }
        } header: {
            Text("Your API app")
        } footer: {
            Text("Enter your own API Client ID and Client Secret. Set your API app’s Redirect URI to urn:ietf:wg:oauth:2.0:oob so token refresh works. Credentials and sign-in tokens are stored in the Keychain. A Client ID alone also enables public Trakt list widgets.")
        }
        .disabled(model.deviceCode != nil)
    }

    private var accountSection: some View {
        Section("Account") {
            if model.isSignedIn {
                Label("Signed in", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("trakt.signedIn")
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                    .accessibilityIdentifier("trakt.signOut")
            } else if let code = model.deviceCode {
                Text("Enter this code on Trakt:").foregroundStyle(.secondary)
                Text(code.userCode).font(.title2.monospaced().bold()).textSelection(.enabled)
                    .accessibilityIdentifier("trakt.userCode")
                Link("Open Trakt to authorize", destination: code.verificationURL)
                    .accessibilityIdentifier("trakt.authorize")
                HStack { ProgressView(); Text("Waiting for authorization…").foregroundStyle(.secondary) }
                Button("Cancel", role: .cancel) { model.cancelSignIn() }
                    .accessibilityIdentifier("trakt.cancel")
            } else {
                Button("Sign in to Trakt") { Task { await model.startSignIn() } }
                    .disabled(!model.canSignIn)
                    .accessibilityIdentifier("trakt.signIn")
            }
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Watchlist", isOn: $model.syncWatchlist).accessibilityIdentifier("trakt.syncWatchlist")
            Toggle("Watched movies and episodes", isOn: $model.syncHistory).accessibilityIdentifier("trakt.syncHistory")
            Button("Import from Trakt") { Task { await model.importFromTrakt() } }
                .disabled(!model.syncWatchlist && !model.syncHistory)
                .accessibilityIdentifier("trakt.import")
            Button("Send to Trakt") { Task { await model.sendToTrakt() } }
                .disabled(!model.syncWatchlist && !model.syncHistory)
                .accessibilityIdentifier("trakt.export")
        } header: {
            Text("Manual sync")
        } footer: {
            Text("Adds missing items without deleting anything. Import puts your watchlist in Library and marks watched items. Send shares saved titles and watched marks with Trakt. Only titles with IMDb IDs can sync; playback positions stay on this device.")
        }
    }
}
#endif
