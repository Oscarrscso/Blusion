import Foundation
import PlayerKit
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

    /// Services that never reach the network: for the parts of Detail that read the preview alone.
    private func offlineServices() -> AppServices {
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: 1, maxRetries: 0))
        return AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client), client: client)
    }

    /// Services with the mock catalog addon installed, so Detail can load the mock's movies and two-season series.
    private func installedServices() async throws -> AppServices {
        let server = try MockServer.shared()
        let services = services(server)
        _ = try await services.registry.install(from: server.catalogManifestURL().absoluteString)
        return services
    }

    /// The mock's series (two seasons of three episodes), loaded.
    private func loadedSeries(_ services: AppServices) async -> DetailViewModel {
        let model = DetailViewModel(preview: MetaPreview(id: "mock:series1", type: "series", name: "S"), services: services)
        await model.load()
        return model
    }

    /// Saves unwatched progress for a movie or episode, as the player does while it plays.
    private func saveProgress(_ services: AppServices, id: String, type: String, position: TimeInterval, duration: TimeInterval,
                              updatedAt: Date, season: Int? = nil, episode: Int? = nil) async {
        await services.progress.save(WatchProgress(id: "\(type)/\(id)", type: type, contentID: id, title: id, position: position,
                                                   duration: duration, isWatched: false, updatedAt: updatedAt, season: season, episode: episode))
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

    @Test func nextUpIsTheFirstEpisodeOfAFreshSeries() async throws {
        let services = try await installedServices()
        let model = await loadedSeries(services)
        #expect(model.nextUp?.id == "mock:series1:1:1")
        #expect(model.primaryActionTitle == "Play S1 · E1")
        #expect(model.selectedSeason == 1, "the season of the next episode is the one shown")
    }

    @Test func nextUpIsTheFirstUnwatchedEpisodeInWatchingOrder() async throws {
        let services = try await installedServices()
        let model = await loadedSeries(services)
        for video in model.episodes.prefix(2) {
            await model.setWatched(true, for: model.request(for: video))
        }
        #expect(model.nextUp?.id == "mock:series1:1:3")
        #expect(model.primaryActionTitle == "Play S1 · E3")
    }

    @Test func nextUpFallsBackToTheFirstEpisodeWhenEverythingIsWatched() async throws {
        let services = try await installedServices()
        let model = await loadedSeries(services)
        for video in model.detail.videos {
            await model.setWatched(true, for: model.request(for: video))
        }
        #expect(model.nextUp?.id == "mock:series1:1:1")
        #expect(model.primaryActionTitle == "Play S1 · E1")
    }

    @Test func nextUpIsTheMostRecentlyUpdatedUnfinishedEpisode() async throws {
        let services = try await installedServices()
        let model = await loadedSeries(services)
        await saveProgress(services, id: "mock:series1:2:2", type: "series", position: 300, duration: 1200,
                           updatedAt: Date().addingTimeInterval(-600), season: 2, episode: 2)
        await saveProgress(services, id: "mock:series1:1:3", type: "series", position: 60, duration: 1200,
                           updatedAt: Date().addingTimeInterval(-60), season: 1, episode: 3)
        await model.refreshUserState()
        #expect(model.nextUp?.id == "mock:series1:1:3", "the episode watched most recently wins, though S1 E1 is still unwatched")
        #expect(model.primaryActionTitle == "Resume S1 · E3")
        let video = try #require(model.detail.videos.first(where: { $0.id == "mock:series1:1:3" }))
        #expect(model.progressFraction(for: video) == 0.05)
        #expect(model.progressFraction(for: model.request(for: video)) == 0.05)
    }

    @Test func primaryActionResumesOnlyWhenThereIsResumableProgress() async throws {
        let services = try await installedServices()
        let model = DetailViewModel(preview: MetaPreview(id: "mock:movie3", type: "movie", name: "P"), services: services)
        await model.load()
        #expect(model.primaryActionTitle == "Play")
        #expect(model.progressFraction(for: model.movieRequest) == nil, "not started: no bar")
        await saveProgress(services, id: "mock:movie3", type: "movie", position: 600, duration: 6000, updatedAt: Date())
        await model.refreshUserState()
        #expect(model.primaryActionTitle == "Resume")
        #expect(model.progressFraction(for: model.movieRequest) == 0.1)
        await model.setWatched(true, for: model.movieRequest)
        #expect(model.primaryActionTitle == "Play")
        #expect(model.progressFraction(for: model.movieRequest) == nil, "watched: no bar")
    }

    @Test func trailerURLIsTheFirstTrailerWithAWellFormedYouTubeID() async throws {
        let json = #"""
        {"meta":{"id":"tt0468569","type":"movie","name":"The Dark Knight",
         "trailerStreams":[{"title":"Bad","ytId":"not an id"},{"title":"Trailer","ytId":"EXeTwQWrcwY"},{"title":"Other","ytId":"zZZ999"}]}}
        """#
        let transport = StubTransport { request, _ in StubTransport.response(Data(json.utf8), for: request) }
        let manifest = Manifest(id: "test.stubmeta", name: "Stub", version: "1", resources: [ResourceDescriptor(name: "meta")], types: ["movie"])
        let (registry, client) = try await makeStubbedRegistry(manifests: [manifest], transport: transport)
        let model = DetailViewModel(preview: MetaPreview(id: "tt0468569", type: "movie", name: "The Dark Knight"),
                                    services: AppServices(registry: registry, client: client))
        await model.load()
        #expect(!model.isFallback)
        #expect(model.trailerURL?.absoluteString == "https://www.youtube.com/watch?v=EXeTwQWrcwY")
    }

    @Test func aWholeShowCanBeMarkedWatchedAndUnmarked() async throws {
        let services = try await installedServices()
        let model = await loadedSeries(services)
        #expect(!model.isSeriesWatched && !model.isSeasonWatched(1))
        await model.setSeriesWatched(true)
        #expect(model.isSeriesWatched && model.isSeasonWatched(1) && model.isSeasonWatched(2))
        #expect(model.watchedIdentities.count == 6, "every episode of both seasons")
        let saved = await services.progress.progress(for: "series/mock:series1:2:3")
        #expect(saved?.isWatched == true && saved?.season == 2 && saved?.episode == 3)
        await model.setSeriesWatched(false)
        #expect(!model.isSeriesWatched && model.watchedIdentities.isEmpty)
        let cleared = await services.progress.progress(for: "series/mock:series1:2:3")
        #expect(cleared == nil)
    }

    @Test func aSeasonIsMarkedOnItsOwn() async throws {
        let model = await loadedSeries(try await installedServices())
        await model.setSeasonWatched(true, season: 1)
        #expect(model.isSeasonWatched(1) && !model.isSeasonWatched(2) && !model.isSeriesWatched)
        #expect(model.watchedIdentities.count == 3)
        #expect(model.nextUp?.season == 2, "the next episode moves to the season after")
        await model.setSeasonWatched(false, season: 1)
        #expect(model.watchedIdentities.isEmpty)
    }

    @Test func markingAShowSkipsEpisodesThatHaveNotAiredYet() async throws {
        let json = #"""
        {"meta":{"id":"tt7000001","type":"series","name":"Ongoing","videos":[
          {"id":"tt7000001:1:1","title":"Out","season":1,"episode":1,"released":"2001-01-01T00:00:00.000Z"},
          {"id":"tt7000001:1:2","title":"Soon","season":1,"episode":2,"released":"2999-01-01T00:00:00.000Z"}]}}
        """#
        let transport = StubTransport { request, _ in StubTransport.response(Data(json.utf8), for: request) }
        let manifest = Manifest(id: "test.stubmeta", name: "Stub", version: "1", resources: [ResourceDescriptor(name: "meta")], types: ["series"])
        let (registry, client) = try await makeStubbedRegistry(manifests: [manifest], transport: transport)
        let model = DetailViewModel(preview: MetaPreview(id: "tt7000001", type: "series", name: "Ongoing"),
                                    services: AppServices(registry: registry, client: client))
        await model.load()
        await model.setSeriesWatched(true)
        #expect(model.watchedIdentities == ["series/tt7000001:1:1"])
        #expect(model.isSeriesWatched, "the show counts as watched once everything that has aired is")
    }

    @Test func anOMDbScoreBeatsTheAddonsOneAndTheAddonsFillsTheRest() async throws {
        let transport = StubTransport(data: Data(#"{"Response":"True","Episodes":[{"Episode":"1","imdbRating":"8.9"}]}"#.utf8))
        let client = AddonClient(configuration: AddonClientConfiguration(timeout: 1, maxRetries: 0), transport: transport)
        let ratings = PosterRatingsStore(omdb: OMDbRatings(client: client, apiKey: "test-key"))
        let services = AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client),
                                   client: client, posterRatings: ratings)
        let model = DetailViewModel(preview: MetaPreview(id: "tt0944947", type: "series", name: "S"), services: services)
        let first = Video(id: "tt0944947:1:1", season: 1, episode: 1, rating: 6)
        let second = Video(id: "tt0944947:1:2", season: 1, episode: 2, rating: 7.5)
        #expect(model.score(for: first) == .init(value: 6, isIMDb: false))
        await model.loadEpisodeScores(season: 1)
        #expect(model.score(for: first) == .init(value: 8.9, isIMDb: true))
        #expect(model.score(for: second) == .init(value: 7.5, isIMDb: false))
        #expect(model.score(for: Video(id: "x")) == nil)
    }

    @Test(arguments: [false, true])
    func episodesLoadIMDbFirstEvenWhenTheAddonUsesItsOwnSeriesID(usesAddonID: Bool) async throws {
        let seriesID = usesAddonID ? "addon:show" : "tt0944947"
        let meta = #"{"meta":{"id":"\#(seriesID)","type":"series","name":"Show","videos":[{"id":"tt0944947:1:1","season":1,"episode":1}]}}"#
        let transport = StubTransport { request, _ in
            let json = request.url?.host == "www.omdbapi.com"
                ? #"{"Response":"True","Episodes":[{"Episode":"1","imdbRating":"8.9"}]}"# : meta
            return StubTransport.response(Data(json.utf8), for: request)
        }
        let manifest = Manifest(id: "test.meta", name: "Meta", version: "1", resources: [ResourceDescriptor(name: "meta")], types: ["series"])
        let (registry, client) = try await makeStubbedRegistry(manifests: [manifest], transport: transport)
        let ratings = PosterRatingsStore(omdb: OMDbRatings(client: client, apiKey: "test-key"),
                                         tmdb: TMDbRatings(client: client, readAccessToken: "test-token"))
        let model = DetailViewModel(preview: MetaPreview(id: seriesID, type: "series"),
                                    services: AppServices(registry: registry, client: client, posterRatings: ratings))
        await model.load()
        let episode = try #require(model.episodes.first)
        #expect(model.score(for: episode) == .init(value: 8.9, isIMDb: true))
        #expect(transport.requests.filter { $0.url?.host == "www.omdbapi.com" }.count == 1)
        #expect(!transport.requests.contains { $0.url?.host == "api.themoviedb.org" }, "IMDb already covered the season")
    }

    @Test func trailerURLIsNilWithoutTrailers() {
        let model = DetailViewModel(preview: MetaPreview(id: "tt1", type: "movie", name: "X"), services: offlineServices())
        #expect(model.trailerURL == nil)
    }

    @Test(arguments: [false, true])
    func detailUsesSeparateOriginalHeroesInsteadOfCatalogPosters(hasArtwork: Bool) async throws {
        let transport = StubTransport { request, _ in
            let json: String
            switch request.url?.lastPathComponent {
            case "tt0468569": json = #"{"movie_results":[{"id":155}]}"#
            case "images":
                json = #"""
                {"backdrops":[{"file_path":"/backdrop.jpg"}],
                 "posters":[{"file_path":"/poster.jpg"}],
                 "logos":[{"file_path":"/logo.png","iso_639_1":"en"}]}
                """#
            default: json = #"{"results":[]}"#
            }
            return StubTransport.response(Data(json.utf8), for: request)
        }
        let client = makeClient(transport)
        let services = AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client),
                                   client: client, settings: InMemorySettingsStore(PlaybackSettings(tmdbReadToken: "test-key")))
        let poster = URL(string: "https://example.com/poster.jpg")
        let backdrop = URL(string: "https://example.com/backdrop.jpg")
        let logo = URL(string: "https://example.com/logo.png")
        let preview = MetaPreview(id: "tt0468569", type: "movie", name: "Film", poster: hasArtwork ? poster : nil,
                                  background: hasArtwork ? backdrop : nil, logo: hasArtwork ? logo : nil)
        let model = DetailViewModel(preview: preview, services: services)
        await model.load()
        #expect(model.tmdbArtwork != nil)
        #expect(model.portraitArtworkURL == URL(string: "https://image.tmdb.org/t/p/original/poster.jpg"))
        #expect(model.backdropURL == URL(string: "https://image.tmdb.org/t/p/original/backdrop.jpg"))
        #expect(model.portraitArtworkURL != model.backdropURL)
        #expect(model.logoURL == (hasArtwork ? logo : URL(string: "https://image.tmdb.org/t/p/original/logo.png")))
        let openedFromHome = DetailViewModel(preview: preview, services: services, artwork: model.tmdbArtwork)
        #expect(!openedFromHome.isLoadingArtwork)
        #expect(openedFromHome.portraitArtworkURL == model.portraitArtworkURL)
        #expect(openedFromHome.backdropURL == model.backdropURL)
    }

    @Test func heroLoadingWaitsForArtworkAndFallsBackWithoutUsingTheCatalogPoster() async {
        let background = URL(string: "https://example.com/hero.jpg")
        let preview = MetaPreview(id: "tt0468569", type: "movie", name: "Film", poster: URL(string: "https://example.com/poster.jpg"),
                                  background: background)
        let model = DetailViewModel(preview: preview, services: offlineServices())
        #expect(model.isLoadingArtwork)
        #expect(model.portraitArtworkURL == nil && model.backdropURL == nil)
        await model.load()
        #expect(!model.isLoadingArtwork)
        #expect(model.portraitArtworkURL == background && model.backdropURL == background)
    }

    @Test func metaPartsAreYearAndRuntime() {
        let model = DetailViewModel(preview: MetaPreview(id: "tt0468569", type: "movie", name: "The Dark Knight", releaseInfo: "2008",
                                                         imdbRating: 9.0, runtime: "152 min"),
                                    services: offlineServices())
        #expect(model.metaParts == ["2008", "152 min"], "the rating is a button under the title, not part of the line")
        let bare = DetailViewModel(preview: MetaPreview(id: "tt1", type: "movie", name: "X", releaseInfo: " ", imdbRating: 0),
                                   services: offlineServices())
        #expect(bare.metaParts.isEmpty, "blank years add no parts")
    }
}
