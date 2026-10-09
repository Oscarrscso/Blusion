import Foundation
import Testing
@testable import StremioKit
import StremioKitTestSupport

@Suite struct ReviewRatingsTests {
    private let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0In0.signature"
    private let findTV = Data(#"{"movie_results":[],"tv_results":[{"id":1399,"vote_average":8.4,"vote_count":50}]}"#.utf8)

    @Test func aReadAccessTokenGoesInTheBearerHeaderNeverInTheURL() async throws {
        let transport = StubTransport(data: findTV)
        let ratings = try await TMDbRatings(client: makeClient(transport), readAccessToken: jwt).ratings(imdbID: "tt0944947", type: "series")
        #expect(ratings.tmdb == 8.4 && ratings.tmdbURL?.absoluteString == "https://www.themoviedb.org/tv/1399")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.themoviedb.org/3/find/tt0944947?external_source=imdb_id")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(jwt)")
        #expect(request.url?.absoluteString.contains(jwt) == false)
    }

    @Test func aV3ApiKeyGoesInTheQueryInsteadOfAHeader() async throws {
        let transport = StubTransport(data: findTV)
        _ = try await TMDbRatings(client: makeClient(transport), readAccessToken: "0123456789abcdef0123456789abcdef").ratings(imdbID: "tt0944947", type: "series")
        let request = try #require(transport.requests.first)
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.contains(URLQueryItem(name: "api_key", value: "0123456789abcdef0123456789abcdef")) == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func pastedTokensAreTrimmedAndAPastedBearerPrefixIsDropped() async throws {
        let transport = StubTransport(data: findTV)
        _ = try await TMDbRatings(client: makeClient(transport), readAccessToken: "  Bearer \(jwt)\n").ratings(imdbID: "tt0944947", type: "series")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(jwt)")
    }

    @Test func invalidIDsOrEmptyTokensDoNotSendRequests() async throws {
        let transport = StubTransport(data: findTV)
        let badID = try await TMDbRatings(client: makeClient(transport), readAccessToken: jwt).ratings(imdbID: "title/id", type: "movie")
        let noToken = try await TMDbRatings(client: makeClient(transport), readAccessToken: " \n ").ratings(imdbID: "tt0468569", type: "movie")
        let badType = try await TMDbRatings(client: makeClient(transport), readAccessToken: jwt).ratings(imdbID: "tt0468569", type: "anime")
        let noEpisodes = try await TMDbRatings(client: makeClient(transport), readAccessToken: "").seasonEpisodeRatings(seriesIMDbID: "tt0944947", season: 1)
        #expect(badID.isEmpty && noToken.isEmpty && badType.isEmpty && noEpisodes.isEmpty && transport.callCount == 0)
    }

    @Test func aRefusedTokenThrowsSoTheCallerCanSayWhy() async throws {
        let transport = StubTransport(data: Data(#"{"success":false,"status_code":7,"status_message":"Invalid API key"}"#.utf8), status: 401)
        let client = TMDbRatings(client: makeClient(transport), readAccessToken: jwt)
        await #expect(throws: AddonError.http(status: 401)) {
            try await client.ratings(imdbID: "tt0468569", type: "movie")
        }
        #expect(transport.callCount == 1, "a 401 is not retried")
    }

    @Test func tmdbResolvesTheCorrectKindAndNeverInventsRatingsForUnratedTitles() throws {
        let data = Data(#"{"movie_results":[{"id":155,"vote_average":9.1,"vote_count":20}],"tv_results":[{"id":1399,"vote_average":8.4,"vote_count":50}]}"#.utf8)
        #expect(try TMDbRatings.parse(data, type: "series").tmdb == 8.4)
        let movie = try TMDbRatings.parse(data, type: "movie")
        #expect(movie.tmdb == 9.1 && movie.tmdbURL?.lastPathComponent == "155")

        let unrated = Data(#"{"movie_results":[{"id":155,"vote_average":0,"vote_count":0}],"tv_results":[]}"#.utf8)
        let unratedMovie = try TMDbRatings.parse(unrated, type: "movie")
        #expect(unratedMovie.tmdb == nil && unratedMovie.tmdbURL != nil)
        #expect(try TMDbRatings.parse(unrated, type: "series").isEmpty)
        #expect(throws: AddonError.invalidJSON) { try TMDbRatings.parse(Data("{}".utf8), type: "movie") }
        #expect(throws: AddonError.invalidJSON) { try TMDbRatings.parse(Data("not json".utf8), type: "movie") }
    }

    @Test func seasonEpisodeScoresComeFromTheSeriesFindThenTheSeasonEndpoint() async throws {
        let season = Data(#"""
        {"episodes":[
          {"episode_number":1,"vote_average":8.1,"vote_count":12},
          {"episode_number":2,"vote_average":0,"vote_count":0},
          {"episode_number":3,"vote_average":11,"vote_count":4},
          {"episode_number":4,"vote_average":7.25,"vote_count":3},
          {"vote_average":9,"vote_count":9}
        ]}
        """#.utf8)
        let transport = StubTransport { request, call in
            call == 1 ? StubTransport.response(self.findTV, for: request) : StubTransport.response(season, for: request)
        }
        let scores = try await TMDbRatings(client: makeClient(transport), readAccessToken: jwt)
            .seasonEpisodeRatings(seriesIMDbID: "tt0944947", season: 2)
        #expect(scores == [1: 8.1, 4: 7.25])
        #expect(transport.requests.count == 2)
        #expect(transport.requests[1].url?.absoluteString == "https://api.themoviedb.org/3/tv/1399/season/2")
        #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(jwt)")
    }

    @Test func aSeriesOrSeasonTMDbDoesNotKnowIsEmptyNotAnError() async throws {
        let unknownShow = StubTransport(data: Data(#"{"movie_results":[],"tv_results":[]}"#.utf8))
        let none = try await TMDbRatings(client: makeClient(unknownShow), readAccessToken: jwt).seasonEpisodeRatings(seriesIMDbID: "tt0944947", season: 1)
        #expect(none.isEmpty && unknownShow.callCount == 1)

        let missingSeason = StubTransport { request, call in
            call == 1 ? StubTransport.response(self.findTV, for: request) : StubTransport.response(Data("{}".utf8), status: 404, for: request)
        }
        let absent = try await TMDbRatings(client: makeClient(missingSeason), readAccessToken: jwt).seasonEpisodeRatings(seriesIMDbID: "tt0944947", season: 9)
        #expect(absent.isEmpty)
    }

    @Test func aRefusedSeasonRequestThrowsWithTheStatus() async throws {
        let transport = StubTransport { request, call in
            call == 1 ? StubTransport.response(self.findTV, for: request) : StubTransport.response(Data("{}".utf8), status: 401, for: request)
        }
        let client = TMDbRatings(client: makeClient(transport), readAccessToken: jwt)
        await #expect(throws: AddonError.http(status: 401)) {
            try await client.seasonEpisodeRatings(seriesIMDbID: "tt0944947", season: 1)
        }
    }

    @Test func linksUseKnownIDsAndSearchForUnknownSlugsWithoutLeakingQuerySyntax() throws {
        let movie = MetaPreview(id: "tt0468569", type: "movie", name: "Film / #? & more")
        #expect(ReviewSite.imdb.url(for: movie)?.absoluteString == "https://www.imdb.com/title/tt0468569/")
        #expect(ReviewSite.letterboxd.url(for: movie)?.absoluteString == "https://letterboxd.com/imdb/tt0468569/")
        for site in [ReviewSite.rottenTomatoes, .metacritic, .tmdb] { #expect(site.isSearch(for: movie)) }
        let tomatoURL = try #require(ReviewSite.rottenTomatoes.url(for: movie))
        let parameters = URLComponents(url: tomatoURL, resolvingAgainstBaseURL: false)?.queryItems
        #expect(parameters == [URLQueryItem(name: "search", value: movie.name)])
        #expect(ReviewSite.metacritic.url(for: movie)?.query == nil)
        let direct = URL(string: "https://www.themoviedb.org/movie/155")
        #expect(ReviewSite.tmdb.url(for: movie, tmdbURL: direct) == direct)
        #expect(!ReviewSite.tmdb.isSearch(for: movie, tmdbURL: direct))
        #expect(ReviewSite.letterboxd.isSearch(for: MetaPreview(id: movie.id, type: "series")))
    }

    private let season = Data(#"""
    {"Title":"Show","Season":"1","totalSeasons":"3","Response":"True","Episodes":[
      {"Title":"Pilot","Released":"2011-04-17","Episode":"1","imdbRating":"9.1","imdbID":"tt1480055"},
      {"Title":"Second","Released":"2011-04-24","Episode":"2","imdbRating":"8.8","imdbID":"tt1668746"},
      {"Title":"Unrated","Released":"2011-05-01","Episode":"3","imdbRating":"N/A","imdbID":"tt1668747"},
      {"Title":"Broken","Released":"N/A","Episode":"x","imdbRating":"7.0","imdbID":"tt1668748"},
      {"Title":"Out of range","Released":"N/A","Episode":"5","imdbRating":"11.2","imdbID":"tt1668749"}]}
    """#.utf8)

    @Test func omdbSeasonAnswersGiveEpisodeScoresAndSkipUnusableOnes() throws {
        #expect(try OMDbRatings.parseSeason(season) == [1: 9.1, 2: 8.8])
    }

    @Test func omdbSeasonRequestsCarryTheSeasonNumber() async throws {
        let transport = StubTransport(data: season)
        let scores = try await OMDbRatings(client: makeClient(transport), apiKey: "test-key").episodeRatings(imdbID: "tt0944947", season: 1)
        #expect(scores == [1: 9.1, 2: 8.8])
        let url = try #require(transport.requests.first?.url)
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(parameters?.contains(URLQueryItem(name: "Season", value: "1")) == true)
        #expect(parameters?.contains(URLQueryItem(name: "i", value: "tt0944947")) == true)
        let invalid = try await OMDbRatings(client: makeClient(transport), apiKey: "test-key").episodeRatings(imdbID: "kitsu:1", season: 1)
        let noKey = try await OMDbRatings(client: makeClient(transport), apiKey: "").episodeRatings(imdbID: "tt0944947", season: 1)
        #expect(invalid.isEmpty && noKey.isEmpty && transport.callCount == 1)
    }

    @Test func omdbMissingSeasonsAreEmptyButBadKeysAndQuotasStillThrow() throws {
        #expect(try OMDbRatings.parseSeason(Data(#"{"Response":"False","Error":"Series or season not found!"}"#.utf8)).isEmpty)
        #expect(throws: AddonError.http(status: 401)) {
            try OMDbRatings.parseSeason(Data(#"{"Response":"False","Error":"Invalid API key!"}"#.utf8))
        }
        #expect(throws: AddonError.http(status: 429)) {
            try OMDbRatings.parseSeason(Data(#"{"Response":"False","Error":"Request limit reached!"}"#.utf8))
        }
        #expect(throws: AddonError.invalidJSON) { try OMDbRatings.parseSeason(Data("{}".utf8)) }
    }

    @Test func episodeScoresSurviveTheCacheFile() throws {
        let current = CachedRating(rating: nil, fetchedAt: Date(timeIntervalSince1970: 100), episodes: [1: 9.1, 12: 7.4])
        #expect(try JSONDecoder().decode(CachedRating.self, from: JSONEncoder().encode(current)) == current)
    }

    @Test func extendedCachesDecodeOldAnswersAndRoundTripNewScores() throws {
        let legacy = Data(#"{"rating":4.5,"fetchedAt":100}"#.utf8)
        let decoded = try JSONDecoder().decode(CachedRating.self, from: legacy)
        #expect(decoded.rating == 4.5 && decoded.reviews == nil)
        // Existing cached scores from either provider survive the merged build.
        let combined = Data(#"{"rating":null,"fetchedAt":100,"reviews":{"imdb":8.7,"rottenTomatoes":91,"tmdb":8.4}}"#.utf8)
        #expect(try JSONDecoder().decode(CachedRating.self, from: combined).reviews == ReviewRatings(imdb: 8.7, rottenTomatoes: 91, tmdb: 8.4))
        let current = CachedRating(rating: nil, fetchedAt: Date(), reviews: ReviewRatings(tmdb: 7.5, tmdbURL: URL(string: "https://www.themoviedb.org/movie/1")))
        #expect(try JSONDecoder().decode(CachedRating.self, from: JSONEncoder().encode(current)) == current)
    }
}
