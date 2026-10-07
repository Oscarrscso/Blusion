import Foundation
@testable import StremioKit

enum TestAddons {
    /// An installed addon pointing at `base`; resources and catalogs mirror the mock's catalog addon.
    static func catalogAddon(base: URL, name: String = "Mock Catalog", enabled: Bool = true) -> InstalledAddon {
        let manifest = Manifest(
            id: "test.\(name)", name: name, version: "1.0.0",
            resources: [ResourceDescriptor(name: "catalog"), ResourceDescriptor(name: "meta")],
            types: ["movie", "series"],
            catalogs: [CatalogDescriptor(type: "movie", id: "mock-top", name: "Top"),
                       CatalogDescriptor(type: "movie", id: "mock-movies", name: "Movies",
                                         extra: [ExtraDescriptor(name: "search"), ExtraDescriptor(name: "genre", options: ["Action", "Drama", "Comedy"]), ExtraDescriptor(name: "skip")])],
            idPrefixes: ["mock:"])
        return InstalledAddon(manifestURL: base.appendingPathComponent("manifest.json"), baseURL: base, manifest: manifest, isEnabled: enabled)
    }

    static func streamAddon(base: URL, name: String = "Mock Streams") -> InstalledAddon {
        let manifest = Manifest(
            id: "test.\(name)", name: name, version: "1.0.0",
            resources: [ResourceDescriptor(name: "stream", types: ["movie", "series"], idPrefixes: ["mock:"]),
                        ResourceDescriptor(name: "subtitles", types: ["movie"], idPrefixes: ["mock:"])],
            types: ["movie", "series"])
        return InstalledAddon(manifestURL: base.appendingPathComponent("manifest.json"), baseURL: base, manifest: manifest)
    }
}

/// Seconds since `start`, for ordering assertions.
func elapsed(since start: Date) -> TimeInterval { Date().timeIntervalSince(start) }
