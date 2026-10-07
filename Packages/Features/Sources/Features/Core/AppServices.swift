import Foundation
import StremioKit

/// The app's long-lived services, handed to view models. Built once at launch (App/) and in tests (with stubs or the mock).
public struct AppServices: Sendable {
    public let registry: AddonRegistry
    public let client: AddonClient
    public let browse: BrowseService
    public let streams: StreamService
    public let settings: any SettingsStore
    /// True once a fallback engine (M6) is linked into the app.
    public let fallbackEngineLinked: Bool

    public init(registry: AddonRegistry, client: AddonClient, browse: BrowseService? = nil, streams: StreamService? = nil,
                settings: (any SettingsStore)? = nil, fallbackEngineLinked: Bool = false) {
        self.registry = registry
        self.client = client
        self.browse = browse ?? BrowseService(registry: registry, client: client)
        self.streams = streams ?? StreamService(registry: registry, client: client)
        self.settings = settings ?? InMemorySettingsStore()
        self.fallbackEngineLinked = fallbackEngineLinked
    }
}
