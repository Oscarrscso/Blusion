import Foundation
import Testing
@testable import StremioKit
import StremioKitTestSupport

@Suite struct WidgetStoreTests {
    private let layout = [
        HomeWidget(id: "continue", title: "Continue", content: .continueWatching),
        HomeWidget(id: "row", title: "Movies", content: .row(RowConfiguration(source: .traktList(TraktListReference(username: "u", listSlug: "s", listName: "S")),
            limit: 30))),
    ]

    /// A throwaway suite, so tests never touch the app's own defaults.
    private func isolatedDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "test.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func theInMemoryStoreKeepsNilAsNeverCustomised() async {
        let store = InMemoryWidgetStore()
        #expect(await store.load() == nil)
        await store.save(layout)
        #expect(await store.load() == layout)
        await store.save(nil)
        #expect(await store.load() == nil)
        #expect(await InMemoryWidgetStore(layout).load() == layout)
    }

    @Test func anEmptyLayoutIsNotTheSameAsNoLayout() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsWidgetStore(defaults: defaults)
        await store.save([])
        #expect(await store.load() == [], "the user deleted every row: show nothing, not the automatic layout")
        await store.save(nil)
        #expect(await store.load() == nil)
    }

    @Test func theDefaultsStoreRoundTripsInTheVersionedWrapper() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsWidgetStore(defaults: defaults)
        #expect(DefaultsWidgetStore.key == "home.widgets.v1")
        await store.save(layout)
        #expect(await store.load() == layout)
        #expect(await DefaultsWidgetStore(defaults: defaults).load() == layout, "a new instance reads the same layout")

        let raw = try #require(defaults.data(forKey: DefaultsWidgetStore.key))
        let object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect((object["widgets"] as? [Any])?.count == 2)
    }

    @Test func savingNilRemovesTheStoredLayout() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsWidgetStore(defaults: defaults)
        await store.save(layout)
        await store.save(nil)
        #expect(defaults.object(forKey: DefaultsWidgetStore.key) == nil)
        #expect(await store.load() == nil)
    }

    @Test func unreadableOrUnknownVersionsLoadAsNil() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsWidgetStore(defaults: defaults)
        let bad = [Data("not json".utf8), Data(#"{"version": 2, "widgets": []}"#.utf8), Data(#"{"version": 1}"#.utf8), Data(#"{"widgets": []}"#.utf8)]
        for data in bad {
            defaults.set(data, forKey: DefaultsWidgetStore.key)
            #expect(await store.load() == nil)
        }
    }

    @Test func aLayoutImportedFromFusionStoresWithoutTheAddonLink() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let manifest = Manifest(id: "com.example.catalogs", name: "Catalogs", version: "1", resources: [ResourceDescriptor(name: "catalog")],
                                types: ["movie"], catalogs: [CatalogDescriptor(type: "movie", id: "mdblist.wb", name: "Warner Bros")])
        let (registry, _) = try await makeStubbedRegistry(manifests: [manifest], transport: StubTransport(data: Data()))
        let imported = try FusionWidgetCodec.decode(Data(#"""
        { "widgets": [ { "id": "aio.1", "title": "Netflix", "type": "row.classic",
          "dataSource": { "kind": "addonCatalog", "payload": { "addonId": "https://stub0.example.com/TOKEN/manifest.json", "catalogId": "movie::mdblist.wb",
              "catalogType": "movie" } } } ] }
        """#.utf8), installed: await registry.addons)
        let store = DefaultsWidgetStore(defaults: defaults)
        await store.save(imported.widgets)
        let raw = String(decoding: try #require(defaults.data(forKey: DefaultsWidgetStore.key)), as: UTF8.self)
        #expect(!raw.contains("TOKEN") && !raw.contains("manifest.json"), "only the addon's id and display host are persisted")
        #expect(await store.load() == imported.widgets)
    }
}
