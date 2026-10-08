#if canImport(UIKit)
import SwiftUI
import AuthenticationServices
import StremioKit

struct TraktAccountView: View {
    @State private var model: TraktAccountViewModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    init(services: AppServices) { _model = State(initialValue: TraktAccountViewModel(services: services)) }

    var body: some View {
        Form {
            if model.isAvailable {
                accountSection
                if model.isSignedIn { syncSection }
            } else {
                Section {
                    Text("Trakt unavailable").foregroundStyle(.secondary).accessibilityIdentifier("trakt.unavailable")
                }
            }
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

    private var accountSection: some View {
        Section {
            if model.isSignedIn {
                Label("Connected", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("trakt.signedIn")
                Button("Disconnect", role: .destructive) { Task { await model.signOut() } }
                    .accessibilityIdentifier("trakt.signOut")
            } else {
                Button("Connect") { Task { await signIn() } }
                    .disabled(!model.canSignIn)
                    .accessibilityIdentifier("trakt.signIn")
            }
        } header: {
            Text("Account")
        } footer: {
            if !model.isSignedIn {
                Text("Connect to import your Trakt watchlist, collection and watched history. Playback positions stay on this device.")
            }
        }
    }

    private var syncSection: some View {
        Section {
            Button("Sync") { Task { await model.sync() } }
                .accessibilityIdentifier("trakt.sync")
            Button("Import collection") { Task { await model.importFromTrakt() } }
                .accessibilityIdentifier("trakt.import")
        } header: {
            Text("Your Trakt library")
        } footer: {
            Text("Sync sends your saved titles and watched items to Trakt, then imports Trakt’s collection. Your watchlist and collection appear in Library → Saved; watched history appears in Library → Watched. Nothing is removed.")
        }
    }

    private func signIn() async {
        await model.startPKCESignIn()
        guard let url = model.authorizationURL else { return }
        do {
            let callback = try await TraktWebAuthentication.authenticate(using: webAuthenticationSession, url: url,
                                                                        redirectURI: TraktAccountViewModel.redirectURI)
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
