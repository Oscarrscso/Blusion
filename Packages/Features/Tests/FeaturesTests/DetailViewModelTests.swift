import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct DetailViewModelTests {
    private func services(_ server: MockServer) -> AppServices {
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: server.slowDelay + 4, maxRetries: 0))
        return AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client), client: client)
    }

    @Test func startsFromThePreviewThenUpgradesToMeta() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let preview = MetaPreview(id: "mock:movie3", type: "movie", name: "Preview Title", poster: URL(string: "https://example.com/p.jpg"))
        let model = DetailViewModel(preview: preview, services: services)
        #expect(model.isLoading)
        #expect(model.detail.name == "Preview Title", "something to show immediately")
        await model.load()
        #expect(!model.isLoading && !model.isFallback)
        #expect(model.detail.name == "Mock Movie 3")
        #expect(model.detail.cast.count == 2)
        #expect(model.detail.preview.poster != nil)
        #expect(model.subtitle.contains("min"))
        #expect(!model.isSeries)
    }

    @Test func fallsBackToCatalogDataWhenMetaIsUnavailable() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let preview = MetaPreview(id: "mock:nometa1", type: "movie", name: "Preview Only Movie", releaseInfo: "2001")
        let model = DetailViewModel(preview: preview, services: services)
        await model.load()
        #expect(model.isFallback)
        #expect(model.detail.name == "Preview Only Movie")
        #expect(model.subtitle == "2001")
    }

    @Test func seriesExposeSeasonsAndEpisodes() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let model = DetailViewModel(preview: MetaPreview(id: "mock:series1", type: "series", name: "S"), services: services)
        await model.load()
        #expect(model.isSeries)
        #expect(model.seasons == [1, 2])
        #expect(model.selectedSeason == 1, "the first season is selected")
        #expect(model.episodes.map(\.episode) == [1, 2, 3])
        model.selectedSeason = 2
        let episode = try #require(model.episodes.first)
        let request = model.request(for: episode)
        #expect(request.type == "series")
        #expect(request.id == "mock:series1:2:1")
        #expect(request.season == 2 && request.episode == 1)
        #expect(request.title == "Mock Series One · Episode 1")
    }

    @Test func movieRequestsCarryTitlePosterAndIdentity() async throws {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        let model = DetailViewModel(preview: MetaPreview(id: "mock:movie4", type: "movie", name: "P"), services: services)
        await model.load()
        let request = model.movieRequest
        #expect(request.id == "mock:movie4")
        #expect(request.type == "movie")
        #expect(request.title == "Mock Movie 4")
        #expect(request.poster != nil)
        #expect(request.identity == "movie/mock:movie4")
    }

    @Test func requestsFromPreviewsDefaultTheType() {
        #expect(StreamRequest(movie: MetaPreview(id: "tt1", name: "X")).type == "movie")
    }
}
