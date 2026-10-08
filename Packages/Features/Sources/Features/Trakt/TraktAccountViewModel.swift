import Foundation
import Observation
import PlayerKit
import StremioKit

/// Explicit, add-only syncing. Local playback positions stay on this device.
/// The Trakt app's client ID is built in (`TraktAccount.defaultClientID`); sign-in uses PKCE, so no secret is needed.
@MainActor
@Observable
public final class TraktAccountViewModel {
    /// The redirect registered for the Trakt app. Blusion receives it natively through the web authentication session.
    public static let redirectURI = "blusion://trakt/callback"

    public private(set) var isSignedIn = false
    public private(set) var isWorking = false
    public private(set) var authorizationURL: URL?
    public private(set) var message: String?
    public private(set) var errorMessage: String?

    private let services: AppServices

    public init(services: AppServices) { self.services = services }

    /// False only when no client ID is built in. The screen then shows "Trakt unavailable".
    public var isAvailable: Bool { !TraktAccount.defaultClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var canSignIn: Bool { isAvailable }

    public func load() async {
        await ensureClientID()
        isSignedIn = await services.traktAccount.isSignedIn()
    }

    /// Stores the built-in client ID. A client ID from an earlier build differs from it, so its sign-in is cleared first.
    private func ensureClientID() async {
        guard isAvailable else { return }
        let clientID = TraktAccount.defaultClientID
        let stored = await services.settings.load()
        guard stored.traktClientID != clientID else { return }
        if stored.traktClientID != nil { await services.traktAccount.signOut() }
        var settings = await services.settings.load()
        settings.traktClientID = clientID
        await services.settings.save(settings)
        await services.widgetContent.invalidate()
    }

    public func startPKCESignIn() async {
        guard isAvailable else { return }
        await ensureClientID()
        #if canImport(CryptoKit)
        await perform {
            let proof = TraktWebAuthentication.proof()
            self.authorizationURL = try await self.services.traktAccount.beginPKCESignIn(
                redirectURI: Self.redirectURI, codeVerifier: proof.verifier, codeChallenge: proof.challenge)
            self.message = nil
        }
        #endif
    }

    public func finishPKCESignIn(callbackURL: URL) async {
        await perform {
            try await self.services.traktAccount.finishPKCESignIn(callbackURL: callbackURL)
            self.isSignedIn = true
            self.authorizationURL = nil
        }
        if isSignedIn, errorMessage == nil { await importFromTrakt() }
    }

    public func authenticationFailed(_ error: Error) {
        cancelSignIn()
        errorMessage = "Couldn’t open Trakt sign-in. Try again."
    }

    public func cancelSignIn() {
        authorizationURL = nil
        Task { await services.traktAccount.cancelPKCESignIn() }
    }

    public func signOut() async {
        authorizationURL = nil
        await perform {
            await self.services.traktAccount.signOut()
            self.isSignedIn = false
            self.message = "Disconnected from Trakt. Your local library and history are kept."
        }
    }

    /// Adds the Trakt watchlist, collection and watched history to this device.
    public func importFromTrakt() async {
        await perform {
            var savedCount = 0
            var watchedCount = 0
            let watchlist = try await self.services.traktAccount.watchlist()
            let collection = try await self.services.traktAccount.collection()
            let watched = try await self.services.traktAccount.watched()
            for item in watchlist + collection {
                let libraryItem = LibraryItem(preview: item)
                if !(await self.services.library.contains(libraryItem.id)) {
                    await self.services.library.add(libraryItem)
                    savedCount += 1
                }
            }
            for item in watched {
                guard await self.services.progress.progress(for: item.identity)?.isWatched != true else { continue }
                let existing = await self.services.progress.progress(for: item.identity)
                await self.services.progress.save(WatchProgress(id: item.identity, type: item.preview.type, contentID: item.contentID,
                    title: existing?.title ?? item.preview.name, poster: existing?.poster ?? item.preview.poster,
                    position: existing?.position ?? 0, duration: existing?.duration ?? 0, isWatched: true,
                    updatedAt: max(existing?.updatedAt ?? .distantPast, item.watchedAt), season: item.season, episode: item.episode))
                watchedCount += 1
            }
            self.message = "Imported \(savedCount) saved titles and \(watchedCount) watched items from Trakt."
        }
    }

    /// Adds local saved titles and watched items that Trakt does not have yet. Nothing is removed on either side.
    public func sendToTrakt() async {
        await perform {
            let remoteWatchlist = Set(try await self.services.traktAccount.watchlist().map { LibraryItem.identity(type: $0.type, contentID: $0.id) })
            let localWatchlist = await self.services.library.all().filter { !remoteWatchlist.contains($0.id) }.map(\.preview)
            let savedCount = try await self.services.traktAccount.addToWatchlist(localWatchlist)
            let remoteHistory = Set(try await self.services.traktAccount.watched().map(\.identity))
            let localHistory = await self.services.progress.all().filter { $0.isWatched && !remoteHistory.contains($0.id) }.compactMap(Self.traktItem)
            let watchedCount = try await self.services.traktAccount.addToHistory(localHistory)
            self.message = "Sent \(savedCount) saved titles and \(watchedCount) watched items to Trakt."
        }
    }

    /// Sends local items to Trakt, then imports Trakt's collection and history.
    public func sync() async {
        await sendToTrakt()
        guard errorMessage == nil else { return }
        await importFromTrakt()
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        message = nil
        defer { isWorking = false }
        do { try await operation() } catch { errorMessage = Self.message(for: error) }
    }

    private static func traktItem(_ progress: WatchProgress) -> TraktWatchedItem? {
        let id = progress.type == "series" ? ContentID(progress.contentID).baseID : progress.contentID
        guard TraktAccount.isIMDb(id), progress.type == "movie" || (progress.type == "series" && progress.season != nil && progress.episode != nil) else {
            return nil
        }
        return TraktWatchedItem(preview: MetaPreview(id: id, type: progress.type, name: progress.title, poster: progress.poster),
                                watchedAt: progress.updatedAt, season: progress.season, episode: progress.episode)
    }

    private static func message(for error: Error) -> String {
        (error as? TraktAccountError)?.message ?? "Couldn’t save or sync your Trakt account. Try again."
    }
}
