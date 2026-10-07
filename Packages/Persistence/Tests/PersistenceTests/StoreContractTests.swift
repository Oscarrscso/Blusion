import Foundation
import Testing
import StremioKit
@testable import Persistence

/// The behaviour every `AddonStore` must have. Runs against the in-memory store everywhere and SwiftData on Apple platforms.
func exerciseAddonStoreContract(_ store: any AddonStore) async throws {
    #expect(try await store.loadAll().isEmpty)
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    let a = AddonRecord(id: UUID(), manifestData: Data("a".utf8), isEnabled: true, order: 0, installedAt: when)
    let b = AddonRecord(id: UUID(), manifestData: Data("b".utf8), isEnabled: false, order: 1, installedAt: when)
    let c = AddonRecord(id: UUID(), manifestData: Data("c".utf8), isEnabled: true, order: 2, installedAt: when)

    try await store.save([a, b])
    #expect(try await store.loadAll().sorted { $0.order < $1.order } == [a, b])

    // update one, add one, drop one
    var updated = b
    updated.isEnabled = true
    updated.order = 0
    var moved = a
    moved.order = 1
    try await store.save([updated, moved, c])
    #expect(try await store.loadAll().sorted { $0.order < $1.order } == [updated, moved, c])

    try await store.save([c])
    #expect(try await store.loadAll() == [c])

    try await store.save([])
    #expect(try await store.loadAll().isEmpty)
}

func exerciseSecretStoreContract(_ store: any SecretStore) async throws {
    let key = "addon.\(UUID().uuidString).manifestURL"
    #expect(try await store.get(key) == nil)
    try await store.set("https://example.com/TOKEN/manifest.json", for: key)
    #expect(try await store.get(key) == "https://example.com/TOKEN/manifest.json")
    try await store.set("https://example.com/OTHER/manifest.json", for: key)
    #expect(try await store.get(key) == "https://example.com/OTHER/manifest.json", "set replaces")
    try await store.remove(key)
    #expect(try await store.get(key) == nil)
    try await store.remove(key)   // removing twice is fine
}

@Suite struct StoreContractTests {
    @Test func inMemoryAddonStore() async throws {
        try await exerciseAddonStoreContract(InMemoryAddonStore())
    }

    @Test func inMemorySecretStore() async throws {
        try await exerciseSecretStoreContract(InMemorySecretStore())
    }

    @Test func bootstrap() {
        #expect(PersistenceInfo.name == "Persistence")
    }
}
