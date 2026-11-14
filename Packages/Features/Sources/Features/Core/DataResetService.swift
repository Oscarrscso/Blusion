import Foundation
import Persistence
import PlayerKit
import StremioKit

/// Local clearing, preference reset and full erasure have different account semantics.
public struct DataResetService: Sendable {
    public enum Scope: Sendable, Equatable, CaseIterable {
        case history, library, downloads, settings, widgets, addons, everything

        public var title: String {
            switch self {
            case .downloads: return "Downloads"
            case .history: return "Watch history"
            case .library: return "Saved titles"
            case .settings: return "Reset Settings"
            case .widgets: return "Home layout"
            case .addons: return "All addons"
            case .everything: return "Erase Everything"
            }
        }

        public var actionTitle: String {
            switch self {
            case .settings, .everything: title
            default: "Clear \(title.lowercased())"
            }
        }

        public var warning: String {
            switch self {
            case .downloads: return "Removes downloaded videos and subtitles from this device. Videos in use are deleted after playback closes."
            case .history: return "Clears watch progress, watched marks and the playback session on this device. Nothing is removed from Trakt; the next sync can restore this history."
            case .library: return "Clears saved titles on this device. Nothing is removed from Trakt; the next sync can restore these titles."
            case .settings: return "Restores this device’s playback, appearance, haptics, download and Performance preferences, turns Ghost Mode off and clears the streaming server. Accounts, rating-service keys, named looks, history, saved titles, addons and Home layout are kept."
            case .widgets: return "Returns Home to the automatic layout and clears widget shuffle choices. If Widget Sync is configured, this can reset Home on your other devices."
            case .addons: return "Removes every installed addon and its saved link. This can also remove links shared through iCloud Keychain. You’ll need to add the addons again."
            case .everything: return "Erases this device’s history, saved titles, downloads, preferences, accounts, named looks, search history and all addons, and disconnects Trakt and Widget Sync. The Home reset and removed addon links can affect other devices. Trakt’s remote history and saved titles are kept and can return if you reconnect. Built-in API configuration is kept."
            }
        }
    }

    private struct Outcome {
        var failures: [String] = []
        var notes: [String] = []
    }

    private let services: AppServices
    private let snapshotStore: any PlaybackSnapshotStore

    public init(services: AppServices, snapshotStore: (any PlaybackSnapshotStore)? = nil) {
        self.services = services
        self.snapshotStore = snapshotStore ?? PlaybackSession.store
    }

    @discardableResult
    public func clear(_ scope: Scope) async -> String {
        let result = await perform(scope)
        let success: String = switch scope {
        case .settings: "Settings reset. Accounts and named looks kept."
        case .everything: "Local data erased. Trakt’s remote data is kept."
        case .history: "Local watch history cleared. Trakt can restore it on the next sync."
        case .library: "Local saved titles cleared. Trakt can restore them on the next sync."
        default: "\(scope.title) cleared."
        }
        let status = result.failures.isEmpty && result.notes.isEmpty ? success
            : result.failures.isEmpty ? "\(scope.title): deletion pending."
            : "\(scope.title): only partially completed."
        return ([status] + result.failures + result.notes).joined(separator: " ")
    }

    private func perform(_ scope: Scope) async -> Outcome {
        var result = Outcome()
        switch scope {
        case .downloads:
            if let deletion = await services.downloads?.deleteAll() {
                if deletion.failed > 0 { result.failures.append("Could not delete \(deletion.failed) downloads.") }
                if deletion.pending > 0 { result.notes.append("\(deletion.pending) downloads are waiting for playback or transfers to close.") }
            }
        case .history:
            await services.progress.clear()
            await snapshotStore.clear()
            if !(await services.progress.all()).isEmpty { result.failures.append("Watch history could not be fully cleared.") }
        case .library:
            await services.library.clear()
            if !(await services.library.all()).isEmpty { result.failures.append("Saved titles could not be fully cleared.") }
        case .settings:
            result = await resetPreferences(preservingAccounts: true)
        case .widgets:
            do { try await services.widgets.resetLayout() }
            catch { result.failures.append("Home was reset locally, but the shared layout could not be reset.") }
            if await services.widgets.load() != nil { result.failures.append("The local Home layout could not be reset.") }
            await services.widgetShuffle.clear()
            await services.widgetContent.forgetEverything()
        case .addons:
            var failed = 0
            for id in await services.registry.installedIDs {
                do { try await services.registry.remove(id: id) } catch { failed += 1 }
            }
            if failed > 0 { result.failures.append("Could not remove \(failed) addons and their saved links.") }
            await services.widgetContent.forgetEverything()
            await services.addonSpeed.clear()
        case .everything:
            // Stop account sync before clearing its local stores, including a sync already in flight.
            if !(await services.traktAccount.clearCredentials()) {
                result.failures.append("Some Trakt credentials could not be erased.")
            }
            await services.traktSync.reset()
            let preferences = await resetPreferences(preservingAccounts: false)
            result.failures += preferences.failures
            AppearanceLooks.reset()
            for each in [Scope.history, .library, .downloads, .widgets, .addons] {
                let part = await perform(each)
                result.failures += part.failures
                result.notes += part.notes
            }
            services.sharedFolder?.forget()
            services.searchHistory.save([])
            await services.posterRatings.forgetAll()
            await services.handoffs.clear()
        }
        return result
    }

    private func resetPreferences(preservingAccounts: Bool) async -> Outcome {
        let expected = await services.settings.update { value in
            var defaults = PlaybackSettings()
            // Private builds supply these even after a reset.
            defaults.traktClientID = value.traktClientID
            defaults.omdbAPIKey = value.omdbAPIKey
            defaults.tmdbReadToken = value.tmdbReadToken
            if preservingAccounts {
                defaults.openSubtitlesAPIKey = value.openSubtitlesAPIKey
                defaults.openSubtitlesUsername = value.openSubtitlesUsername
                defaults.openSubtitlesPassword = value.openSubtitlesPassword
            }
            value = defaults
        }
        AppearancePreferences.reset()
        for key in OptimisationSettings.allKeys + [ImageCachePolicy.diskMegabytesKey, GhostMode.defaultsKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let saved = await services.settings.load()
        await services.posterRatings.setReviewServices(
            omdb: saved.omdbAPIKey.map { OMDbRatings(client: services.client, apiKey: $0) },
            tmdb: saved.tmdbReadToken.map { TMDbRatings(client: services.client, readAccessToken: $0) })
        await MainActor.run {
            services.posterRatings.isEnabled = saved.showsPosterRatings
            services.posterRatings.showsColouredLogos = saved.showsColouredRatingLogos
            services.posterRatings.showsBestDisc = saved.showsBestDiscOnPosters
            services.posterRatings.markPlacement = saved.posterMarkPlacement
            #if canImport(UIKit)
            Haptics.apply(saved.haptics)
            ImagePipeline.shared.setMemoryLevel(OptimisationSettings.pictureMemory())
            ImagePipeline.shared.setDiskLimit(megabytes: ImageCachePolicy.defaultDiskMegabytes)
            #endif
        }
        #if canImport(UIKit)
        await ImagePipeline.shared.downloadSlotsChanged()
        #endif
        await services.downloads?.preferencesChanged()
        await services.trakt.clearCache()
        await services.widgetContent.forgetEverything()
        return Outcome(failures: saved == expected ? [] : ["Some settings could not be reset or saved."])
    }
}
