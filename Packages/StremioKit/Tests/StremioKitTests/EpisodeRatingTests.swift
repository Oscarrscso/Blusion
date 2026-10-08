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
}
