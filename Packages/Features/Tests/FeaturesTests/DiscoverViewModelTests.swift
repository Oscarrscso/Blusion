import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct DiscoverViewModelTests {
    private func services(_ server: MockServer) -> AppServices {
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: server.slowDelay + 4, maxRetries: 0, retryBackoff: 0.01))
        return AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client), client: client)
    }

    @Test func selectsTheFirstCatalogAndLoadsItsFirstPage() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let model = DiscoverViewModel(services: services)
        await model.loadSources()
        #expect(model.hasSources)
        #expect(model.selectedSource?.catalog.id == "mock-movies")
        #expect(model.items.count == 20)
        #expect(model.state == .loaded)
        #expect(model.genres == ["Action", "Drama", "Comedy"])
        #expect(model.canLoadMore)
    }

    @Test func nothingInstalledMeansNoSources() async throws {
        let model = DiscoverViewModel(services: services(try MockServer.shared()))
        await model.loadSources()
        #expect(!model.hasSources)
        #expect(model.selectedSource == nil)
        #expect(model.items.isEmpty)
        await model.reload()
        await model.loadMore()
        #expect(model.state == .idle)
    }

    @Test func skipPaginationAppendsUntilTheCatalogIsExhausted() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let model = DiscoverViewModel(services: services)
        await model.loadSources()
        await model.loadMore()
        #expect(model.items.count == 40)
        await model.loadMore()
        #expect(model.items.count == 45)
        #expect(model.canLoadMore, "a short page is not proof of the end; only an empty one is")
        await model.loadMore()
        #expect(model.items.count == 45)
        #expect(!model.canLoadMore)
        let ids = model.items.map(\.id)
        #expect(Set(ids).count == ids.count, "no duplicates across pages")
        await model.loadMore()   // no-op after the end
        #expect(model.items.count == 45)
    }

    @Test func genreFilterResetsAndRepaginates() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let model = DiscoverViewModel(services: services)
        await model.loadSources()
        await model.loadMore()
        await model.select(genre: "Drama")
        #expect(model.selectedGenre == "Drama")
        #expect(!model.items.isEmpty && model.items.allSatisfy { $0.genres.contains("Drama") })
        #expect(model.items.count < 40, "the previous pages were discarded")
        await model.select(genre: nil)
        #expect(model.items.count == 20)
    }

    @Test func switchingCatalogsKeepsOnlyCompatibleGenres() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let model = DiscoverViewModel(services: services)
        await model.loadSources()
        await model.select(genre: "Action")
        let top = try #require(model.sources.first { $0.catalog.id == "mock-top" })
        await model.select(source: top)
        #expect(model.selectedGenre == nil, "mock-top has no genre filter")
        #expect(model.genres.isEmpty)
        #expect(model.items.count == 4)
        #expect(!model.canLoadMore, "mock-top does not support skip")
    }

    @Test func aStaleResponseNeverOverwritesALaterSelection() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL(flags: ["slow"], token: "slow").absoluteString)
        _ = try await services.registry.install(from: server.catalogManifestURL(token: "fast").absoluteString)
        let model = DiscoverViewModel(services: services)
        await model.loadSources()   // selects the slow addon's first catalog (and waits for it)
        let slowTop = try #require(model.sources.first { $0.catalog.id == "mock-top" && $0.addon.name == "Mock Catalog" })
        let fastMovies = try #require(model.sources.last { $0.catalog.id == "mock-movies" })
        let pending = Task { await model.select(source: slowTop) }
        try await Task.sleep(for: .milliseconds(150))
        await model.select(source: fastMovies)
        await pending.value
        #expect(model.selectedSource == fastMovies)
        #expect(model.items.count == 20, "the late slow answer was discarded")
    }

    @Test func failuresAreReportedAndReloadRecovers() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL(flags: ["badjson"]).absoluteString)
        let model = DiscoverViewModel(services: services)
        await model.loadSources()
        #expect(model.state == .failed(.invalidJSON))
        #expect(model.items.isEmpty)
    }
}
