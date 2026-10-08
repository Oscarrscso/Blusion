import Foundation

/// What the app ships and under which terms. The default build links no third-party code (ADR-001), so the list is short; the fallback
/// player's LGPL components appear only when that engine is built in (ADR-006, docs/licenses.md).
public struct Acknowledgement: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let license: String
    public let detail: String
    public let sourceURL: URL?

    public init(name: String, license: String, detail: String, sourceURL: URL? = nil) {
        self.name = name
        self.license = license
        self.detail = detail
        self.sourceURL = sourceURL
    }

    public static func all(fallbackEngineLinked: Bool) -> [Acknowledgement] {
        var list = [
            Acknowledgement(name: "Apple frameworks", license: "Apple SDK terms",
                            detail: "SwiftUI, SwiftData, AVFoundation, AVKit and the Security framework come with iOS."),
            Acknowledgement(name: "TMDB", license: "TMDB API attribution",
                            detail: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
                            sourceURL: URL(string: "https://www.themoviedb.org")),
            Acknowledgement(name: "Review site icons", license: "Respective service trademarks",
                            detail: "IMDb, Letterboxd, Rotten Tomatoes, Metacritic and TMDB marks identify links to their services. Blusion is not affiliated with them."),
        ]
        if fallbackEngineLinked {
            list += [
                Acknowledgement(name: "MPVKit", license: "LGPL-3.0", detail: "Swift wrapper and prebuilt libmpv used by the optional fallback player.",
                                sourceURL: URL(string: "https://github.com/mpvkit/MPVKit")),
                Acknowledgement(name: "libmpv", license: "LGPL-2.1 or later (LGPL build)", detail: "Media player library used by the fallback player.",
                                sourceURL: URL(string: "https://github.com/mpv-player/mpv")),
                Acknowledgement(name: "FFmpeg", license: "LGPL-2.1 or later (LGPL build)", detail: "Demuxing and decoding libraries used by the fallback player.",
                                sourceURL: URL(string: "https://ffmpeg.org/")),
                Acknowledgement(name: "libplacebo", license: "LGPL-2.1 or later", detail: "Video rendering library used by the fallback player.",
                                sourceURL: URL(string: "https://code.videolan.org/videolan/libplacebo")),
                Acknowledgement(name: "libass", license: "ISC", detail: "Subtitle rendering used by the fallback player.",
                                sourceURL: URL(string: "https://github.com/libass/libass")),
                Acknowledgement(name: "MoltenVK", license: "Apache-2.0", detail: "Vulkan to Metal layer used by the fallback player.",
                                sourceURL: URL(string: "https://github.com/KhronosGroup/MoltenVK")),
            ]
        }
        return list
    }
}
