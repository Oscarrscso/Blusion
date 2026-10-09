import Foundation
import Testing
import StremioKit
import StremioKitTestSupport
@testable import Features

@MainActor
@Suite struct PosterRatingsTests {
    private let movie = MetaPreview(id: "tt0468569", type: "movie", name: "Film", imdbRating: 9)
    private let page = Data(#"<meta name="twitter:data2" content="4.5 out of 5">"#.utf8)
    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(_ transport: StubTransport, cache: any RatingsCache = InMemoryRatingsCache(), enabled: Bool = true,
                       now: @escaping @Sendable () -> Date = { Date() }) -> PosterRatingsStore {
        PosterRatingsStore(isEnabled: enabled, letterboxd: LetterboxdRatings(client: makeClient(transport, retries: 0)), cache: cache, now: now)
    }

    @Test func entriesAreStablePerTypeAndIDAndFillIMDbAsynchronously() async throws {
        let store = PosterRatingsStore()
        let missing = MetaPreview(id: movie.id, type: "movie")
        let first = store.ratings(for: missing)
        let second = store.ratings(for: movie)
        let same = first === second
        #expect(same)
        #expect(first.imdb == nil, "asking from a view body must not synchronously change an observed rating")
        try await waitUntil { first.imdb == 9 }
        let series = store.ratings(for: MetaPreview(id: movie.id, type: "series"))
        let different = first !== series
        #expect(different)
    }

    @Test func aMovieIsLookedUpOnlyOnceAndFormatsBothRatings() async throws {
        let transport = StubTransport(data: page, status: 206)
        let store = store(transport)
        let entry = store.ratings(for: movie)
        for _ in 0..<50 { _ = store.ratings(for: movie) }
        try await waitUntil { entry.letterboxd == 4.5 }
        _ = store.ratings(for: movie)
        #expect(transport.callCount == 1)
        #expect(entry.imdbText == "9.0" && entry.letterboxdText == "9.0")
        #expect(entry.text(for: .letterboxd) == "9.0/10")
        #expect(!entry.isEmpty)
    }

    @Test func seriesInvalidIDsAndDisabledRatingsNeverRequest() async throws {
        let transport = StubTransport(data: page)
        let store = store(transport)
        _ = store.ratings(for: MetaPreview(id: movie.id, type: "series"))
        _ = store.ratings(for: MetaPreview(id: "kitsu:1", type: "movie"))
        store.isEnabled = false
        let entry = store.ratings(for: movie)
        try await Task.sleep(for: .milliseconds(50))
        #expect(entry.imdb == 9 && entry.letterboxd == nil)
        #expect(transport.callCount == 0)
        store.isEnabled = true
        _ = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4.5 }
        #expect(transport.callCount == 1)
    }

