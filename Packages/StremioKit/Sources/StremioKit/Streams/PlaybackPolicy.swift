import Foundation

public struct PolicyConfiguration: Sendable, Equatable {
    /// True once a fallback engine (M6) is linked and enabled.
    public var fallbackEngineAvailable: Bool
    /// A user-supplied Stremio-compatible streaming server. Without one, `infoHash` streams are hidden (ADR-004).
    public var streamingServerURL: URL?

    public init(fallbackEngineAvailable: Bool = false, streamingServerURL: URL? = nil) {
        self.fallbackEngineAvailable = fallbackEngineAvailable
        self.streamingServerURL = streamingServerURL
    }
}

public enum FallbackReason: Sendable, Equatable {
    case container(MediaContainer)
    case audioCodec
    case unknownFormat
}

public enum HiddenReason: String, Sendable, Equatable, Hashable {
    case needsStreamingServer
    case usenetOrArchive

    public var hint: String {
        switch self {
        case .needsStreamingServer: return "needs a streaming server (Settings) or an addon that returns direct links"
        case .usenetOrArchive: return "uses a download format Blusion doesn't support"
        }
    }
}

public enum PlaybackRoute: Sendable, Equatable {
    /// AVPlayer.
    case native(URL)
    /// The fallback engine (MKV, DTS, …).
    case fallback(URL, FallbackReason)
    /// Opened outside the app (YouTube, external links).
    case external(URL)
    /// Playable in principle, but no engine for it is available: shown as "unsupported format", with the next stream offered.
    case unsupported(MediaContainer?)
    /// Not shown at all (a hint is shown instead).
    case hidden(HiddenReason)

    public var playableURL: URL? {
        switch self {
        case .native(let url), .fallback(let url, _): return url
        default: return nil
        }
    }

    public var isPlayable: Bool { playableURL != nil }
    public var isHidden: Bool {
        if case .hidden = self { return true }
        return false
    }

    /// Lower sorts first: native, fallback, external, unsupported, hidden.
    public var sortClass: Int {
        switch self {
        case .native: return 0
        case .fallback: return 1
        case .external: return 2
        case .unsupported: return 3
        case .hidden: return 4
        }
    }
}

/// PLAN §4 stream handling policy, with the `notWebReady` refinement from ADR-003.
public enum PlaybackPolicy {
    public static func route(for stream: AddonStream, container: MediaContainer?, quality: StreamQuality, config: PolicyConfiguration) -> PlaybackRoute {
        switch stream.source {
        case .direct(let url):
            return directRoute(url, stream: stream, container: container, quality: quality, config: config)
        case .torrent(let hash, let index, _):
            guard let server = config.streamingServerURL, let url = StreamingServerRoute.url(server: server, infoHash: hash, fileIndex: index) else {
                return .hidden(.needsStreamingServer)
            }
            return directRoute(url, stream: stream, container: container, quality: quality, config: config)
        case .youtube(let id):
            guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return .hidden(.usenetOrArchive) }
            return .external(url)
        case .external(let url):
            return .external(url)
        case .archive:
            return .hidden(.usenetOrArchive)
        }
    }

    private static func directRoute(_ url: URL, stream: AddonStream, container sniffed: MediaContainer?, quality: StreamQuality,
                                    config: PolicyConfiguration) -> PlaybackRoute {
        let known = sniffed ?? ContainerSniffer.container(url: url, filename: stream.behaviorHints.filename)
        if let known {
            if known.isNativelyPlayable && !quality.audioNeedsFallbackEngine { return .native(url) }
            return fallback(url, known.isNativelyPlayable ? .audioCodec : .container(known), known: known, config: config)
        }
        // Nothing says what this is. Audio we can't decode, or `notWebReady` (a hint, not a verdict: ADR-003) tips it to the fallback
        // engine; otherwise try AVPlayer and let the coordinator move on if it fails.
        if quality.audioNeedsFallbackEngine { return fallback(url, .audioCodec, known: nil, config: config) }
        if stream.behaviorHints.notWebReady { return fallback(url, .unknownFormat, known: nil, config: config) }
        return .native(url)
    }

    private static func fallback(_ url: URL, _ reason: FallbackReason, known: MediaContainer?, config: PolicyConfiguration) -> PlaybackRoute {
        config.fallbackEngineAvailable ? .fallback(url, reason) : .unsupported(known)
    }
}

/// UNVERIFIED (ADR-004): turns an `infoHash` into a URL on a user-supplied Stremio-compatible streaming server.
public enum StreamingServerRoute {
    public static func url(server: URL, infoHash: String, fileIndex: Int?) -> URL? {
        guard let scheme = server.scheme?.lowercased(), scheme == "http" || scheme == "https", server.host != nil else { return nil }
        let hash = infoHash.lowercased()
        let isHex = hash.count == 40 && hash.allSatisfy { $0.isHexDigit }
        let isBase32 = hash.count == 32 && hash.allSatisfy { ("a"..."z").contains($0) || ("2"..."7").contains($0) }
        guard isHex || isBase32 else { return nil }
        var base = server.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/\(hash)/\(fileIndex ?? -1)")
    }
}
