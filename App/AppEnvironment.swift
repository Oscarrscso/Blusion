import CryptoKit
import Foundation
import PlayerKit
import SwiftData
import StremioKit
import Persistence
import Features
import FallbackPlayer

/// Builds the app's long-lived services once. UI tests (`BLUSION_UITEST=1`) get in-memory stores, so every test launch starts empty
/// and nothing is written to the Keychain or disk.
@MainActor
final class AppEnvironment {
    let services: AppServices
    let isUITesting: Bool
    /// The screen to open on (`BLUSION_ROUTE`, see `LaunchRoute`). Home unless a test or `scripts/snapshot.sh` asks for another.
    let launchRoute: LaunchRoute
    /// Nil in UI tests, which start with no addons, unless `BLUSION_SEED_DEFAULTS=1` (snapshots set it, so they show real catalogs).
    private let seeder: DefaultAddonSeeder?

    private init(services: AppServices, isUITesting: Bool, launchRoute: LaunchRoute, seeder: DefaultAddonSeeder?) {
        self.services = services
        self.isUITesting = isUITesting
        self.launchRoute = launchRoute
        self.seeder = seeder
    }

    /// Installs the default metadata addon on first launch. Waits at most `limit` so the first screen
    /// usually opens with content; a slower install finishes in the background and Home fills in when the registry publishes the addon.
    func seedDefaultAddons(waitingAtMost limit: Duration = .seconds(3)) async {
        guard seeder != nil else { return }
        let seeder = self.seeder
        // Not a task group: a group waits for all its children, and the install cannot be cancelled, so the screen would wait for it anyway.
        let install = Task {
            await seeder?.seedIfNeeded()
        }
        let (finished, signal) = AsyncStream<Void>.makeStream()
        Task {
            _ = await install.value
            signal.yield(())
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            signal.yield(())
        }
        for await _ in finished { break }
        timer.cancel()
        signal.finish()
    }

    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppEnvironment {
        let uiTesting = environment["BLUSION_UITEST"] == "1"
        let logger = AddonLogger(sink: OSLogSink())
        let client = AddonClient(logger: logger)

        let store: any AddonStore
        let secrets: any SecretStore
        let progress: any ProgressStore
        let library: any LibraryStore
        let downloads: any DownloadStore
        let settingsDefaults: UserDefaults
        var secretsInKeychain = true
        if uiTesting {
            store = InMemoryAddonStore()
            secrets = InMemorySecretStore()
            progress = InMemoryProgressStore()
            library = InMemoryLibraryStore()
            downloads = InMemoryDownloadStore()
            // A throwaway suite, so UI tests neither read nor leave preferences behind.
            let suite = "app.blusion.uitest.\(UUID().uuidString)"
            settingsDefaults = UserDefaults(suiteName: suite) ?? .standard
            settingsDefaults.removePersistentDomain(forName: suite)
        } else {
            let device = KeychainSecretStore.forThisDevice(onSynchronizedChange: {
                Task { @MainActor in SecretsSyncObserver.shared.secretsDidChangeLocally() }
            })
            secrets = device.store
            secretsInKeychain = device.usesKeychain
            if !secretsInKeychain { logger.log(.error, "Keychain unavailable to this build; secrets are kept in a private file") }
            settingsDefaults = .standard
            // A digest of the synchronized secrets, so a change is noticed without the secrets leaving the Keychain. Memory only.
            let secretStore = device.store
            let synchronizedSecretsFingerprint: @Sendable () async -> String = {
                var lines = ""
                for key in KeychainSecretStore.synchronizedKeys.sorted() {
                    let value = (try? await secretStore.get(key)) ?? ""
                    lines += "\(key)=\(value)\n"
                }
                return SHA256.hash(data: Data(lines.utf8)).map { String(format: "%02x", $0) }.joined()
            }
            SecretsSyncObserver.shared.start(secretsFingerprint: synchronizedSecretsFingerprint)
            if let container = try? PersistenceContainer.make() {
                // One container, three stores: addons, watch progress and the library share the same file and migration plan.
                store = SwiftDataAddonStore(container: container)
                progress = SwiftDataProgressStore(container: container)
                library = SwiftDataLibraryStore(container: container)
                downloads = SwiftDataDownloadStore(container: container)
            } else {
                // A store that cannot be opened must not stop the app: run from memory and say so.
                logger.log(.error, "persistent store unavailable; using memory")
                store = InMemoryAddonStore()
                progress = InMemoryProgressStore()
                library = InMemoryLibraryStore()
                downloads = InMemoryDownloadStore()
            }
        }
        let settings = QueuedSettingsStore(base: DefaultsSettingsStore(defaults: settingsDefaults, secrets: secrets, logger: logger))
        // Before any view exists: the haptics are the listener's own, and the first gesture of the session must already obey them.
        Haptics.apply(HapticPreferences.saved(in: settingsDefaults))
        let registry = AddonRegistry(store: store, secrets: secrets, client: client, logger: logger)
        // AVPlayer for MP4/MOV/M4V/HLS. MKV, AVI, DTS, AV1 and friends go to the fallback engine on iPhone and Mac.
        let makeEngine: EngineFactory = { candidate in
            switch candidate.route {
            case .native:
                let engine = AVEngine()
                #if DEBUG
                // A snapshot run (scripts/snapshot.sh) plays for a few seconds on the Mac: keep it silent.
                if environment["BLUSION_SNAPSHOT"] != nil { engine.player.isMuted = true }
                #endif
                return engine
            case .fallback(_, let reason):
                // AetherEngine first (native Dolby Vision, profile 7 FEL, Atmos), unless the listener chose mpv; mpv for full subtitle
                // styling and as the backup when AetherEngine can't start a stream (`.fullFeaturedEngine`, PlaybackCoordinator).
                let player = Self.playerPreferences(settingsDefaults)
                if reason != .fullFeaturedEngine, player.advancedEngine == .aether,
                   let aether = AetherBackend(composesFEL: player.composesDolbyVisionFEL, rendersObjectAudio: player.rendersObjectAudio,
                                              preferredAudioLanguages: player.audioLanguage.map { [$0] } ?? []) {
                    return FallbackEngine(backend: aether)
                }
                return FallbackEngine(backend: MPVBackend())
            default:
                return nil
            }
        }
        // The stream a player is opening on starts downloading at once, while its screen animates in. AetherEngine can take such bytes;
        // AVPlayer and mpv fetch their own, so only AetherEngine's streams warm.
        let preloadStream: StreamPreloader = { candidate in
            guard case .fallback(_, let reason) = candidate.route, reason != .fullFeaturedEngine, let url = candidate.url,
                  Self.playerPreferences(settingsDefaults).advancedEngine == .aether else { return }
            AetherBackend.prewarm(url: url, headers: candidate.headers)
        }
        // The Home layout is a preference, not a secret: it names addons by manifest id and host, never by URL. It is shared with the
        // user's other devices through a folder they choose in Settings (see `SyncedWidgetStore`).
        let sharedFolder = SharedFolder(defaults: settingsDefaults)
        let widgets: any WidgetStore = uiTesting ? InMemoryWidgetStore() : SyncedWidgetStore(defaults: settingsDefaults, shared: sharedFolder)
        // Streams handed to Infuse and not yet called back, so a stop recorded after a relaunch still counts.
        let handoffs: any HandoffStore = uiTesting ? InMemoryHandoffStore() : DefaultsHandoffStore(defaults: settingsDefaults)
        let addonSpeed: any AddonSpeedStore = uiTesting ? InMemoryAddonSpeedStore() : DefaultsAddonSpeedStore(defaults: settingsDefaults)
        let widgetShuffle: any WidgetShuffleStore = uiTesting ? InMemoryWidgetShuffleStore()
            : DefaultsWidgetShuffleStore(defaults: settingsDefaults)
        // The last items of each Home row, kept on disk so Home shows them at once on the next launch (UI tests start empty).
        var snapshots: (any WidgetSnapshotStore)?
        if !uiTesting, let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            snapshots = FileWidgetSnapshotStore(directory: caches.appendingPathComponent("WidgetSnapshots", isDirectory: true))
        }
        let traktAccount = TraktAccount(settings: settings, secrets: secrets)
        let trakt = TraktClient(client: client, account: traktAccount, cache: TraktBrowseCache())
        // Trakt's sync state (queued changes, and what Trakt last held) is kept across launches. UI tests keep it in memory.
        var traktSyncState: (any TraktSyncStateStore)?
        if !uiTesting, let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // A Mac app that is not sandboxed shares Application Support with every other such app, so on the Mac the file goes into a
            // folder named after the bundle id, as the SwiftData store does (see `PersistenceContainer.defaultStoreURL`).
            #if targetEnvironment(macCatalyst)
            let folder = Bundle.main.bundleIdentifier.map { support.appendingPathComponent($0, isDirectory: true) } ?? support
            #else
            let folder = support
            #endif
            traktSyncState = FileTraktSyncStateStore(fileURL: folder.appendingPathComponent("trakt-sync.json"))
        }
        // IMDb's ratings dataset, downloaded in the background once a day and read offline. UI tests never touch the network or the disk.
        var imdbDataset: IMDbRatingsService?
        if !uiTesting, let directory = IMDbRatingsService.standardDirectory() { imdbDataset = IMDbRatingsService(directory: directory) }
        let genreFile = uiTesting ? nil : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("title-genres.json")
        let browse = BrowseService(registry: registry, client: client, genreFile: genreFile)
        let ratingsCache: any RatingsCache
        var marksFile: URL?
        if !uiTesting, let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            ratingsCache = FileRatingsCache(fileURL: caches.appendingPathComponent("poster-ratings.json"))
            marksFile = caches.appendingPathComponent("title-marks.bin")
        } else {
            ratingsCache = InMemoryRatingsCache()
        }
        let marks = TitleMarksCache(fileURL: marksFile, region: Locale.current.region?.identifier ?? "US")
        let posterRatings = PosterRatingsStore(letterboxd: uiTesting ? nil : LetterboxdRatings(client: client), cache: ratingsCache,
                                               dataset: imdbDataset, bestBlurays: uiTesting ? nil : BestBluraysClient(client: client),
                                               marks: marks, myAnimeList: uiTesting ? nil : MyAnimeListRatings(client: client), logger: logger)
        // A TMDB list's score bounds hold each title to its rating as the rating filters judge it (Letterboxd, then IMDb).
        let widgetContent = WidgetContentService(registry: registry, client: client, settings: settings, trakt: trakt, account: traktAccount,
                                                 snapshots: snapshots, imdb: imdbDataset, browse: browse,
                                                 ratingJudge: { item, tmdbScore, isAnime in
                                                     await posterRatings.listRating(for: item, tmdbScore: tmdbScore, isAnime: isAnime)
                                                 })
        let searchHistory: any SearchHistoryStore = uiTesting ? InMemorySearchHistoryStore() : DefaultsSearchHistoryStore(defaults: settingsDefaults)
        let streamService = StreamService(registry: registry, client: client, timings: addonSpeed)
        let subtitleService = SubtitleService(registry: registry, client: client)
        let downloadManager = DownloadManager(store: downloads, secrets: secrets, settings: settings, streams: streamService,
                                              subtitles: subtitleService, fallback: true,
                                              hardwareAV1: AVHardware.decodesAV1InHardware, persistent: !uiTesting)
        DownloadBackgroundEvents.manager = downloadManager
        Task { await downloadManager.start() }
        let services = AppServices(registry: registry, client: client, browse: browse, streams: streamService, subtitles: subtitleService,
            settings: settings, progress: progress, library: library,
                                   makeEngine: makeEngine, preloadStream: preloadStream, fallbackEngineLinked: true, aetherEngineLinked: true,
                                   decodesAV1InHardware: AVHardware.decodesAV1InHardware,
                                   widgets: widgets, widgetContent: widgetContent,
                                   posterRatings: posterRatings, handoffs: handoffs, searchHistory: searchHistory, traktAccount: traktAccount, trakt: trakt,
                                   secretsInKeychain: secretsInKeychain, traktSyncState: traktSyncState, syncSchedulesItself: !uiTesting,
                                   addonSpeed: addonSpeed, widgetShuffle: widgetShuffle, downloads: downloadManager,
                                   sharedFolder: uiTesting ? nil : sharedFolder)
        if !uiTesting {
            // The first report from the network monitor is also the launch sync.
            Task { await services.traktSync.startMonitoringNetwork() }
        }
        let seedsDefaults = !uiTesting || environment["BLUSION_SEED_DEFAULTS"] == "1"
        let seeder = seedsDefaults ? DefaultAddonSeeder(registry: registry, flags: DefaultsFlagStore(defaults: settingsDefaults)) : nil
        return AppEnvironment(services: services, isUITesting: uiTesting, launchRoute: LaunchRoute.parse(environment["BLUSION_ROUTE"]) ?? .home,
                              seeder: seeder)
    }

    /// The player settings as saved now, read synchronously: an engine is made the moment a stream starts, when the async store can't be awaited.
    private static func playerPreferences(_ defaults: UserDefaults) -> PlayerPreferences {
        defaults.data(forKey: DefaultsSettingsStore.Keys.player).flatMap { try? JSONDecoder().decode(PlayerPreferences.self, from: $0) }
            ?? PlayerPreferences()
    }
}