    @Test func aFreshCachedRatingSkipsTheRequest() async throws {
        let cache = InMemoryRatingsCache()
        await cache.store(CachedRating(rating: 4, fetchedAt: when.addingTimeInterval(-6 * 86_400)), for: movie.id)
        let transport = StubTransport(data: page)
        let store = store(transport, cache: cache, now: { when })
        let entry = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4 }
        #expect(transport.callCount == 0)
    }

    @Test func sevenDayOldRatingsAreRefetched() async throws {
        let cache = InMemoryRatingsCache()
        await cache.store(CachedRating(rating: 4, fetchedAt: when.addingTimeInterval(-7 * 86_400)), for: movie.id)
        let transport = StubTransport(data: page)
        let store = store(transport, cache: cache, now: { when })
        let entry = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4.5 }
        let saved = await cache.value(for: movie.id)
        #expect(transport.callCount == 1)
        #expect(saved == CachedRating(rating: 4.5, fetchedAt: when))
    }

    @Test func noRatingAnswersExpireAfterAnHourInTheSameSession() async throws {
        let clock = RatingsTestState(now: when)
        let cache = InMemoryRatingsCache()
        await cache.store(CachedRating(rating: nil, fetchedAt: when.addingTimeInterval(-1_800)), for: movie.id)
        let transport = StubTransport(data: page)
        let store = store(transport, cache: cache, now: { clock.date })
        let entry = store.ratings(for: movie)
        try await Task.sleep(for: .milliseconds(50))
        #expect(entry.letterboxd == nil && transport.callCount == 0)
        clock.advance(1_800)
        _ = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4.5 }
        #expect(transport.callCount == 1)
    }

    @Test func successfulEmptyAnswersAreCached() async throws {
        let cache = InMemoryRatingsCache()
        let transport = StubTransport(data: Data("<head></head>".utf8))
        let store = store(transport, cache: cache, now: { when })
        _ = store.ratings(for: movie)
        try await waitUntil { transport.callCount == 1 }
        try await Task.sleep(for: .milliseconds(20))
        let stored = await cache.value(for: movie.id)
        #expect(stored == CachedRating(rating: nil, fetchedAt: when))
    }

    @Test func failuresAreNotCachedAndCanRetryAfterAMinute() async throws {
        let clock = RatingsTestState(now: when)
        let cache = InMemoryRatingsCache()
        let transport = StubTransport { request, call in
            if call == 1 { throw AddonError.offline }
            return StubTransport.response(Data(#"<meta name="twitter:data2" content="4.5">"#.utf8), for: request)
        }
        let store = store(transport, cache: cache, now: { clock.date })
        let entry = store.ratings(for: movie)
        try await waitUntil { transport.callCount == 1 }
        try await Task.sleep(for: .milliseconds(20))
        let stored = await cache.value(for: movie.id)
        #expect(stored == nil)
        clock.advance(59)
        _ = store.ratings(for: movie)
        try await Task.sleep(for: .milliseconds(20))
        #expect(transport.callCount == 1 && entry.letterboxd == nil)
        clock.advance(1)
        _ = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4.5 }
        #expect(transport.callCount == 2)
    }

    @Test func tenMoviesUseAtMostThreeLookupsAndKeepQueueOrder() async throws {
        let state = RatingsTestState(now: when)
        let transport = StubTransport { request, _ in
            state.started()
            defer { state.finished() }
            try await Task.sleep(for: .milliseconds(40))
            return StubTransport.response(Data(#"<meta name="twitter:data2" content="4.5">"#.utf8), for: request)
        }
        let store = store(transport)
        let items = (0..<10).map { MetaPreview(id: "tt\(1_000_000 + $0)", type: "movie") }
        let entries = items.map { store.ratings(for: $0) }
        try await waitUntil { entries.allSatisfy { $0.letterboxd == 4.5 } }
        #expect(state.maximum == 3)
        #expect(transport.callCount == 10)
        #expect(Set(transport.requests.prefix(3).compactMap { $0.url?.lastPathComponent }) == Set(items.prefix(3).map(\.id)))
    }

    @Test func serialLookupsRunInTheOrderAsked() async throws {
        let transport = StubTransport(data: page)
        let store = PosterRatingsStore(letterboxd: LetterboxdRatings(client: makeClient(transport)), maxConcurrentLookups: 1)
        let items = (0..<5).map { MetaPreview(id: "tt\(1_000_000 + $0)", type: "movie") }
        let entries = items.map { store.ratings(for: $0) }
        try await waitUntil { entries.allSatisfy { $0.letterboxd == 4.5 } }
        #expect(transport.requests.compactMap { $0.url?.lastPathComponent } == items.map(\.id))
    }

    @Test func forgetAllCancelsAnOldAnswerAndKeepsIMDb() async throws {
        let cache = InMemoryRatingsCache()
        let transport = StubTransport { request, _ in
            try? await Task.sleep(for: .milliseconds(100))
            return StubTransport.response(Data(#"<meta name="twitter:data2" content="4.5">"#.utf8), for: request)
        }
        let store = store(transport, cache: cache)
        let entry = store.ratings(for: movie)
        try await waitUntil { transport.callCount == 1 }
        await store.forgetAll()
        let stored = await cache.value(for: movie.id)
        #expect(stored == nil && entry.letterboxd == nil && entry.imdb == 9)
        _ = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4.5 }
        #expect(transport.callCount == 2)
        await store.forgetAll()
        #expect(entry.letterboxd == nil && entry.imdb == 9)
    }

    @Test func postersFetchCriticScoresEvenWhenTheCatalogHasIMDb() async throws {
        let transport = StubTransport(data: Data(#"{"Response":"True","imdbRating":"8.7","Metascore":"82","Ratings":[{"Source":"Rotten Tomatoes","Value":"91%"}]}"#.utf8))
        let store = PosterRatingsStore(omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let entry = store.ratings(for: movie)
        try await waitUntil { entry.metacritic == 82 }
        #expect(entry.imdb == 9 && entry.rottenTomatoes == 91)
        #expect(entry.posterSites == [.imdb, .rottenTomatoes])
        #expect(entry.text(for: .rottenTomatoes) == "91%" && entry.text(for: .metacritic) == "82/100")
        for _ in 0..<10 { _ = store.ratings(for: movie, includeReviews: true) }
        #expect(transport.callCount == 1)
    }

    private let omdbMovie = Data(#"{"Response":"True","imdbRating":"7.4","Metascore":"N/A"}"#.utf8)
    private let omdbSeason = Data(#"{"Response":"True","Season":"2","Episodes":[{"Episode":"1","imdbRating":"8.9"},{"Episode":"2","imdbRating":"N/A"}]}"#.utf8)

    @Test func aPosterWithoutAnIMDbScoreAsksOMDbForItOnce() async throws {
        let transport = StubTransport(data: omdbMovie)
        let store = PosterRatingsStore(omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let unrated = MetaPreview(id: "tt1234567", type: "movie", name: "New")
        let entry = store.ratings(for: unrated)
        for _ in 0..<10 { _ = store.ratings(for: unrated) }
        try await waitUntil { entry.imdb == 7.4 }
        #expect(transport.callCount == 1 && entry.imdbText == "7.4")
        _ = store.ratings(for: unrated)
        #expect(transport.callCount == 1)
    }

    @Test func postersPreferTwoSourcesAndFillEitherMissingPreferredScore() {
        let entry = TitleRatings(id: "test", imdb: 8, letterboxd: 4)
        entry.rottenTomatoes = 91
        entry.metacritic = 82
        entry.tmdb = 8.4
        #expect(entry.posterSites == [.imdb, .letterboxd])
        entry.imdb = nil
        #expect(entry.posterSites == [.letterboxd, .rottenTomatoes])
        entry.letterboxd = nil
        #expect(entry.posterSites == [.rottenTomatoes, .metacritic])
        #expect(!entry.isEmpty && entry.shortText(for: .rottenTomatoes) == "91%")
        #expect(entry.shortText(for: .metacritic) == "82")
        entry.rottenTomatoes = nil
        #expect(entry.posterSites == [.metacritic, .tmdb])
        entry.metacritic = nil
        #expect(entry.posterSites == [.tmdb], "do not invent a second score for an unrated source")
        entry.tmdb = nil
        #expect(entry.posterSites.isEmpty && entry.isEmpty)
    }

    @Test(arguments: ["movie", "series"])
    func criticOnlyPostersShowTwoSourcesAndRefreshWithoutLosingThem(type: String) async throws {
        let transport = StubTransport { request, call in
            let body = call == 1
                ? #"{"Response":"True","imdbRating":"N/A","Metascore":"82","Ratings":[{"Source":"Rotten Tomatoes","Value":"91%"}]}"#
                : #"{"Response":"True","imdbRating":"N/A","Metascore":"83","Ratings":[{"Source":"Rotten Tomatoes","Value":"92%"}]}"#
            return StubTransport.response(Data(body.utf8), for: request)
        }
        let store = PosterRatingsStore(omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let item = MetaPreview(id: movie.id, type: type)
        let entry = store.ratings(for: item)
        try await waitUntil { entry.metacritic == 82 }
        #expect(entry.imdb == nil && entry.posterSites == [.rottenTomatoes, .metacritic] && !entry.isEmpty)
        await store.refresh()
        #expect(entry.rottenTomatoes == 91 && entry.metacritic == 82)
        _ = store.ratings(for: item)
        try await waitUntil { entry.metacritic == 83 }
        #expect(entry.rottenTomatoes == 92 && transport.callCount == 2)
    }

    @Test func postersFallBackToTMDbWhenOMDbAndLetterboxdFail() async throws {
        let letterboxd = StubTransport { _, _ in throw AddonError.offline }
        let omdb = StubTransport(data: Data(#"{"Response":"False","Error":"Invalid API key!"}"#.utf8))
        let tmdb = StubTransport(data: Data(#"{"movie_results":[{"id":155,"vote_average":8.4,"vote_count":100}]}"#.utf8))
        let store = PosterRatingsStore(letterboxd: LetterboxdRatings(client: makeClient(letterboxd, retries: 0)),
                                       omdb: OMDbRatings(client: makeClient(omdb, retries: 0), apiKey: "bad"),
                                       tmdb: TMDbRatings(client: makeClient(tmdb), readAccessToken: "test-token"))
        let entry = store.ratings(for: movie)
        try await waitUntil { entry.tmdb == 8.4 && store.omdbError != nil }
        #expect(entry.posterSites == [.imdb, .tmdb])
        #expect(entry.shortText(for: .tmdb) == "8.4")
        for _ in 0..<10 { _ = store.ratings(for: movie) }
        #expect(tmdb.callCount == 1 && omdb.callCount == 1)
    }

    @Test func aRefusedOMDbKeyStopsEveryOtherLookupUntilCredentialsChange() async throws {
        let transport = StubTransport(data: Data(#"{"Response":"False","Error":"Invalid API key!"}"#.utf8))
        let store = PosterRatingsStore(maxConcurrentLookups: 1, omdb: OMDbRatings(client: makeClient(transport, retries: 0), apiKey: "bad"))
        let items = (0..<4).map { MetaPreview(id: "tt\(2_000_000 + $0)", type: "movie") }
        for item in items { _ = store.ratings(for: item) }
        try await waitUntil { transport.callCount >= 1 }
        try await Task.sleep(for: .milliseconds(80))
        #expect(transport.callCount == 1, "the first refusal pauses the rest")
        #expect(store.omdbError?.contains("rejected") == true)
        let scores = await store.episodeRatings(for: "tt0944947", season: 1)
        #expect(scores.isEmpty && transport.callCount == 1)
        await store.setReviewServices(omdb: OMDbRatings(client: makeClient(transport, retries: 0), apiKey: "good"), tmdb: nil)
        _ = store.ratings(for: MetaPreview(id: "tt3000000", type: "movie"))
        try await waitUntil { transport.callCount == 2 }
    }

    @Test func savingAKeyRefreshesExistingPostersAndBypassesCachedMisses() async throws {
        let cache = InMemoryRatingsCache()
        let unrated = MetaPreview(id: "tt1234567", type: "movie")
        await cache.store(CachedRating(rating: nil, fetchedAt: when, reviews: ReviewRatings()), for: "omdb:\(unrated.id)")
        let transport = StubTransport(data: omdbMovie)
        let client = makeClient(transport)
        let store = PosterRatingsStore(cache: cache, now: { when })
        let entry = store.ratings(for: unrated)
        let services = AppServices(registry: AddonRegistry(store: InMemoryAddonStore(), secrets: InMemorySecretStore(), client: client),
                                   client: client, posterRatings: store)
        let settings = SettingsViewModel(services: services)
        await settings.load()
        settings.omdbAPIKeyText = " test-key "
        await settings.commitReviewCredentials()
        #expect(store.reviewServicesRevision == 1)
        let saved = await services.settings.load()
        #expect(saved.omdbAPIKey == "test-key")
        let refreshed = store.ratings(for: unrated)
        #expect(refreshed === entry, "visible posters keep observing the same entry")
        try await waitUntil { entry.imdb == 7.4 }
        #expect(transport.callCount == 1)
    }

    @Test func settingUpServicesAtLaunchReusesGoodCachedRatings() async throws {
        let cache = InMemoryRatingsCache()
        let item = MetaPreview(id: "tt1234567", type: "movie")
        await cache.store(CachedRating(rating: nil, fetchedAt: when, reviews: ReviewRatings(imdb: 8)), for: "omdb:\(item.id)")
        let transport = StubTransport(data: omdbMovie)
        let store = PosterRatingsStore(cache: cache, now: { when })
        await store.setReviewServices(omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"), tmdb: nil)
        let entry = store.ratings(for: item)
        try await waitUntil { entry.imdb == 8 }
        #expect(transport.callCount == 0)
    }

    @Test func refreshKeepsGoodScoresAndUpdatesThemWithoutRestarting() async throws {
        let cache = InMemoryRatingsCache()
        let item = MetaPreview(id: "tt1234567", type: "movie")
        await cache.store(CachedRating(rating: nil, fetchedAt: when, reviews: ReviewRatings(imdb: 8)), for: "omdb:\(item.id)")
        let transport = StubTransport(data: omdbMovie)
        let store = PosterRatingsStore(cache: cache, now: { when }, omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let entry = store.ratings(for: item)
        try await waitUntil { entry.imdb == 8 }
        await store.refresh()
        #expect(entry.imdb == 8, "refresh must not blank a visible score")
        _ = store.ratings(for: item)
        try await waitUntil { entry.imdb == 7.4 }
        for _ in 0..<10 { _ = store.ratings(for: item) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(transport.callCount == 1)
    }

    @Test func successfulLookupsExpireDuringTheSameSession() async throws {
        let clock = RatingsTestState(now: when)
        let transport = StubTransport { request, call in
            let body = call == 1 ? #"{"Response":"True","imdbRating":"7.4"}"# : #"{"Response":"True","imdbRating":"7.8"}"#
            return StubTransport.response(Data(body.utf8), for: request)
        }
        let store = PosterRatingsStore(now: { clock.date }, omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let item = MetaPreview(id: "tt1234567", type: "movie")
        let entry = store.ratings(for: item)
        try await waitUntil { entry.imdb == 7.4 }
        clock.advance(7 * 86_400)
        _ = store.ratings(for: item)
        try await waitUntil { entry.imdb == 7.8 }
        #expect(transport.callCount == 2)
    }

    @Test func expiredScoresSurviveOfflineFailuresAndManualRetryWorks() async throws {
        let cache = InMemoryRatingsCache()
        let cached = CachedRating(rating: 4, fetchedAt: when.addingTimeInterval(-8 * 86_400))
        await cache.store(cached, for: movie.id)
        let transport = StubTransport { request, call in
            if call == 1 { throw AddonError.offline }
            return StubTransport.response(Data(#"<meta name="twitter:data2" content="4.5">"#.utf8), for: request)
        }
        let store = store(transport, cache: cache, now: { when })
        let entry = store.ratings(for: movie)
        try await waitUntil { transport.callCount == 1 && entry.letterboxd == 4 }
        try await Task.sleep(for: .milliseconds(20))
        let retained = await cache.value(for: movie.id)
        #expect(retained == cached)
        await store.refresh()
        #expect(entry.letterboxd == 4)
        _ = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4.5 }
        #expect(transport.callCount == 2)
    }

    @Test func criticScoresWithoutIMDbDoNotHideANewerIMDbScoreForAWeek() async throws {
        let cache = InMemoryRatingsCache()
        let item = MetaPreview(id: "tt1234567", type: "movie")
        await cache.store(CachedRating(rating: nil, fetchedAt: when.addingTimeInterval(-3_600),
                                      reviews: ReviewRatings(metacritic: 82)), for: "omdb:\(item.id)")
        let transport = StubTransport(data: omdbMovie)
        let store = PosterRatingsStore(cache: cache, now: { when }, omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let entry = store.ratings(for: item)
        try await waitUntil { entry.imdb == 7.4 }
        #expect(entry.metacritic == 82 && transport.callCount == 1)
    }

    @Test func episodeScoresComeFromOMDbOncePerSeasonAndAreCached() async throws {
        let cache = InMemoryRatingsCache()
        let transport = StubTransport(data: omdbSeason)
        let store = PosterRatingsStore(cache: cache, now: { when }, omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        async let first = store.episodeRatings(for: "tt0944947", season: 2)
        async let second = store.episodeRatings(for: "tt0944947", season: 2)
        let (a, b) = await (first, second)
        #expect(a == [1: 8.9] && b == a)
        let again = await store.episodeRatings(for: "tt0944947", season: 2)
        #expect(again == a && transport.callCount == 1)
        let stored = await cache.value(for: "omdb:tt0944947:s2")
        #expect(stored == CachedRating(rating: nil, fetchedAt: when, episodes: [1: 8.9]))
        _ = await store.episodeRatings(for: "tt0944947", season: 3)
        #expect(transport.callCount == 2)
    }

    @Test func episodeScoresNeedAnOMDbKeyAndAnIMDbID() async throws {
        let transport = StubTransport(data: omdbSeason)
        let without = PosterRatingsStore()
        let withKey = PosterRatingsStore(omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let noKey = await without.episodeRatings(for: "tt0944947", season: 1)
        let notIMDb = await withKey.episodeRatings(for: "kitsu:1", season: 1)
        #expect(noKey.isEmpty && notIMDb.isEmpty && transport.callCount == 0)
    }

    @Test func refreshingEpisodesBypassesCachedMissesAndDeduplicatesTheNewAnswer() async throws {
        let cache = InMemoryRatingsCache()
        await cache.store(CachedRating(rating: nil, fetchedAt: when, episodes: [:]), for: "omdb:tt0944947:s2")
        let transport = StubTransport(data: omdbSeason)
        let store = PosterRatingsStore(cache: cache, now: { when }, omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let before = await store.episodeRatings(for: "tt0944947", season: 2)
        #expect(before.isEmpty && transport.callCount == 0)
        await store.refresh()
        let after = await store.episodeRatings(for: "tt0944947", season: 2)
        let again = await store.episodeRatings(for: "tt0944947", season: 2)
        #expect(after == [1: 8.9] && again == after && transport.callCount == 1)
    }

    @Test func episodeScoresRemainAvailableOfflineAfterTheirDailyExpiry() async throws {
        let cache = InMemoryRatingsCache()
        let cached = CachedRating(rating: nil, fetchedAt: when.addingTimeInterval(-86_400), episodes: [1: 8.9])
        await cache.store(cached, for: "omdb:tt0944947:s2")
        let transport = StubTransport { _, _ in throw AddonError.offline }
        let store = PosterRatingsStore(cache: cache, now: { when }, omdb: OMDbRatings(client: makeClient(transport, retries: 0), apiKey: "test-key"))
        let scores = await store.episodeRatings(for: "tt0944947", season: 2)
        #expect(scores == [1: 8.9] && transport.callCount == 1)
        #expect(store.omdbError?.contains("connection") == true)
        let again = await store.episodeRatings(for: "tt0944947", season: 2)
        #expect(again == scores && transport.callCount == 1)
        let retained = await cache.value(for: "omdb:tt0944947:s2")
        #expect(retained == cached)
    }

    @Test func refreshingCancelsOldAnswersBeforeTheyCanFillTheCache() async throws {
        let cache = InMemoryRatingsCache()
        let transport = StubTransport { request, call in
            if call == 1 { try? await Task.sleep(for: .milliseconds(80)) }
            let body = call == 1 ? #"{"Response":"True","imdbRating":"4.0"}"# : #"{"Response":"True","imdbRating":"8.0"}"#
            return StubTransport.response(Data(body.utf8), for: request)
        }
        let store = PosterRatingsStore(cache: cache, omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"))
        let item = MetaPreview(id: "tt1234567", type: "movie")
        let entry = store.ratings(for: item)
        try await waitUntil { transport.callCount == 1 }
        await store.refresh()
        let cancelled = await cache.value(for: "omdb:\(item.id)")
        #expect(cancelled == nil && entry.imdb == nil)
        _ = store.ratings(for: item)
        try await waitUntil { entry.imdb == 8 }
        let saved = await cache.value(for: "omdb:\(item.id)")
        #expect(saved?.reviews?.imdb == 8 && transport.callCount == 2)
    }

    @Test func reviewScoresUseTheCacheAndRemainAvailableWithPosterBadgesDisabled() async throws {
        let cache = InMemoryRatingsCache()
        await cache.store(CachedRating(rating: nil, fetchedAt: when, reviews: ReviewRatings(tmdb: 8.4,
                          tmdbURL: URL(string: "https://www.themoviedb.org/movie/155"))), for: "tmdb:\(movie.identity)")
        let transport = StubTransport(data: Data())
        let store = PosterRatingsStore(isEnabled: false, cache: cache, now: { when },
                                       tmdb: TMDbRatings(client: makeClient(transport), readAccessToken: "test-token"))
        let entry = store.ratings(for: movie, includeReviews: true)
        try await waitUntil { entry.tmdb == 8.4 }
        #expect(transport.callCount == 0 && entry.text(for: .tmdb) == "8.4/10")
        await store.forgetAll()
        #expect(entry.tmdb == nil && entry.tmdbURL == nil)
    }

    @Test func addingAndRemovingCredentialsStartsFreshLookupsAndClearsTheirVisibleScores() async throws {
        let transport = StubTransport(data: Data(#"{"Response":"True","Metascore":"82"}"#.utf8))
        let store = PosterRatingsStore()
        let entry = store.ratings(for: movie, includeReviews: true)
        #expect(entry.metacritic == nil && transport.callCount == 0)
        await store.setReviewServices(omdb: OMDbRatings(client: makeClient(transport), apiKey: "test-key"), tmdb: nil)
        #expect(store.reviewServicesRevision == 1)
        _ = store.ratings(for: movie, includeReviews: true)
        try await waitUntil { entry.metacritic == 82 }
        await store.setReviewServices(omdb: nil, tmdb: nil)
        _ = store.ratings(for: movie, includeReviews: true)
        #expect(entry.metacritic == nil && store.reviewServicesRevision == 2 && transport.callCount == 1)
    }

    @Test func openingReviewsResumesALetterboxdLookupPausedByThePosterSwitch() async throws {
        let transport = StubTransport(data: page)
        let store = store(transport)
        let entry = store.ratings(for: movie)
        store.isEnabled = false
        try await Task.sleep(for: .milliseconds(20))
        #expect(transport.callCount == 0)
        _ = store.ratings(for: movie, includeReviews: true)
        try await waitUntil { entry.letterboxd == 4.5 }
        #expect(transport.callCount == 1)
    }
}

private final class RatingsTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Date
    private var active = 0
    private var peak = 0

    init(now: Date) { self.now = now }
    var date: Date { lock.withLock { now } }
    var maximum: Int { lock.withLock { peak } }
    func advance(_ seconds: TimeInterval) { lock.withLock { now.addTimeInterval(seconds) } }
    func started() { lock.withLock { active += 1; peak = max(peak, active) } }
    func finished() { lock.withLock { active -= 1 } }
}
