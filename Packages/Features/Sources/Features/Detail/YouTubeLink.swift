import Foundation
import StremioKit

/// The links that open a YouTube trailer outside Blusion: the YouTube app's own link first, and the web page when the app does not open.
/// Nothing here touches UIKit, so the host tests cover it.
enum YouTubeLink {
    /// The YouTube app's link for `videoID`, or nil unless it is a well-formed YouTube id.
    static func appURL(videoID: String) -> URL? {
        guard Trailer.isYouTubeID(videoID) else { return nil }
        return URL(string: "youtube://www.youtube.com/watch?v=\(videoID)")
    }

    /// The watch page for `videoID`, or nil unless it is a well-formed YouTube id.
    static func webURL(videoID: String) -> URL? {
        guard Trailer.isYouTubeID(videoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }
}
