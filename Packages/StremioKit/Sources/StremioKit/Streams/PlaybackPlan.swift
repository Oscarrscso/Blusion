import Foundation

/// One playable stream, with everything the player needs. Value type: safe to hand across actors and to a navigation stack.
public struct PlaybackCandidate: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let addonName: String
    /// `.native` or `.fallback`; never external, unsupported or hidden.
    public let route: PlaybackRoute
    /// `behaviorHints.proxyHeaders.request`: sent with every media request for this stream.
    public let headers: [String: String]
    /// Subtitles bundled with the stream itself.
    public let subtitles: [SubtitleItem]
    public let filename: String?
    public let videoHash: String?
    public let videoSize: Int64?
    public let bingeContext: BingeContext?

    public init?(_ ranked: RankedStream) {
        guard ranked.route.isPlayable else { return nil }
        self.id = ranked.id
        self.title = ranked.title
        self.addonName = ranked.addon.name
        self.route = ranked.route
        self.headers = ranked.stream.behaviorHints.proxyHeaders?.request ?? [:]
        self.subtitles = ranked.stream.subtitles
        self.filename = ranked.stream.behaviorHints.filename
        self.videoHash = ranked.stream.behaviorHints.videoHash
        self.videoSize = ranked.stream.behaviorHints.videoSize
        self.bingeContext = ranked.bingeContext
    }

    public init(id: String, title: String, addonName: String = "", route: PlaybackRoute, headers: [String: String] = [:],
                subtitles: [SubtitleItem] = [], filename: String? = nil, videoHash: String? = nil, videoSize: Int64? = nil,
                bingeContext: BingeContext? = nil) {
        self.id = id
        self.title = title
        self.addonName = addonName
        self.route = route
        self.headers = headers
        self.subtitles = subtitles
        self.filename = filename
        self.videoHash = videoHash
        self.videoSize = videoSize
        self.bingeContext = bingeContext
    }

    public var url: URL? { route.playableURL }
}

/// What to play and what to fall back on: the chosen stream first, then every other playable stream in rank order.
/// If one fails, the coordinator moves to the next (PLAN M5: auto-advance on failure).
public struct PlaybackPlan: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let request: StreamRequest
    public let candidates: [PlaybackCandidate]

    public init(id: UUID = UUID(), request: StreamRequest, candidates: [PlaybackCandidate]) {
        self.id = id
        self.request = request
        self.candidates = candidates
    }

    /// `nil` when `chosen` isn't playable.
    public static func make(request: StreamRequest, chosen: RankedStream, from listing: StreamListing) -> PlaybackPlan? {
        guard let first = PlaybackCandidate(chosen) else { return nil }
        let rest = listing.playable.filter { $0.id != chosen.id }.compactMap(PlaybackCandidate.init)
        return PlaybackPlan(request: request, candidates: [first] + rest)
    }

    public static func == (lhs: PlaybackPlan, rhs: PlaybackPlan) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
