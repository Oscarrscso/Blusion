#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import StremioKit
@testable import Persistence

@Suite struct SwiftDataStoreTests {
    @Test func satisfiesTheAddonStoreContract() async throws {
        let container = try PersistenceContainer.make(inMemory: true)
        try await exerciseAddonStoreContract(SwiftDataAddonStore(container: container))
    }

    @Test func aSecondStoreOnTheSameContainerSeesSavedRecords() async throws {
        let container = try PersistenceContainer.make(inMemory: true)
        let record = AddonRecord(id: UUID(), manifestData: Data("m".utf8), isEnabled: true, order: 0, installedAt: Date(timeIntervalSince1970: 1))
        try await SwiftDataAddonStore(container: container).save([record])
        #expect(try await SwiftDataAddonStore(container: container).loadAll() == [record])
    }

    @Test func registryWorksOnTopOfSwiftData() async throws {
        let container = try PersistenceContainer.make(inMemory: true)
        let store = SwiftDataAddonStore(container: container)
        let secrets = InMemorySecretStore()
        let manifest = Manifest(id: "x", name: "X", version: "1", resources: [ResourceDescriptor(name: "stream")], types: ["movie"])
        let record = AddonRecord(id: UUID(), manifestData: try JSONEncoder().encode(manifest), isEnabled: true, order: 0, installedAt: Date())
        try await store.save([record])
        try await secrets.set("https://example.com/manifest.json", for: "addon.\(record.id.uuidString).manifestURL")
        let registry = AddonRegistry(store: store, secrets: secrets, client: AddonClient())
        try await registry.load()
        #expect(await registry.addons.map(\.name) == ["X"])
    }
}
#endif
