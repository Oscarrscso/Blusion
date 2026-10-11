import Foundation
import StremioKit
import Testing
@testable import Features

@Suite struct PosterQualityTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func metahubPostersBecomeSmall() {
        for size in ["small", "medium", "large"] {
            #expect(PosterQuality.smallest(url("https://images.metahub.space/poster/\(size)/tt0111161/img"))
                == url("https://images.metahub.space/poster/small/tt0111161/img"))
        }
    }

    @Test func tmdbPostersBecomeW154() {
        for size in ["w92", "w154", "w185", "w342", "w500", "w780", "original"] {
            #expect(PosterQuality.smallest(url("https://image.tmdb.org/t/p/\(size)/abc123.jpg"))
                == url("https://image.tmdb.org/t/p/w154/abc123.jpg"))
        }
    }

    @Test func nonPostersAndUnknownHostsAreUntouched() {
        let background = url("https://images.metahub.space/background/medium/tt0111161/img")
        let logo = url("https://images.metahub.space/logo/medium/tt0111161/img")
        let other = url("https://example.com/poster/large/tt0111161/img")
        #expect(PosterQuality.smallest(background) == background)
        #expect(PosterQuality.smallest(logo) == logo)
        #expect(PosterQuality.smallest(other) == other)
        #expect(PosterQuality.smallest(nil) == nil)
    }

    @Test func posterFallsBackToMetahubForTheIMDbID() {
        let own = MetaPreview(id: "tt0111161", type: "movie", name: "A", poster: url("https://image.tmdb.org/t/p/original/x.jpg"))
        #expect(PosterQuality.poster(for: own) == url("https://image.tmdb.org/t/p/w154/x.jpg"))
        let bare = MetaPreview(id: "tt0111161", type: "movie", name: "A")
        #expect(PosterQuality.poster(for: bare) == url("https://images.metahub.space/poster/small/tt0111161/img"))
    }

    @Test func placeholderIsTwoTMDbStepsAboveTheFloor() {
        for size in ["w92", "w154", "w185", "w342", "w500", "w780", "original"] {
            #expect(PosterQuality.placeholder(url("https://image.tmdb.org/t/p/\(size)/abc123.jpg"))
                == url("https://image.tmdb.org/t/p/w342/abc123.jpg"))
        }
    }

    @Test func placeholderIsMetahubsMediumPoster() {
        for size in ["small", "medium", "large"] {
            #expect(PosterQuality.placeholder(url("https://images.metahub.space/poster/\(size)/tt0111161/img"))
                == url("https://images.metahub.space/poster/medium/tt0111161/img"))
        }
    }

    @Test func placeholderLeavesOtherURLsAlone() {
        let background = url("https://images.metahub.space/background/medium/tt0111161/img")
        let other = url("https://example.com/poster/large/tt0111161/img")
        #expect(PosterQuality.placeholder(background) == background)
        #expect(PosterQuality.placeholder(other) == other)
        #expect(PosterQuality.placeholder(nil) == nil)
    }

    @Test func thePlaceholderIsLargerThanTheSmallestPoster() {
        let tmdb = url("https://image.tmdb.org/t/p/original/x.jpg")
        #expect(PosterQuality.placeholder(tmdb) != PosterQuality.smallest(tmdb))
        let metahub = url("https://images.metahub.space/poster/small/tt0111161/img")
        #expect(PosterQuality.placeholder(metahub) == url("https://images.metahub.space/poster/medium/tt0111161/img"))
    }
}
