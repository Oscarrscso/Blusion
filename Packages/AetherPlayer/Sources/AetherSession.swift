#if canImport(UIKit)
import AetherEngine
import AVFoundation
import Combine
import Foundation
import PlaybackGeometry
import UIKit

/// One AetherEngine playback session, driven by the app's `AetherBackend`. Owns the engine, the view it draws into and
/// the subtitle overlay (AetherEngine publishes subtitle cues; the host draws them). Everything it reports goes out as `AetherEvent`s.
@MainActor
public final class AetherSession {
    /// The optional parts of AetherEngine this build compiled (package traits in Package.swift).
    public static var composesFEL: Bool { AetherEngine.OptionalComponent.dualLayerDolbyVision.isBuiltIn }
    public static var rendersObjectAudio: Bool { AetherEngine.OptionalComponent.trueHDObjectAudio.isBuiltIn }

    let engine: AetherEngine
    let host = AetherHostView()
    public let events: AsyncStream<AetherEvent>
    let continuation: AsyncStream<AetherEvent>.Continuation
    var subscriptions: Set<AnyCancellable> = []
    var loadTask: Task<Void, Never>?
    var generation = 0
    var isLoaded = false
    var options = AetherOptions()
    private var volume: Float = 1
    private var isMuted = false
    var lastPosition = -1.0
    var lastBuffered = -1.0
    /// The length last reported, in `loaded` or a later `duration`; 0 while unknown.
    var lastDuration = 0.0
    var lastTracks: (audio: [AetherTrack], subtitles: [AetherTrack], audioID: Int?, subtitleID: Int?)?
    var lastChapters: [AetherChapter] = []
    var pausedState: Bool?
    var bufferingState = false
    var downloadSample: (bytes: Int64, at: ContinuousClock.Instant)?
    var networkBitrate: Double?
    var hasEnded = false
    var subtitleDelay: TimeInterval = 0
    /// The last play or pause Blusion asked for. Blusion says play straight after load, before AetherEngine has a session to play,
    /// and AetherEngine's own play() is a no-op until then; so the word is kept and applied once the load is done.
    private var wantsPlaying = false
    /// A track pick AetherEngine has not reported back yet (a switch rebuilds the session, so it lands later). Reported as selected
    /// meanwhile, so the menu doesn't flick back to the old track.
    var pendingAudio: Int?
    var pendingSubtitle: SubtitlePick?
    enum SubtitlePick: Equatable {
        case off
        case track(Int)

        var trackID: Int? {
            if case .track(let id) = self { return id }
            return nil
        }
    }

    public var view: UIView { host }
    /// The AVPlayer AetherEngine plays the picture through now; nil on its software path or before a load. It changes as AetherEngine
    /// rebuilds its session (a track switch, a seam), so readers ask again rather than keep it.
    public var currentPlayer: AVPlayer? { engine.currentAVPlayer }

    /// Shows `layer` over the picture, placed and sized with it (AI super resolution's scaled frames); nil removes it. Subtitles stay
    /// above it.
    public func hostPictureOverlay(_ layer: CALayer?) { host.hostPictureOverlay(layer) }
    /// The layer Picture in Picture shows: the native route's AVPlayerLayer, or the software route's sample-buffer layer. nil before a load
    /// has one. It changes with the session, so readers ask again.
    public var pictureInPictureLayer: CALayer? {
        if let native = engine.nativePlayerLayer { return native }
        return engine.softwarePiPSource?.layer
    }
    /// The software route's playable range, for the window's timeline. Invalid when nothing plays.
    public func pictureInPictureTimeRange() -> CMTimeRange { engine.softwarePiPSource?.timeRange() ?? .invalid }
    /// The window is open or closed. AetherEngine draws subtitles into the picture while it is open.
    public func setPictureInPictureActive(_ active: Bool) { engine.pictureInPictureActive = active }
    /// How the picture is drawn into its frame, for a layer drawn over it.
    public var pictureGravity: AVLayerVideoGravity { host.currentGravity }
    /// The stream is HDR or Dolby Vision (not what reaches the display).
    public var isHDRSource: Bool { isLoaded && engine.sourceVideoFormat != .sdr }
    /// Compressed media downloaded ahead, including FEL packets. The software clock does not
    /// advance before its first play, so read its published cache ranges while startup is paused.
    public var bufferedAhead: TimeInterval? {
        guard let ahead = bufferedMediaAhead else { return nil }
        // Nothing more to wait for when the remaining film is already downloaded.
        if lastDuration > 0, engine.clock.currentTime + ahead >= lastDuration - 0.5 { return nil }
        return ahead
    }

