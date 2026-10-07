import Foundation
import PlayerKit
import SwiftData
import StremioKit
import Persistence
import Features

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
        if uiTesting {
            store = InMemoryAddonStore()
            secrets = InMemorySecretStore()
        } else {
            secrets = KeychainSecretStore()
            if let container = try? PersistenceContainer.make() {
                store = SwiftDataAddonStore(container: container)
            } else {
                // A store that cannot be opened must not stop the app: run from memory and say so.
                logger.log(.error, "persistent store unavailable; using memory")
                store = InMemoryAddonStore()
            }
        }
        let registry = AddonRegistry(store: store, secrets: secrets, client: client, logger: logger)
        // AVPlayer for MP4/MOV/M4V/HLS. The fallback engine for MKV and friends arrives in M6.
        let makeEngine: EngineFactory = { candidate in
            switch candidate.route {
            case .native: return AVEngine()
            default: return nil
            }
        }
        return AppEnvironment(services: AppServices(registry: registry, client: client, makeEngine: makeEngine), isUITesting: uiTesting)
    }
}
