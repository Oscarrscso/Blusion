import Foundation
import PlayerKit
import SwiftData
import StremioKit
import Persistence
import Features
#if BLUSION_FALLBACK_ENGINE
import FallbackPlayer
#endif

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

    /// Installs the default metadata addon on first launch. Waits at most `limit` so the first screen usually opens with content;
    /// a slower install finishes in the background and Home fills in when the registry publishes the addon.
    func seedDefaultAddons(waitingAtMost limit: Duration = .seconds(3)) async {
        guard let seeder else { return }
        // Not a task group: a group waits for all its children, and the install cannot be cancelled, so the screen would wait for it anyway.
        let install = Task { await seeder.seedIfNeeded() }
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
        let settingsDefaults: UserDefaults
        var secretsInKeychain = true
        if uiTesting {
            store = InMemoryAddonStore()
            secrets = InMemorySecretStore()
            progress = InMemoryProgressStore()
            library = InMemoryLibraryStore()
            // A throwaway suite, so UI tests neither read nor leave preferences behind.
            let suite = "app.blusion.uitest.\(UUID().uuidString)"
            settingsDefaults = UserDefaults(suiteName: suite) ?? .standard
            settingsDefaults.removePersistentDomain(forName: suite)
        } else {
            let device = KeychainSecretStore.forThisDevice()
            secrets = device.store
            secretsInKeychain = device.usesKeychain
            if !secretsInKeychain { logger.log(.error, "Keychain unavailable to this build; secrets are kept in a private file") }
            settingsDefaults = .standard
            if let container = try? PersistenceContainer.make() {
                // One container, three stores: addons, watch progress and the library share the same file and migration plan.
                store = SwiftDataAddonStore(container: container)
                progress = SwiftDataProgressStore(container: container)
                library = SwiftDataLibraryStore(container: container)
            } else {
                // A store that cannot be opened must not stop the app: run from memory and say so.
                logger.log(.error, "persistent store unavailable; using memory")
                store = InMemoryAddonStore()
                progress = InMemoryProgressStore()
                library = InMemoryLibraryStore()
            }
        }
        let settings = DefaultsSettingsStore(defaults: settingsDefaults, secrets: secrets)
        let registry = AddonRegistry(store: store, secrets: secrets, client: client, logger: logger)
        // AVPlayer for MP4/MOV/M4V/HLS. MKV, AVI, DTS and friends go to the fallback engine when it is built in (ADR-006, opt-in).
        let makeEngine: EngineFactory = { candidate in
            switch candidate.route {
            case .native:
                let engine = AVEngine()
                #if DEBUG
                // A snapshot run (scripts/snapshot.sh) plays for a few seconds on the Mac: keep it silent.
                if environment["BLUSION_SNAPSHOT"] != nil { engine.player.isMuted = true }
                #endif
                return engine
            case .fallback:
                #if BLUSION_FALLBACK_ENGINE
                return FallbackEngine(backend: MPVBackend())
                #else
                return nil
                #endif
            default:
                return nil
            }
        }
        #if BLUSION_FALLBACK_ENGINE
        let fallbackLinked = true
        #else
        let fallbackLinked = false
        #endif
        // The Home layout is a preference, not a secret: it names addons by manifest id and host, never by URL.
        let widgets: any WidgetStore = uiTesting ? InMemoryWidgetStore() : DefaultsWidgetStore(defaults: settingsDefaults)
        // Streams handed to Infuse and not yet called back, so a stop recorded after a relaunch still counts.
        let handoffs: any HandoffStore = uiTesting ? InMemoryHandoffStore() : DefaultsHandoffStore(defaults: settingsDefaults)
        // The last items of each Home row, kept on disk so Home shows them at once on the next launch (UI tests start empty).
        var snapshots: (any WidgetSnapshotStore)?
        if !uiTesting, let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            snapshots = FileWidgetSnapshotStore(directory: caches.appendingPathComponent("WidgetSnapshots", isDirectory: true))
        }
        let widgetContent = WidgetContentService(registry: registry, client: client, settings: settings, snapshots: snapshots)
        let ratingsCache: any RatingsCache
        if !uiTesting, let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            ratingsCache = FileRatingsCache(fileURL: caches.appendingPathComponent("poster-ratings.json"))
        } else {
            ratingsCache = InMemoryRatingsCache()
        }
        let posterRatings = PosterRatingsStore(letterboxd: uiTesting ? nil : LetterboxdRatings(client: client), cache: ratingsCache)
        let searchHistory: any SearchHistoryStore = uiTesting ? InMemorySearchHistoryStore() : DefaultsSearchHistoryStore(defaults: settingsDefaults)
        let traktAccount = TraktAccount(settings: settings, secrets: secrets)
        let services = AppServices(registry: registry, client: client, settings: settings, progress: progress, library: library,
                                   makeEngine: makeEngine, fallbackEngineLinked: fallbackLinked, widgets: widgets, widgetContent: widgetContent,
                                   posterRatings: posterRatings, handoffs: handoffs, searchHistory: searchHistory, traktAccount: traktAccount,
                                   secretsInKeychain: secretsInKeychain)
        let seedsDefaults = !uiTesting || environment["BLUSION_SEED_DEFAULTS"] == "1"
        let seeder = seedsDefaults ? DefaultAddonSeeder(registry: registry, flags: DefaultsFlagStore(defaults: settingsDefaults)) : nil
        return AppEnvironment(services: services, isUITesting: uiTesting, launchRoute: LaunchRoute.parse(environment["BLUSION_ROUTE"]) ?? .home,
                              seeder: seeder)
    }
}
