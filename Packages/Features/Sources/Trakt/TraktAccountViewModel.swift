import Foundation
import Observation
import PlayerKit
import StremioKit

/// Two-way syncing that runs by itself. The buttons here force a full sync, which reads everything from Trakt and applies every removal.
/// Trakt uses the app's built-in client ID and PKCE.
@MainActor
@Observable
final class TraktAccountViewModel {
    /// The redirect registered for the Trakt app. Blusion receives it natively through the web authentication session.
    static let redirectURI = "blusion://trakt/callback"

    private(set) var isSignedIn = false
    private(set) var isWorking = false
    private(set) var authorizationURL: URL?
    private(set) var message: String?
    private(set) var errorMessage: String?
    /// Changes still waiting to reach Trakt.
    private(set) var pendingCount = 0
    private(set) var clientIDConfigured = false

    private let services: AppServices

    init(services: AppServices) { self.services = services }

    /// Account settings remain available even when no API client ID has been configured.
    var isAvailable: Bool { true }

    var canSignIn: Bool { clientIDConfigured }

    func load() async {
        let stored = await services.settings.load()
        clientIDConfigured = !(stored.traktClientID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isSignedIn = await services.traktAccount.isSignedIn()
        pendingCount = await services.traktSync.pendingCount()
    }

    func startPKCESignIn() async {
        guard canSignIn else {
            errorMessage = "This build has no Trakt client ID."
            return
        }
        #if canImport(CryptoKit)
        await perform {
            let proof = TraktWebAuthentication.proof()
            self.authorizationURL = try await self.services.traktAccount.beginPKCESignIn(
                redirectURI: Self.redirectURI, codeVerifier: proof.verifier, codeChallenge: proof.challenge)
            self.message = nil
        }
        #endif
    }

    func finishPKCESignIn(callbackURL: URL) async {
        await perform {
            try await self.services.traktAccount.finishPKCESignIn(callbackURL: callbackURL)
            await self.services.trakt.clearCache()
            await self.services.widgetContent.forgetEverything()
            self.isSignedIn = true
            self.authorizationURL = nil
        }
        if isSignedIn, errorMessage == nil { await importFromTrakt() }
    }

    func authenticationFailed(_ error: Error) {
        cancelSignIn()
        errorMessage = "Couldn’t open Trakt sign-in. Try again."
    }

    func cancelSignIn() {
        authorizationURL = nil
        Task { await services.traktAccount.cancelPKCESignIn() }
    }

    func signOut() async {
        authorizationURL = nil
        await perform {
            guard await self.services.traktAccount.signOut() else {
                self.errorMessage = "Couldn’t remove the Trakt sign-in from secure storage. Try Disconnect again."
                return
            }
            await self.services.traktSync.signedOut()
            await self.services.trakt.clearCache()
            await self.services.widgetContent.forgetEverything()
            self.isSignedIn = false
            self.message = "Disconnected from Trakt. Your local library and history are kept."
        }
    }

    /// Forces a full sync: reads everything from Trakt and applies it here, removals included, so a title or mark that left Trakt leaves
    /// this device too.
    func importFromTrakt() async {
        guard canSync() else { return }
        await perform {
            let summary = try await self.services.traktSync.sync(force: true)
            self.message = GhostMode.isOn ? "Paused by Ghost Mode" : Self.syncMessage(summary)
        }
    }

    /// Forces a full sync that also sends the saved titles and watched marks here that Trakt does not have yet. What Trakt removed is
    /// removed here too, as in an import.
    func sendToTrakt() async {
        guard canSync() else { return }
        await perform {
            let summary = try await self.services.traktSync.sync(force: true, sendingLocalOnly: true)
            self.message = GhostMode.isOn ? "Paused by Ghost Mode" : Self.syncMessage(summary)
        }
    }

    /// Forces a full sync that sends local items to Trakt and reads Trakt back, in one pass.
    func sync() async {
        guard canSync() else { return }
        await perform {
            let summary = try await self.services.traktSync.sync(force: true, sendingLocalOnly: true)
            self.message = GhostMode.isOn ? "Paused by Ghost Mode" : Self.syncMessage(summary)
        }
    }

    private func canSync() -> Bool {
        guard !GhostMode.isOn else {
            errorMessage = nil
            message = "Paused by Ghost Mode"
            return false
        }
        return true
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        message = nil
        defer { isWorking = false }
        do { try await operation() } catch { errorMessage = Self.message(for: error) }
        pendingCount = await services.traktSync.pendingCount()
    }

    /// Include uploads even when no local data changed. Sent counts include additions and removals.
    private static func syncMessage(_ summary: TraktSync.Summary) -> String {
        var text = "Sent \(summary.savedSent) saved-title changes and \(summary.watchedSent) watch-history changes to Trakt."
        text += " Received \(summary.savedAdded) saved titles and \(summary.watchedAdded) watched items."
        text += " Removed \(summary.savedRemoved) saved titles and \(summary.watchedRemoved) watched marks locally."
        if summary.playbackSent + summary.playbackRemoved > 0 {
            text += " Sent \(summary.playbackSent) playback positions and removed \(summary.playbackRemoved) paused records on Trakt."
        }
        return text
    }

    private static func message(for error: Error) -> String {
        (error as? TraktAccountError)?.message ?? "Couldn’t save or sync your Trakt account. Try again."
    }
}