    public var bufferedMediaAhead: TimeInterval? {
        guard isLoaded, !engine.isLive else { return nil }
        let position = engine.clock.currentTime
        let frontier: Double
        switch engine.videoRoute {
        case .loopback: frontier = engine.clock.bufferedPosition
        case .software:
            // Allow the first packet's timestamp to sit just after the requested start.
            frontier = engine.residentRanges.first {
                $0.lowerBound <= position + 0.5 && $0.upperBound >= position
            }?.upperBound ?? engine.clock.bufferedPosition
        default: return nil
        }
        let ahead = frontier - position
        return ahead.isFinite ? max(0, ahead) : nil
    }
    #if DEBUG
    let trace = PlaybackTrace()
    #endif

    public init() throws {
        engine = try AetherEngine()
        engine.logTag = "blusion"
        (events, continuation) = AsyncStream<AetherEvent>.makeStream()
        engine.bind(view: host.playerView)
        let engine = engine
        host.onGravity = { gravity in engine.videoGravity = gravity }
        observe()
    }

    // MARK: Loading

    public func load(url: URL, headers: [String: String], startPosition: TimeInterval, options: AetherOptions) {
        generation += 1
        let generation = generation
        self.options = options
        isLoaded = false
        hasEnded = false
        lastDuration = 0
        lastBuffered = -1
        downloadSample = nil
        networkBitrate = nil
        lastTracks = nil
        lastChapters = []
        pausedState = nil
        wantsPlaying = false
        pendingAudio = nil
        pendingSubtitle = nil
        host.displaySize = nil
        host.overlay.show(cues: [], at: 0)
        Self.activateAudioSession()
        #if DEBUG
        trace.begin(name: url.lastPathComponent, start: startPosition, engine: engine)
        #endif
        var loadOptions = LoadOptions(
            httpHeaders: headers,
            preferDualLayerDolbyVision: options.composesFEL,
            objectAudioRendering: options.rendersObjectAudio ? .apac(.l714) : .off,
            preferredAudioLanguages: options.preferredAudioLanguages,
            autoplay: false
        )
        loadOptions.dolbyVisionHandling = options.dolbyVision ? .automatic : .baseLayerOnly
        let loadedDolbyVision = options.dolbyVision
        // Both remuxed AVPlayer and FEL's compressed-packet reader fill independently of playback.
        loadOptions.forwardBufferSegments = 30 // About two minutes; bounded by bytes and free disk.
        loadOptions.sessionCacheByteBudget = 2_147_483_648
        loadOptions.softwarePacketCacheStorage = .disk
        // Start on a segment's first fragments instead of waiting for the whole segment: a faster first frame on slow links.
        loadOptions.progressiveSegmentDelivery = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            // A warm of this stream already under way (`AetherPrewarm`) hands its bytes and resolved link to the load.
            if AetherPrewarm.isWarming(url) { self.continuation.yield(.preparing(.resolvingStream)) }
            await AetherPrewarm.waitForWarm(of: url)
            guard !Task.isCancelled, generation == self.generation else { return }
            do {
                try await self.engine.load(url: url, startPosition: startPosition > 0 ? startPosition : nil, options: loadOptions)
                guard !Task.isCancelled, generation == self.generation else { return }
                self.didLoad()
                // A change made while loading missed the load's options.
                if self.options.dolbyVision != loadedDolbyVision { self.reloadForDolbyVision(self.options.dolbyVision) }
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                self.continuation.yield(.failed(self.failure(thrown: error)))
            }
        }
    }

    private func didLoad() {
        isLoaded = true
        #if DEBUG
        trace.note("loaded route=\(engine.videoRoute.rawValue) \(engine.sourceVideoWidth)x\(engine.sourceVideoHeight) "
                   + "\(engine.sourceVideoCodecName ?? "-") \(engine.sourceVideoBitrate / 1_000_000) Mbit/s wantsPlay=\(wantsPlaying)")
        #endif
        if wantsPlaying { engine.play() }
        let tracks = currentTracks()
        lastTracks = tracks
        let duration = engine.duration.isFinite && engine.duration > 0 ? engine.duration : nil
        lastDuration = duration ?? 0
        continuation.yield(.loaded(duration: duration, audio: tracks.audio, subtitles: tracks.subtitles,
                                   selectedAudio: tracks.audioID, selectedSubtitle: tracks.subtitleID))
        publishChapters()
        publishTransport()
        if engine.hasFirstFrameReadyForDisplay { continuation.yield(.videoFrameReady) }
        host.displaySize = presentedSize()
    }

    /// The picture's presented size: measured on the software path, else the coded size under a valid pixel aspect ratio.
    func presentedSize() -> CGSize? {
        if let size = engine.softwareDisplaySize, size.width > 0, size.height > 0 { return size }
        guard engine.sourceVideoWidth > 0, engine.sourceVideoHeight > 0 else { return nil }
        let par = engine.sourceVideoPixelAspectRatio
        let validPAR = par.isFinite && par > 0 ? par : 1
        return CGSize(width: Double(engine.sourceVideoWidth) * validPAR, height: Double(engine.sourceVideoHeight))
    }

    // MARK: Transport

    public func setPaused(_ paused: Bool) {
        wantsPlaying = !paused
        #if DEBUG
        trace.note(paused ? "pause" : "play ahead=\(bufferedAhead.map { String(format: "%.1f", $0) } ?? "-")")
        #endif
        guard isLoaded else { return }   // applied in didLoad
        if paused { engine.pause() } else { engine.play() }
    }

    public func seek(to position: TimeInterval) async {
        hasEnded = false
        await engine.seek(to: position)
    }

    public func setRate(_ rate: Float) { engine.setRate(rate) }

    /// AetherEngine's own ceiling for the route playing: 2× for video, 3× for audio-only. It clamps anything above.
    public var maximumRate: Float { engine.maxSupportedRate }

    public func setVolume(_ volume: Float) {
        self.volume = volume
        engine.volume = isMuted ? 0 : volume
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        engine.volume = muted ? 0 : volume
    }

    public func setAudioDelay(_ seconds: TimeInterval) { engine.setAudioDelay(seconds) }

    /// Positive delays the subtitles: the overlay and the frames composed for Picture in Picture.
    public func setSubtitleDelay(_ seconds: TimeInterval) {
        subtitleDelay = seconds
        engine.setSoftwareSubtitleDelay(seconds)
        refreshSubtitles()
    }

    // MARK: Tracks

    public func selectAudio(id: Int?) {
        guard let id else { return }   // AetherEngine always plays one audio track
        pendingAudio = id
        engine.selectAudioTrack(index: id)
        publishTracks()
    }

    public func selectSubtitle(id: Int?) {
        pendingSubtitle = id.map(SubtitlePick.track) ?? .off
        if let id { engine.selectSubtitleTrack(index: id) } else { engine.clearSubtitle() }
        publishTracks()
    }

    /// Adds a subtitle file (downloaded by the engine with these headers) and selects it.
    public func addSubtitle(url: URL, title: String, language: String?, headers: [String: String]) {
        let track = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: url, name: title, language: language,
                                                                          httpHeaders: headers.isEmpty ? nil : headers))
        engine.selectSubtitleTrack(index: track.id)
        publishTracks()
    }

    // MARK: Picture and subtitles

    /// Whether the stream is Dolby Vision with a base layer to switch to, so the switch is worth offering. Not profile 5: it has none.
    public var isDolbyVisionSource: Bool {
        guard isLoaded, engine.sourceDVProfile != 5 else { return false }
        return engine.sourceDVProfile != nil || engine.sourceVideoFormat == .dolbyVision
    }

    /// Off plays the HDR10 / HLG base layer instead (AetherEngine keeps Dolby Vision on a profile 5 stream, which has none). A playing
    /// session is rebuilt where it is; before the load it is part of the load.
    public func setDolbyVision(_ enabled: Bool) {
        guard options.dolbyVision != enabled else { return }
        options.dolbyVision = enabled
        guard isLoaded else { return }
        reloadForDolbyVision(enabled)
    }

    private func reloadForDolbyVision(_ enabled: Bool) {
        let generation = generation
        Task { [weak self] in
            guard let self, generation == self.generation else { return }
            _ = try? await self.engine.reloadAtCurrentPosition { $0.dolbyVisionHandling = enabled ? .automatic : .baseLayerOnly }
            guard generation == self.generation, self.isLoaded else { return }
            self.host.displaySize = self.presentedSize()
            self.host.setNeedsLayout()
        }
    }

    /// How bright HDR gets, 0…1. 0 leaves the engine's own dynamic range; above it the picture asks for the display's whole HDR range.
    public func setHDRBrightness(_ level: Double) {
        host.hdrBrightness = level
    }

    /// `aspect` sets the visible picture's display shape; `crop` measures content in the original source. nil leaves either alone. `inset` keeps
    /// Fit that far from the left and the right (points). A change of fit, zoom, aspect or crop moves the picture smoothly into its new
    /// place; a new inset comes with a rotation, so it applies at once, as the new size does.
    public func apply(fit: AetherFit, zoom: Double, aspect: Double? = nil, crop: Double? = nil, inset: Double = 0) {
        let clampedZoom = zoom.isFinite ? max(1, zoom) : 1
        let clampedInset = inset.isFinite ? max(0, inset) : 0
        let moves = host.fit != fit || host.zoom != clampedZoom || host.aspect != aspect || host.crop != crop
        host.fit = fit
        host.zoom = clampedZoom
        host.aspect = aspect
        host.crop = crop
        host.inset = clampedInset
        if moves { host.animateNextLayout() }
    }

    public func apply(subtitleStyle: AetherSubtitleStyle) {
        host.overlay.style = subtitleStyle
        refreshSubtitles()
    }

    // MARK: Helpers

    /// Multichannel PCM and spatial audio reach the routes that take them; the system downmixes for headphones and the speaker.
    private static func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        try? session.setSupportsMultichannelContent(true)
        try? session.setActive(true)
    }

    func failure(thrown error: Error?) -> AetherFailure {
        if let info = engine.errorInfo { return Self.failure(info) }
        let message = error?.localizedDescription ?? "AetherEngine could not play this stream."
        if let error = error as? URLError {
            let kind: AetherFailure.Kind = error.code == .timedOut ? .timeout
                : error.code == .userAuthenticationRequired ? .unauthorized : .network
            return AetherFailure(kind: kind, message: message)
        }
        return AetherFailure(kind: .other, message: message)
    }

    static func failure(_ info: PlaybackErrorInfo) -> AetherFailure {
        if info.underlyingDomain == NSURLErrorDomain, info.underlyingCode == URLError.timedOut.rawValue {
            return AetherFailure(kind: .timeout, message: info.message)
        }
        let kind: AetherFailure.Kind
        switch info.kind {
        case .sourceRefused:
            switch info.underlyingCode {
            case 401, 403: kind = .unauthorized
            case 404, 410: kind = .notFound
            default: kind = .network
            }
        case .sourceOpenFailed:
            kind = info.underlyingDomain == NSURLErrorDomain ? .network : .format
        case .sourceCertificateRejected, .sourceRateLimited, .vodSourceFailed, .liveSourceUnavailable, .storageExhausted:
            kind = .network
        case .customSourceProbeFailed, .dolbyVisionRequiresHardware, .nativeItemFailed, .noPlayableTrackWithinBudget,
             .masterPlaylistRejected, .softwarePipelineFailed, .audioBridgeProducedNoOutput, .demuxedAudioLiveUnsupported:
            kind = .format
        default:
            kind = .other
        }
        return AetherFailure(kind: kind, message: info.message)
    }

    static func track(_ info: TrackInfo) -> AetherTrack {
        AetherTrack(id: info.id, name: info.name, codec: info.codec, language: info.language, channels: info.channels,
                    isDefault: info.isDefault, isForced: info.isForced, isHearingImpaired: info.isHearingImpaired,
                    isCommentary: info.isCommentary, isAtmos: info.isAtmos, isDTSX: info.isDTSX, isExternal: info.isExternal)
    }

    static func routeName(_ route: VideoRoute) -> String {
        switch route {
        case .none: "starting"
        case .remoteBypass: "AVPlayer, direct"
        case .loopback: "AVPlayer, remuxed"
        case .software: "VideoToolbox + Metal"
        case .audio: "audio only"
        }
    }

    static func formatName(_ format: VideoFormat) -> String {
        switch format {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .dolbyVision: "Dolby Vision"
        case .hlg: "HLG"
        }
    }

    static func deliveryName(_ delivery: AudioDelivery) -> String? {
        switch delivery {
        case .none: nil
        case .noAudioInSource: "No audio in the source"
        case .streamCopy: "Passed to the system untouched"
        case .bridged: "Re-encoded for the system"
        case .decoded: "Decoded to PCM"
        case .droppedNoPipeline: "Not playing: no pipeline for this audio"
        case .playerManaged: "Played by AVPlayer"
        }
    }

    static func audioName(_ track: TrackInfo) -> String {
        let base: String = switch track.codec {
        case "ac3": "Dolby Digital"
        case "eac3": "Dolby Digital Plus"
        case "truehd", "mlp": "TrueHD"
        case "dts": track.profile?.contains("MA") == true ? "DTS-HD MA" : "DTS"
        case "aac": "AAC"
        case "flac": "FLAC"
        case "opus": "Opus"
        default: track.codec.uppercased()
        }
        if track.isAtmos { return "\(base) + Atmos" }
        if track.isDTSX { return "\(base) + DTS:X" }
        return base
    }

    static func channelLayout(_ count: Int) -> String {
        switch count {
        case 1: "mono"
        case 2: "stereo"
        case 6: "5.1"
        case 7: "6.1"
        case 8: "7.1"
        default: "\(count) ch"
        }
    }
}
#endif
