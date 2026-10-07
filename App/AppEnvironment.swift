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

    private init(services: AppServices, isUITesting: Bool) {
        self.services = services
        self.isUITesting = isUITesting
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
            secrets = KeychainSecretStore()
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
                return AVEngine()
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
        let services = AppServices(registry: registry, client: client, settings: settings, progress: progress, library: library,
                                   makeEngine: makeEngine, fallbackEngineLinked: fallbackLinked)
        return AppEnvironment(services: services, isUITesting: uiTesting)
    }
}
