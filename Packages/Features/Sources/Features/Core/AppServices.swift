import Foundation
import StremioKit

/// The app's long-lived services, handed to view models. Built once at launch (App/) and in tests (with stubs or the mock).
public struct AppServices: Sendable {
    public let registry: AddonRegistry
    public let client: AddonClient
    public let browse: BrowseService

    public init(registry: AddonRegistry, client: AddonClient, browse: BrowseService? = nil) {
        self.registry = registry
        self.client = client
        self.browse = browse ?? BrowseService(registry: registry, client: client)
    }
}
