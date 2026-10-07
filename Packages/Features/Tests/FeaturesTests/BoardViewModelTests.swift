import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct BoardViewModelTests {
    private func services(_ server: MockServer, timeout: TimeInterval? = nil) -> AppServices {
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: timeout ?? (server.slowDelay + 4), maxRetries: 0, retryBackoff: 0.01))
        let registry = AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client)
        return AppServices(registry: registry, client: client)
    }

    @Test func emptyStateWhenNothingIsInstalled() async throws {
        let model = BoardViewModel(services: services(try MockServer.shared()))
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .noAddons)
        #expect(model.rows.isEmpty)
    }

    @Test func streamOnlyAddonsLeaveNoCatalogsToShow() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.streamManifestURL().absoluteString)
        let model = BoardViewModel(services: services)
        await model.load()
        #expect(model.phase == .noCatalogs)
    }

    @Test func rowsLoadFromEveryCatalog() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let model = BoardViewModel(services: services)
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.rows.map(\.source.catalog.id) == ["mock-movies", "mock-top"])
        #expect(model.rows[0].state.value?.count == 20)
        #expect(model.rows[1].state.value?.map(\.id) == ["mock:movie1", "mock:movie2", "mock:movie3", "mock:nometa1"])
    }

    @Test func aBrokenAddonOnlyFailsItsOwnRowsAndCanBeRetried() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL(token: "good").absoluteString)
        let broken = try await services.registry.install(from: server.catalogManifestURL(flags: ["err500"], token: "bad").absoluteString)
        let model = BoardViewModel(services: services)
        await model.load()
        #expect(model.rows.count == 4)
        let good = model.rows.filter { $0.source.addon.id != broken.id }
        let bad = model.rows.filter { $0.source.addon.id == broken.id }
        #expect(good.allSatisfy { $0.state.value != nil })
        #expect(bad.allSatisfy { $0.state.error == .http(status: 500) })
        let rowID = try #require(bad.first?.id)
        await model.retry(rowID: rowID)
        #expect(model.rows.first { $0.id == rowID }?.state.error == .http(status: 500), "still failing, but handled")
        await model.retry(rowID: "no-such-row")
    }

    @Test func rowsFillInAsEachAddonAnswers() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL(token: "fast").absoluteString)
        _ = try await services.registry.install(from: server.catalogManifestURL(flags: ["slow"], token: "slow").absoluteString)
        let model = BoardViewModel(services: services)
        let loading = Task { await model.load() }
        try await Task.sleep(for: .milliseconds(server.slowDelay * 1000 / 2))
        let midway = model.rows
        #expect(midway.count == 4)
        #expect(midway.prefix(2).allSatisfy { $0.state.value != nil }, "the fast addon's rows are already filled in")
        #expect(midway.suffix(2).allSatisfy { $0.state.isLoading }, "the slow addon's rows are still spinning")
        await loading.value
        #expect(model.rows.allSatisfy { $0.state.value != nil })
    }

    @Test func observingAddonsReloadsWhenTheyChange() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        let model = BoardViewModel(services: services)
        let observing = Task { await model.observeAddons() }
        try await waitUntil { model.phase == .noAddons }
        let addon = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        try await waitUntil { model.phase == .ready && model.rows.allSatisfy { $0.state.value != nil } }
        try await services.registry.setEnabled(false, id: addon.id)
        try await waitUntil { model.phase == .noCatalogs || model.phase == .noAddons || model.rows.isEmpty }
        #expect(model.rows.isEmpty)
        observing.cancel()
    }
}

/// Polls `condition` on the main actor until it holds or the timeout passes.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { throw WaitTimeout() }
        try await Task.sleep(for: .milliseconds(20))
    }
}

struct WaitTimeout: Error {}
