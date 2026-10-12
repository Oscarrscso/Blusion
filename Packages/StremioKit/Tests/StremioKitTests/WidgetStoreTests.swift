import Foundation
import Testing
@testable import StremioKit
import StremioKitTestSupport

@Suite struct WidgetStoreTests {
    private let layout = [
        HomeWidget(id: "continue", title: "Continue Watching", content: .continueWatching),
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

    @Test func aDiscoverWidgetSurvivesTheDefaultsStore() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let query = TMDbDiscoverQuery(kind: .series, ordering: .newest, period: .last5Years, minimumScore: 6.5, language: "ja")
        let discover = HomeWidget(id: "discover", title: "New Japanese Series", content: .row(RowConfiguration(
            source: .tmdbDiscover(query), presentation: WidgetPresentation(usesBetterPosters: true))))
        let widgets = layout + [discover]
        let store = DefaultsWidgetStore(defaults: defaults)
        await store.save(widgets)
        #expect(await DefaultsWidgetStore(defaults: defaults).load() == widgets)
        #expect(await InMemoryWidgetStore(widgets).load() == widgets)
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

    @Test func aWidgetThisBuildCannotReadIsKeptInStorageWhereItWas() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsWidgetStore(defaults: defaults)
        await store.save(layout)
        // A widget a newer build saved between the two this build reads: its content kind is one this build does not have.
        let future: [String: Any] = ["id": "future", "title": "From a newer build", "hideTitle": false, "content": ["futureKind": [String: Any]()]]
        let stored = try #require(defaults.data(forKey: DefaultsWidgetStore.key))
        var envelope = try #require(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        var widgets = try #require(envelope["widgets"] as? [Any])
        widgets.insert(future, at: 1)
        envelope["widgets"] = widgets
        defaults.set(try JSONSerialization.data(withJSONObject: envelope), forKey: DefaultsWidgetStore.key)

        #expect(await store.load() == layout, "a widget this build cannot read is left out of the layout")

        let added = HomeWidget(id: "added", title: "Added", content: .continueWatching)
        await store.save([layout[0], added, layout[1]])
        #expect(await store.load() == [layout[0], added, layout[1]])
        #expect(try savedIDs(in: defaults) == ["continue", "future", "added", "row"], "it stays after the widget before it")

        await store.save([added, layout[1]])
        #expect(try savedIDs(in: defaults) == ["future", "added", "row"], "with the widget before it gone, it moves to the front")
    }

    /// Layouts saved before Fusion's TMDb lists read their filters from the title hold them as unsupported. Loading reads them now.
    @Test func aSavedFusionTMDbListReadsItsFiltersFromItsTitleOnLoad() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let stale = HomeWidget(id: "old", title: "Hidden Gems", content: .row(RowConfiguration(source: .unsupported(kind: "tmdbDiscover"))))
        let unknown = HomeWidget(id: "blusion", title: "Horror", content: .row(RowConfiguration(source: .unsupported(kind: "blusion.tmdbDiscover"))))
        let decades = HomeWidget(id: "tiles", title: "Decades", content: .collection([
            CollectionItem(id: "d", title: "1980s TV", sources: [.unsupported(kind: "tmdbDiscover")]),
        ]))
        let store = DefaultsWidgetStore(defaults: defaults)
        await store.save([stale, unknown, decades])
        let loaded = try #require(await DefaultsWidgetStore(defaults: defaults).load())
        #expect(loaded.count == 3)
        #expect(loaded[0] == HomeWidget(id: "old", title: "Hidden Gems", content: .row(RowConfiguration(source: .tmdbDiscover(.inferred(fromTitle: "Hidden Gems"))))))
        #expect(loaded[1] == unknown, "only the exact Fusion kind is read from its title")
        if case .collection(let tiles) = loaded[2].content {
            #expect(tiles.first?.sources == [.tmdbDiscover(.inferred(fromTitle: "1980s TV"))])
        } else {
            Issue.record("the collection should load as a collection")
        }
    }

    private func savedIDs(in defaults: UserDefaults) throws -> [String] {
        let data = try #require(defaults.data(forKey: DefaultsWidgetStore.key))
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(envelope["widgets"] as? [[String: Any]]).compactMap { $0["id"] as? String }
    }
}
