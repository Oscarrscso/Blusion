import Foundation
import Testing
@testable import StremioKit
import StremioKitTestSupport

@Suite struct ITunesTrailersTests {
    private func results(_ items: String) -> Data {
        Data(#"{"resultCount":\#(items.count),"results":[\#(items)]}"#.utf8)
    }

    @Test func theSearchAsksForTheMovieOrTheSeasonsInIreland() throws {
        let movie = try #require(ITunesTrailers.searchURL(title: "Inception", type: "movie"))
        #expect(movie.absoluteString == "https://itunes.apple.com/search?term=Inception&media=movie&entity=movie&country=ie")
        let series = try #require(ITunesTrailers.searchURL(title: "Breaking Bad", type: "series"))
        #expect(series.absoluteString == "https://itunes.apple.com/search?term=Breaking%20Bad&media=tvShow&entity=tvSeason&country=ie")
        #expect(ITunesTrailers.searchURL(title: "Inception", type: "channel") == nil)
    }

    @Test func aMovieMatchesItsExactNameNotALongerOne() throws {
        let data = results(#"""
        {"trackName":"Inception: Extra Scenes","releaseDate":"2010-07-16T07:00:00Z","previewUrl":"https://a.example.com/extra.m4v"},
        {"trackName":"Inception","releaseDate":"2010-07-16T07:00:00Z","previewUrl":"https://a.example.com/inception.m4v"}
        """#)
        let trailer = try ITunesTrailers.parse(data, title: "Inception", year: 2010, type: "movie")
        #expect(trailer?.directURL == URL(string: "https://a.example.com/inception.m4v"))
        #expect(trailer?.title == "Trailer" && trailer?.kind == .trailer && trailer?.isOfficial == true && trailer?.language == nil)
        #expect(trailer?.duration == nil)
    }

    @Test func namesMatchWithoutCaseAccentsOrPunctuation() throws {
        let data = results(#"{"trackName":"AMELIE!","previewUrl":"https://a.example.com/amelie.m4v"}"#)
        #expect(try ITunesTrailers.parse(data, title: "Amélie", year: nil, type: "movie")?.directURL != nil)
        #expect(try ITunesTrailers.parse(data, title: "Amelie 2", year: nil, type: "movie") == nil)
    }

    @Test func aKnownYearMustBeWithinOneYear() throws {
        let data = results(#"{"trackName":"Dune","releaseDate":"2021-10-22T07:00:00Z","previewUrl":"https://a.example.com/dune.m4v"}"#)
        #expect(try ITunesTrailers.parse(data, title: "Dune", year: 2020, type: "movie") != nil)
        #expect(try ITunesTrailers.parse(data, title: "Dune", year: 2022, type: "movie") != nil)
        #expect(try ITunesTrailers.parse(data, title: "Dune", year: 2024, type: "movie") == nil)
        #expect(try ITunesTrailers.parse(data, title: "Dune", year: nil, type: "movie") != nil, "no year known: the name alone matches")
    }

    @Test func onlyAnHTTPSPreviewCounts() throws {
        let data = results(#"{"trackName":"Dune","previewUrl":"http://a.example.com/dune.m4v"}"#)
        #expect(try ITunesTrailers.parse(data, title: "Dune", year: nil, type: "movie") == nil)
        #expect(try ITunesTrailers.parse(results(#"{"trackName":"Dune"}"#), title: "Dune", year: nil, type: "movie") == nil)
    }

    @Test func aSeriesTakesTheMatchForItsLowestSeason() throws {
        let data = results(#"""
        {"collectionName":"Show, Season 3","releaseDate":"2015-01-01T00:00:00Z","previewUrl":"https://a.example.com/s3.m4v"},
        {"collectionName":"Show - Season 1","releaseDate":"2010-01-01T00:00:00Z","previewUrl":"https://a.example.com/s1.m4v"},
        {"collectionName":"Show Extra, Season 1","releaseDate":"2010-01-01T00:00:00Z","previewUrl":"https://a.example.com/other.m4v"},
        {"collectionName":"Show, Season 2","releaseDate":"2012-01-01T00:00:00Z","previewUrl":"https://a.example.com/s2.m4v"}
        """#)
        let trailer = try ITunesTrailers.parse(data, title: "Show", year: nil, type: "series")
        #expect(trailer?.directURL == URL(string: "https://a.example.com/s1.m4v"))
    }

    @Test func noResultsOrAnotherTypeGiveNoTrailer() throws {
        #expect(try ITunesTrailers.parse(results(""), title: "Dune", year: nil, type: "movie") == nil)
        #expect(try ITunesTrailers.parse(results(#"{"trackName":"Dune","previewUrl":"https://a.example.com/d.m4v"}"#),
                                         title: "Dune", year: nil, type: "channel") == nil)
    }

    @Test func aBadAnswerIsInvalid() {
        #expect(throws: AddonError.self) { try ITunesTrailers.parse(Data("nope".utf8), title: "Dune", year: nil, type: "movie") }
        #expect(throws: AddonError.self) { try ITunesTrailers.parse(Data(#"{"resultCount":0}"#.utf8), title: "Dune", year: nil, type: "movie") }
    }

    @Test func aSearchIsSentOnceAndAnswersAreKeptIncludingNone() async throws {
        let transport = StubTransport(data: results(#"{"trackName":"Stub Ledger Film","previewUrl":"https://a.example.com/l.m4v"}"#))
        let itunes = ITunesTrailers(client: makeClient(transport, retries: 0), cache: ITunesTrailerCache())
        let first = try await itunes.preview(title: "Stub Ledger Film", year: nil, type: "movie")
        #expect(first?.directURL == URL(string: "https://a.example.com/l.m4v"))
        let again = try await itunes.preview(title: "stub ledger film!", year: nil, type: "movie")
        #expect(again == first)
        #expect(transport.callCount == 1, "the second title is answered from the session")
    }

    @Test func aTitleWithNoPreviewIsAlsoKept() async throws {
        let transport = StubTransport(data: results(""))
        let itunes = ITunesTrailers(client: makeClient(transport, retries: 0), cache: ITunesTrailerCache())
        #expect(try await itunes.preview(title: "Nothing Here", year: nil, type: "movie") == nil)
        #expect(try await itunes.preview(title: "Nothing Here", year: nil, type: "movie") == nil)
        #expect(transport.callCount == 1)
    }

    @Test func aTitleWithNoLettersIsNotSearched() async throws {
        let transport = StubTransport(data: results(""))
        let itunes = ITunesTrailers(client: makeClient(transport, retries: 0), cache: ITunesTrailerCache())
        #expect(try await itunes.preview(title: "!!!", year: nil, type: "movie") == nil)
        #expect(transport.callCount == 0)
    }
}
