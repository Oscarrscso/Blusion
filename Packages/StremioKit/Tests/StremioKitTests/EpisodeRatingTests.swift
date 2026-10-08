import Foundation
import Testing
@testable import StremioKit

@Suite struct EpisodeRatingTests {
    private func video(_ json: String) throws -> Video { try JSONDecoder().decode(Video.self, from: Data(json.utf8)) }

    @Test func readsImdbRatingAsNumberOrString() throws {
        #expect(try video(#"{"id":"tt1:1:1","imdbRating":8.4}"#).rating == 8.4)
        #expect(try video(#"{"id":"tt1:1:1","imdbRating":"7.9"}"#).rating == 7.9)
        #expect(try video(#"{"id":"tt1:1:1","rating":9}"#).ratingText == "9.0")
    }

    @Test func missingOrNonsenseRatingsAreNil() throws {
        for body in [#"{"id":"a"}"#, #"{"id":"a","imdbRating":"N/A"}"#, #"{"id":"a","imdbRating":0}"#, #"{"id":"a","imdbRating":11}"#, #"{"id":"a","imdbRating":-1}"#] {
            #expect(try video(body).rating == nil, "\(body)")
        }
        #expect(try video(#"{"id":"a"}"#).ratingText == nil)
    }

    @Test func addonRatingsAreTaggedWithTheAddonAsTheirSource() throws {
        #expect(try video(#"{"id":"tt1:1:1","imdbRating":8.4}"#).ratingSource == .addon)
        #expect(try video(#"{"id":"tt1:1:1"}"#).ratingSource == nil)
        #expect(Video(id: "tt1:1:1", rating: 8).ratingSource == .addon)
        #expect(Video(id: "tt1:1:1", rating: 0).ratingSource == nil, "a zero score is no score")
        #expect(Video(id: "tt1:1:1", rating: 7.1, ratingSource: .tmdb).ratingSource == .tmdb)
    }

    @Test func tmdbScoresFillOnlyTheEpisodesOfThatSeasonWithoutARating() throws {
        let json = #"""
        {"id":"tt0944947","type":"series","name":"Show","videos":[
          {"id":"tt0944947:1:1","season":1,"episode":1},
          {"id":"tt0944947:1:2","season":1,"episode":2,"imdbRating":9.1},
          {"id":"tt0944947:1:3","season":1,"episode":3},
          {"id":"tt0944947:1:4","season":1,"episode":4},
          {"id":"tt0944947:2:1","season":2,"episode":1}
        ]}
        """#
        var detail = try JSONDecoder().decode(MetaDetail.self, from: Data(json.utf8))
        detail.fillEpisodeRatings(season: 1, scores: [1: 8.1, 2: 5.0, 3: 0, 4: 11, 9: 7.0], source: .tmdb)
        let season = detail.episodes(inSeason: 1)
        #expect(season.map(\.rating) == [8.1, 9.1, nil, nil], "the addon's 9.1 stays, and 0 or 11 are not scores")
        #expect(season.map(\.ratingSource) == [.tmdb, .addon, nil, nil])
        #expect(detail.episodes(inSeason: 2).first?.rating == nil, "other seasons are untouched")
    }

    @Test func theSeriesIMDbIDIsTheHeadOfAnEpisodeID() {
        #expect(Video.seriesIMDbID(fromVideoID: "tt0944947:1:2") == "tt0944947")
        #expect(Video.seriesIMDbID(fromVideoID: "tt0944947") == nil, "a bare IMDb id is not an episode id")
        #expect(Video.seriesIMDbID(fromVideoID: "kitsu:123:4") == nil)
        #expect(Video.seriesIMDbID(fromVideoID: "tt1:1:2") == nil, "too short to be an IMDb id")
        #expect(Video.seriesIMDbID(fromVideoID: "") == nil)
    }
}
