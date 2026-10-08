#if canImport(UIKit)
import SwiftUI
import AuthenticationServices
import StremioKit

struct TraktAccountView: View {
    @State private var model: TraktAccountViewModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openURL) private var openURL

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
            TextField("Redirect URI", text: $model.redirectURIText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("trakt.redirectURI")
            Button("Save connection settings") { Task { await model.saveCredentials() } }
                .accessibilityIdentifier("settings.traktClientID.save")
            if let url = URL(string: "https://app.trakt.tv/oauth/applications") {
                Link("Trakt app settings", destination: url).accessibilityIdentifier("trakt.apiApp")
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("PKCE sign-in needs no Client Secret. Enter the exact Redirect URI from your Trakt app settings. The blusion://trakt/callback URI returns directly to this app when registered. Other callbacks can be pasted below after authorization. Sign-in tokens are stored in the Keychain.")
        }
        .disabled(model.authorizationURL != nil)
    }

    private var accountSection: some View {
        Section("Account") {
            if model.isSignedIn {
                Label("Signed in", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("trakt.signedIn")
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                    .accessibilityIdentifier("trakt.signOut")
            } else if let url = model.authorizationURL {
                Link("Open Trakt to authorize", destination: url)
                    .accessibilityIdentifier("trakt.authorize")
                if model.redirectURIText == "urn:ietf:wg:oauth:2.0:oob" {
                    SecureField("Authorization code from Trakt", text: $model.authorizationCodeText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    Text("After allowing access, copy the redirected address from your browser and paste it here.")
                        .foregroundStyle(.secondary)
                    SecureField("Redirect URL", text: $model.authorizationCodeText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Finish connecting") { Task { await model.finishPastedSignIn() } }
                    .disabled(model.authorizationCodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("trakt.finishSignIn")
                Button("Cancel", role: .cancel) { model.cancelSignIn() }
                    .accessibilityIdentifier("trakt.cancel")
            } else {
                Button("Connect Trakt") { Task { await signIn() } }
                    .disabled(!model.canSignIn)
                    .accessibilityIdentifier("trakt.signIn")
            }
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Watchlist", isOn: $model.syncWatchlist).accessibilityIdentifier("trakt.syncWatchlist")
            Toggle("Collection / library", isOn: $model.syncCollection).accessibilityIdentifier("trakt.syncCollection")
            Toggle("Watched movies and episodes", isOn: $model.syncHistory).accessibilityIdentifier("trakt.syncHistory")
            Button("Refresh from Trakt") { Task { await model.importFromTrakt() } }
                .disabled(!model.syncWatchlist && !model.syncCollection && !model.syncHistory)
                .accessibilityIdentifier("trakt.import")
        } header: {
            Text("Your Trakt library")
        } footer: {
            Text("Your watchlist (watch later) and collection appear in Library → Saved. Watched history appears in Library → Watched. Connecting imports these automatically; Refresh adds newly saved titles without deleting local items. Only titles with IMDb IDs can import; playback positions stay on this device.")
        }
    }

    private func signIn() async {
        await model.startPKCESignIn()
        guard let url = model.authorizationURL else { return }
        let redirectURI = model.redirectURIText.trimmingCharacters(in: .whitespacesAndNewlines)
        // The existing blusion scheme supports a native return. Other registered callbacks use paste.
        guard URL(string: redirectURI)?.scheme == "blusion" else {
            openURL(url)
            return
        }
        do {
            let callback = try await TraktWebAuthentication.authenticate(using: webAuthenticationSession, url: url, redirectURI: redirectURI)
            await model.finishPKCESignIn(callbackURL: callback)
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin || Task.isCancelled {
                model.cancelSignIn()
            } else {
                model.authenticationFailed(error)
            }
        }
    }
}
#endif
