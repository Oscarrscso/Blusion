import Foundation
import Observation
import PlayerKit
import StremioKit

/// Explicit, add-only syncing. Local playback positions stay on this device.
@MainActor
@Observable
public final class TraktAccountViewModel {
    public var clientIDText = ""
    public var clientSecretText = ""
    public var syncWatchlist = true
    public var syncHistory = true
    public private(set) var isSignedIn = false
    public private(set) var isWorking = false
    public private(set) var deviceCode: TraktDeviceCode?
    public private(set) var message: String?
    public private(set) var errorMessage: String?

    private let services: AppServices

    public init(services: AppServices) { self.services = services }

    public var canSignIn: Bool {
        !clientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecretText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func load() async {
        clientIDText = await services.settings.load().traktClientID ?? ""
        clientSecretText = await services.traktAccount.clientSecret()
        isSignedIn = await services.traktAccount.isSignedIn()
    }

    public func saveCredentials() async {
        await perform {
            var settings = await self.services.settings.load()
            let clientID = self.clientIDText.trimmingCharacters(in: .whitespacesAndNewlines)
            if settings.traktClientID != clientID {
                await self.services.traktAccount.signOut()
            }
            settings.traktClientID = clientID.isEmpty ? nil : clientID
            await self.services.settings.save(settings)
            try await self.services.traktAccount.saveClientSecret(self.clientSecretText)
            self.isSignedIn = await self.services.traktAccount.isSignedIn()
            await self.services.widgetContent.invalidate()
            self.message = "Trakt credentials saved in the Keychain."
        }
    }

    public func startSignIn() async {
        await saveCredentials()
        guard errorMessage == nil else { return }
        await perform {
            self.deviceCode = try await self.services.traktAccount.beginSignIn()
            self.message = nil
        }
    }

    /// SwiftUI owns and cancels the polling task when this screen or code disappears.
    public func pollForSignIn() async {
        guard let code = deviceCode else { return }
        let expires = Date().addingTimeInterval(Double(max(code.expiresIn, 1)))
        var interval = max(code.interval, 1)
        do {
            while Date() < expires {
                try await Task.sleep(for: .seconds(interval))
                try Task.checkCancellation()
                guard deviceCode == code else { return }
                switch try await services.traktAccount.checkAuthorization(code) {
                case .pending: continue
                case .slowDown: interval += 5
                case .signedIn:
                    isSignedIn = true
                    deviceCode = nil
                    message = "Signed in to Trakt."
                    return
                }
            }
            throw TraktAccountError.expiredCode
        } catch {
            guard !Task.isCancelled else { return }
            deviceCode = nil
            errorMessage = Self.message(for: error)
        }
    }

    public func cancelSignIn() { deviceCode = nil }

    public func signOut() async {
        deviceCode = nil
        await perform {
            await self.services.traktAccount.signOut()
            self.isSignedIn = false
            self.message = "Signed out of Trakt. Your local library and history are kept."
        }
    }

    public func importFromTrakt() async {
        guard syncWatchlist || syncHistory else { return }
        await perform {
            var savedCount = 0
            var watchedCount = 0
            let watchlist = self.syncWatchlist ? try await self.services.traktAccount.watchlist() : []
            let watched = self.syncHistory ? try await self.services.traktAccount.watched() : []
            if self.syncWatchlist {
                for item in watchlist {
                    let libraryItem = LibraryItem(preview: item)
                    if !(await self.services.library.contains(libraryItem.id)) {
                        await self.services.library.add(libraryItem)
                        savedCount += 1
                    }
                }
            }
            if self.syncHistory {
                for item in watched {
                    guard await self.services.progress.progress(for: item.identity)?.isWatched != true else { continue }
                    let existing = await self.services.progress.progress(for: item.identity)
                    await self.services.progress.save(WatchProgress(id: item.identity, type: item.preview.type, contentID: item.contentID,
                        title: existing?.title ?? item.preview.name, poster: existing?.poster ?? item.preview.poster,
                        position: existing?.position ?? 0, duration: existing?.duration ?? 0, isWatched: true,
                        updatedAt: max(existing?.updatedAt ?? .distantPast, item.watchedAt), season: item.season, episode: item.episode))
                    watchedCount += 1
                }
            }
            self.message = "Imported \(savedCount) saved titles and \(watchedCount) watched items from Trakt."
        }
    }

    public func sendToTrakt() async {
        guard syncWatchlist || syncHistory else { return }
        await perform {
            var savedCount = 0
            var watchedCount = 0
            if self.syncWatchlist {
                let remote = Set(try await self.services.traktAccount.watchlist().map { LibraryItem.identity(type: $0.type, contentID: $0.id) })
                let local = await self.services.library.all().filter { !remote.contains($0.id) }.map(\.preview)
                savedCount = try await self.services.traktAccount.addToWatchlist(local)
            }
            if self.syncHistory {
                let remote = Set(try await self.services.traktAccount.watched().map(\.identity))
                let local = await self.services.progress.all().filter { $0.isWatched && !remote.contains($0.id) }.compactMap(Self.traktItem)
                watchedCount = try await self.services.traktAccount.addToHistory(local)
            }
            self.message = "Sent \(savedCount) saved titles and \(watchedCount) watched items to Trakt."
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        message = nil
        defer { isWorking = false }
        do { try await operation() }
        catch { errorMessage = Self.message(for: error) }
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
