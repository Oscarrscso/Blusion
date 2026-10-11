import Foundation
import Testing
@testable import Features

@Suite struct YouTubeLinkTests {
    @Test func aWellFormedIDMakesTheAppAndWebLinks() {
        #expect(YouTubeLink.appURL(videoID: "EXeTwQWrcwY")?.absoluteString == "youtube://www.youtube.com/watch?v=EXeTwQWrcwY")
        #expect(YouTubeLink.webURL(videoID: "EXeTwQWrcwY")?.absoluteString == "https://www.youtube.com/watch?v=EXeTwQWrcwY")
        #expect(YouTubeLink.webURL(videoID: "a-_9")?.absoluteString == "https://www.youtube.com/watch?v=a-_9")
    }

    @Test func aMalformedIDMakesNoLink() {
        for id in ["", "not an id", "abc&x=1", "abc/../evil", "https://youtu.be/abc", "abcé"] {
            #expect(YouTubeLink.appURL(videoID: id) == nil, "\(id) is not a YouTube id")
            #expect(YouTubeLink.webURL(videoID: id) == nil, "\(id) is not a YouTube id")
        }
    }
}
