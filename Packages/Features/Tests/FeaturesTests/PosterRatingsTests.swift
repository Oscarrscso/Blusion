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
    private let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0In0.signature"
    private let tmdbFindMovie = Data(#"{"movie_results":[{"id":155,"vote_average":9.1,"vote_count":20}],"tv_results":[]}"#.utf8)
    private let tmdbFindTV = Data(#"{"movie_results":[],"tv_results":[{"id":1399,"vote_average":8.4,"vote_count":50}]}"#.utf8)

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
        await cache.store(CachedRating(rating: 4, fetchedAt: when.addingTimeInterval(-20 * 86_400)), for: movie.id)
        let transport = StubTransport(data: page)
        let store = store(transport, cache: cache, now: { when })
        let entry = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4 }
        #expect(transport.callCount == 0)
    }

    @Test func twentyOneDayOldRatingsAreRefetched() async throws {
        let cache = InMemoryRatingsCache()
        await cache.store(CachedRating(rating: 4, fetchedAt: when.addingTimeInterval(-21 * 86_400)), for: movie.id)
        let transport = StubTransport(data: page)
        let store = store(transport, cache: cache, now: { when })
        let entry = store.ratings(for: movie)
        try await waitUntil { entry.letterboxd == 4.5 }
        let saved = await cache.value(for: movie.id)
        #expect(transport.callCount == 1)
        #expect(saved == CachedRating(rating: 4.5, fetchedAt: when))
    }

    @Test func noRatingAnswersExpireAfterThreeDays() async throws {
        let cache = InMemoryRatingsCache()
        await cache.store(CachedRating(rating: nil, fetchedAt: when.addingTimeInterval(-2 * 86_400)), for: movie.id)
        let transport = StubTransport(data: page)
        let fresh = store(transport, cache: cache, now: { when })
        let entry = fresh.ratings(for: movie)
        try await Task.sleep(for: .milliseconds(50))
        #expect(entry.letterboxd == nil && transport.callCount == 0)
        await cache.store(CachedRating(rating: nil, fetchedAt: when.addingTimeInterval(-3 * 86_400)), for: movie.id)
        let expired = store(transport, cache: cache, now: { when })
        let updated = expired.ratings(for: movie)
        try await waitUntil { updated.letterboxd == 4.5 }
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

    @Test func failuresAreNotCachedAndRetryOnlyAfterTenMinutes() async throws {
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
        clock.advance(599)
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

    @Test func tmdbScoresAreRequestedOnlyByTheDetailReviewRow() async throws {
        let transport = StubTransport(data: tmdbFindMovie)
        let store = PosterRatingsStore(tmdb: TMDbRatings(client: makeClient(transport), readAccessToken: jwt))
        let entry = store.ratings(for: movie)
        try await Task.sleep(for: .milliseconds(20))
        #expect(transport.callCount == 0 && entry.tmdb == nil)
        _ = store.ratings(for: movie, includeReviews: true)
        try await waitUntil { entry.tmdb == 9.1 }
        #expect(entry.imdb == 9 && entry.text(for: .tmdb) == "9.1/10")
        #expect(entry.tmdbURL?.absoluteString == "https://www.themoviedb.org/movie/155")
        for _ in 0..<10 { _ = store.ratings(for: movie, includeReviews: true) }
        #expect(transport.callCount == 1 && store.reviewServiceIssue == nil)
    }

    @Test func aRefusedTokenIsLoggedWithItsReasonAndSaidInTheReviewRow() async throws {
        let sink = MemoryLogSink()
        let transport = StubTransport(data: Data(#"{"success":false,"status_code":7}"#.utf8), status: 401)
        let store = PosterRatingsStore(tmdb: TMDbRatings(client: makeClient(transport), readAccessToken: jwt), logger: AddonLogger(sink: sink))
        let entry = store.ratings(for: movie, includeReviews: true)
        try await waitUntil { store.reviewServiceIssue != nil }
        #expect(store.reviewServiceIssue == "TMDb refused the Read Access Token. Check it in Settings.")
        #expect(entry.tmdb == nil)
        #expect(sink.lines.contains { $0.contains("tmdb lookup failed") && $0.contains("Server error (401)") })
        #expect(!sink.lines.joined().contains(jwt), "the token never reaches the log")
    }

    @Test func episodeScoresComeFromTMDbOnlyWithACredentialAndFailuresAreExplained() async throws {
        let season = Data(#"{"episodes":[{"episode_number":2,"vote_average":7.6,"vote_count":30}]}"#.utf8)
        let transport = StubTransport { request, call in
            StubTransport.response(call == 1 ? tmdbFindTV : season, for: request)
        }
        let store = PosterRatingsStore(tmdb: TMDbRatings(client: makeClient(transport), readAccessToken: jwt))
        #expect(await store.episodeRatings(seriesIMDbID: "tt0944947", season: 1) == [2: 7.6])
        #expect(await PosterRatingsStore().episodeRatings(seriesIMDbID: "tt0944947", season: 1).isEmpty)

        let sink = MemoryLogSink()
        let limited = StubTransport(data: Data("{}".utf8), status: 429)
        let failing = PosterRatingsStore(tmdb: TMDbRatings(client: makeClient(limited, retries: 0), readAccessToken: jwt), logger: AddonLogger(sink: sink))
        #expect(await failing.episodeRatings(seriesIMDbID: "tt0944947", season: 1).isEmpty)
        #expect(failing.reviewServiceIssue == "TMDb rate limit reached. Scores will return later.")
        #expect(sink.lines.contains { $0.contains("episode lookup for season 1 failed") })
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

    @Test func addingAndRemovingTheTokenStartsFreshLookupsAndClearsTheirVisibleScores() async throws {
        let transport = StubTransport(data: tmdbFindMovie)
        let store = PosterRatingsStore()
        let entry = store.ratings(for: movie, includeReviews: true)
        #expect(entry.tmdb == nil && transport.callCount == 0)
        await store.setReviewServices(tmdb: TMDbRatings(client: makeClient(transport), readAccessToken: jwt))
        #expect(store.reviewServicesRevision == 1)
        _ = store.ratings(for: movie, includeReviews: true)
        try await waitUntil { entry.tmdb == 9.1 }
        await store.setReviewServices(tmdb: nil)
        _ = store.ratings(for: movie, includeReviews: true)
        #expect(entry.tmdb == nil && store.reviewServicesRevision == 2 && transport.callCount == 1)
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
