import Foundation
import Testing
@testable import StremioKit
import StremioKitTestSupport

@Suite struct ReviewRatingsTests {
    private let omdb = Data(#"{"Response":"True","imdbRating":"8.7","Metascore":"82","Ratings":[{"Source":"Rotten Tomatoes","Value":"91%"}]}"#.utf8)

    @Test func omdbUsesTheIMDbIDAndReturnsNativeRatingScales() async throws {
        let transport = StubTransport(data: omdb)
        let ratings = try await OMDbRatings(client: makeClient(transport), apiKey: "test-key").ratings(imdbID: "tt0468569")
        #expect(ratings == ReviewRatings(imdb: 8.7, rottenTomatoes: 91, metacritic: 82))
        let url = try #require(transport.requests.first?.url)
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(url.host == "www.omdbapi.com" && url.scheme == "https")
        #expect(parameters?.contains(URLQueryItem(name: "i", value: "tt0468569")) == true)
        #expect(parameters?.contains(URLQueryItem(name: "apikey", value: "test-key")) == true)
    }

    @Test func invalidIDsOrMissingKeysDoNotSendRequests() async throws {
        let transport = StubTransport(data: omdb)
        let invalid = try await OMDbRatings(client: makeClient(transport), apiKey: "test-key").ratings(imdbID: "title/id")
        let noKey = try await OMDbRatings(client: makeClient(transport), apiKey: "  ").ratings(imdbID: "tt0468569")
        let noToken = try await TMDbRatings(client: makeClient(transport), readAccessToken: "").ratings(imdbID: "tt0468569", type: "movie")
        #expect(invalid.isEmpty && noKey.isEmpty && noToken.isEmpty && transport.callCount == 0)
    }

    @Test func omdbRejectsInvalidScoresAndReadsTheRatingsArrayFallback() throws {
        let bad = Data(#"""
        {"Response":"True","imdbRating":"N/A","Metascore":"101","Ratings":[
          {"Source":"Internet Movie Database","Value":"8.2/10"},
          {"Source":"Rotten Tomatoes","Value":"-2%"},{"Source":"Metacritic","Value":"79/100"}]}
        """#.utf8)
        let ratings = try OMDbRatings.parse(bad)
        #expect(ratings == ReviewRatings(imdb: 8.2, metacritic: 79))
        let malformed = Data(#"{"Response":"True","Ratings":[{"Source":"Rotten Tomatoes","Value":"0.9/1"}]}"#.utf8)
        #expect(try OMDbRatings.parse(malformed).rottenTomatoes == nil)
    }

    @Test func omdbMissingTitlesAreEmptyButInvalidKeysAndQuotasThrow() throws {
        #expect(try OMDbRatings.parse(Data(#"{"Response":"False","Error":"Movie not found!"}"#.utf8)).isEmpty)
        #expect(throws: AddonError.http(status: 401)) {
            try OMDbRatings.parse(Data(#"{"Response":"False","Error":"Invalid API key!"}"#.utf8))
        }
        #expect(throws: AddonError.http(status: 429)) {
            try OMDbRatings.parse(Data(#"{"Response":"False","Error":"Request limit reached!"}"#.utf8))
        }
        #expect(throws: AddonError.invalidJSON) { try OMDbRatings.parse(Data("{}".utf8)) }
    }

    @Test func tmdbResolvesTheCorrectKindAndSendsTheTokenInAHeader() async throws {
        let data = Data(#"{"movie_results":[{"id":155,"vote_average":9.1,"vote_count":20}],"tv_results":[{"id":1399,"vote_average":8.4,"vote_count":50}]}"#.utf8)
        let transport = StubTransport(data: data)
        let ratings = try await TMDbRatings(client: makeClient(transport), readAccessToken: "test-token").ratings(imdbID: "tt0944947", type: "series")
        #expect(ratings.tmdb == 8.4 && ratings.tmdbURL?.absoluteString == "https://www.themoviedb.org/tv/1399")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.themoviedb.org/3/find/tt0944947?external_source=imdb_id")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.url?.absoluteString.contains("test-token") == false)
        let movie = try TMDbRatings.parse(data, type: "movie")
        #expect(movie.tmdb == 9.1 && movie.tmdbURL?.lastPathComponent == "155")
    }

    @Test func tmdbDoesNotInventRatingsForUnratedOrMissingTitles() throws {
        let data = Data(#"{"movie_results":[{"id":155,"vote_average":0,"vote_count":0}],"tv_results":[]}"#.utf8)
        let movie = try TMDbRatings.parse(data, type: "movie")
        #expect(movie.tmdb == nil && movie.tmdbURL != nil)
        #expect(try TMDbRatings.parse(data, type: "series").isEmpty)
        #expect(throws: AddonError.invalidJSON) { try TMDbRatings.parse(Data("{}".utf8), type: "movie") }
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

    @Test func extendedCachesDecodeOldAnswersAndRoundTripNewScores() throws {
        let legacy = Data(#"{"rating":4.5,"fetchedAt":100}"#.utf8)
        let decoded = try JSONDecoder().decode(CachedRating.self, from: legacy)
        #expect(decoded.rating == 4.5 && decoded.reviews == nil)
        let current = CachedRating(rating: nil, fetchedAt: Date(), reviews: ReviewRatings(rottenTomatoes: 85, metacritic: 72))
        #expect(try JSONDecoder().decode(CachedRating.self, from: JSONEncoder().encode(current)) == current)
    }
}
