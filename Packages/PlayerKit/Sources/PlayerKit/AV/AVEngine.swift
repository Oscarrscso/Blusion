#if canImport(AVFoundation)
@preconcurrency import AVFoundation
import Foundation
import StremioKit

/// `PlaybackEngine` backed by AVPlayer: MP4/MOV/M4V and HLS (PLAN §4). The video surface attaches to `player`.
///
/// UNVERIFIED on this build host (no Xcode): compiled and run only by macOS CI and on device. Kept deliberately plain.
@MainActor
public final class AVEngine: PlaybackEngine {
    public let player = AVPlayer()
    public private(set) var state = PlaybackState()

    private let broadcaster = PlaybackStateBroadcaster()
    private var playerItem: AVPlayerItem?
    private var headerLoader: HeaderResourceLoader?
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var itemObservations: [NSKeyValueObservation] = []
    private var tokens: [NSObjectProtocol] = []
    private var itemTokens: [NSObjectProtocol] = []
    private var audioGroup: AVMediaSelectionGroup?
    private var audioOptions: [String: AVMediaSelectionOption] = [:]
    private var subtitleGroup: AVMediaSelectionGroup?
    private var subtitleOptions: [String: AVMediaSelectionOption] = [:]
    private var wantsPlay = false
    private var wasPlayingBeforeInterruption = false
    private var isItemReady = false
    /// Distinguishes "ready, never played" (.ready) from "paused by the user" (.paused).
    private var hasPlayed = false
    private var pendingStart: TimeInterval = 0
    private var generation = 0

    public init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        observePlayer()
        observeAudioSession()
    }

    public func makeStateStream() -> AsyncStream<PlaybackState> {
        broadcaster.makeStream(current: state)
    }

    // MARK: PlaybackEngine

    public func load(_ item: PlaybackItem) {
        teardownItem()
        generation += 1
        isItemReady = false
        hasPlayed = false
        pendingStart = item.startPosition
        var fresh = PlaybackState()
        fresh.status = .loading
        publish(fresh)

        let made = AVAssetFactory.make(url: item.url, headers: item.headers)
        headerLoader = made.loader
        let playerItem = AVPlayerItem(asset: made.asset)
        self.playerItem = playerItem
        observeItem(playerItem)
        player.replaceCurrentItem(with: playerItem)
    }

    public func play() {
        wantsPlay = true
        activateAudioSession()
        if state.status == .ended {
            // Replay from the start.
            update { $0.status = .paused }
            Task {
                await self.seek(to: 0)
                self.player.play()
                self.refreshStatus()
            }
            return
        }
        player.play()
        if player.rate != 0, state.rate != 1 { player.rate = state.rate }
        refreshStatus()
    }

    public func pause() {
        wantsPlay = false
        player.pause()
        refreshStatus()
    }

    public func seek(to position: TimeInterval) async {
        let time = CMTime(seconds: max(0, position), preferredTimescale: 600)
        _ = await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        update { $0.position = max(0, position) }
    }

    public func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.timeControlStatus == .playing { player.rate = rate }
        update { $0.rate = rate }
    }

    public func selectAudioTrack(id: String?) {
        guard let id, let option = audioOptions[id], let group = audioGroup else { return }
        playerItem?.select(option, in: group)
        update { $0.selectedAudioTrackID = id }
    }

    public func selectEmbeddedSubtitleTrack(id: String?) {
        guard let group = subtitleGroup else { return }
        if let id, let option = subtitleOptions[id] {
            playerItem?.select(option, in: group)
        } else {
            playerItem?.select(nil, in: group)
        }
        update { $0.selectedEmbeddedSubtitleID = id }
    }

    public func stop() {
        generation += 1
        teardownItem()
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.forEach { $0.invalidate() }
        observations = []
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens = []
        deactivateAudioSession()
        update { $0.status = .idle }
        broadcaster.finish()
    }

    // MARK: State

    private func update(_ change: (inout PlaybackState) -> Void) {
        var next = state
        change(&next)
        publish(next)
    }

    private func publish(_ next: PlaybackState) {
        guard next != state else { return }
        state = next
        broadcaster.yield(next)
    }

    /// Maps AVPlayer's time-control status onto ours, but only once the item is ready (before that we are `.loading`).
    private func refreshStatus() {
        guard playerItem != nil, isItemReady else { return }
        if case .failed = state.status { return }
        if state.status == .ended { return }
        switch player.timeControlStatus {
        case .playing:
            hasPlayed = true
            update { $0.status = .playing }
        case .waitingToPlayAtSpecifiedRate:
            update { $0.status = wantsPlay ? .buffering : .ready }
        case .paused:
            if wantsPlay {
                update { $0.status = .buffering }
            } else {
                update { $0.status = hasPlayed ? .paused : .ready }
            }
        @unknown default:
            break
        }
        update { $0.isExternalPlaybackActive = player.isExternalPlaybackActive }
    }

    private func fail(_ error: Error?) {
        update { $0.status = .failed(AVEngine.failure(from: error)) }
    }

    static func failure(from error: Error?) -> PlaybackFailure {
        guard let error = error as NSError? else { return PlaybackFailure(.other, "Playback failed.") }
        let message = Redactor.redact(text: error.localizedDescription)   // error text can contain the media URL
        if error.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: error.code) {
            case .timedOut: return PlaybackFailure(.timeout, message)
            case .appTransportSecurityRequiresSecureConnection:
                return PlaybackFailure(.network, "This stream uses an insecure connection that iOS blocks.")
            default: return PlaybackFailure(.network, message)
            }
        }
        if error.domain == AVFoundationErrorDomain {
            switch AVError.Code(rawValue: error.code) {
            case .fileFormatNotRecognized, .decoderNotFound, .failedToLoadMediaData: return PlaybackFailure(.format, message)
            default: break
            }
        }
        return PlaybackFailure(.other, message)
    }

    // MARK: Observation

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshStatus() }
        })
        observations.append(player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshStatus() }
        })
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            Task { @MainActor in self?.itemStatusChanged(status, error: error) }
        })
        let center = NotificationCenter.default
        itemTokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didPlayToEnd() }
        })
        itemTokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            MainActor.assumeIsolated { self?.fail(error) }
        })
        itemTokens.append(center.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.status = .buffering } }
        })
    }

    private func teardownItem() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations = []
        itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemTokens = []
        playerItem = nil
        headerLoader?.invalidate()
        headerLoader = nil
        audioGroup = nil
        audioOptions = [:]
        subtitleGroup = nil
        subtitleOptions = [:]
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, error: Error?) {
        switch status {
        case .readyToPlay:
            guard let item = playerItem, !isItemReady else { return }
            isItemReady = true
            let seconds = item.duration.seconds
            update { $0.duration = (seconds.isFinite && seconds > 0) ? seconds : nil }
            if pendingStart > 0 {
                let start = pendingStart
                pendingStart = 0
                Task { await self.seek(to: start) }
            }
            loadTracks(of: item.asset)
            refreshStatus()
        case .failed:
            fail(error)
        default:
            break
        }
    }

    private func tick(_ time: CMTime) {
        guard let item = playerItem, isItemReady else { return }
        let position = time.seconds
        guard position.isFinite else { return }
        let buffered = item.loadedTimeRanges.last.map { $0.timeRangeValue.end.seconds } ?? 0
        update {
            $0.position = max(0, position)
            if buffered.isFinite { $0.bufferedUntil = buffered }
        }
    }

    private func didPlayToEnd() {
        update {
            if let duration = $0.duration { $0.position = duration }
            $0.status = .ended
        }
    }

    // MARK: Tracks

    private func loadTracks(of asset: AVAsset) {
        let current = generation
        Task { @MainActor [weak self] in
            let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            guard let self, self.generation == current, let item = self.playerItem else { return }
            let selection = item.currentMediaSelection
            self.audioGroup = audio ?? nil
            self.subtitleGroup = legible ?? nil
            let audioTracks = Self.tracks(from: self.audioGroup, prefix: "audio", selection: selection, into: &self.audioOptions)
            let subtitleTracks = Self.tracks(from: self.subtitleGroup, prefix: "subtitle", selection: selection, into: &self.subtitleOptions)
            self.update {
                $0.audioTracks = audioTracks.tracks
                $0.selectedAudioTrackID = audioTracks.selected
                $0.embeddedSubtitleTracks = subtitleTracks.tracks
                $0.selectedEmbeddedSubtitleID = subtitleTracks.selected
            }
        }
    }

    private static func tracks(from group: AVMediaSelectionGroup?, prefix: String, selection: AVMediaSelection,
                               into table: inout [String: AVMediaSelectionOption]) -> (tracks: [MediaTrack], selected: String?) {
        table = [:]
        guard let group else { return ([], nil) }
        let selectedOption = selection.selectedMediaOption(in: group)
        var tracks: [MediaTrack] = []
        var selectedID: String?
        for (index, option) in group.options.enumerated() {
            let id = "\(prefix)-\(index)"
            table[id] = option
            tracks.append(MediaTrack(id: id, title: option.displayName, language: option.locale?.identifier, isDefault: option == group.defaultOption))
            if option == selectedOption { selectedID = id }
        }
        return (tracks, selectedID)
    }

    // MARK: Audio session (iOS)

    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)   // ADR-005: playback category, activated when playback starts
        try? session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            MainActor.assumeIsolated { self?.handleInterruption(type: type, options: options) }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated { if reason == .oldDeviceUnavailable { self?.pause() } }   // headphones unplugged
        })
        #endif
    }

    #if os(iOS)
    private func handleInterruption(type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions?) {
        switch type {
        case .began:
            wasPlayingBeforeInterruption = wantsPlay
            update { if $0.status == .playing || $0.status == .buffering { $0.status = .paused } }
        case .ended:
            if wasPlayingBeforeInterruption, options?.contains(.shouldResume) == true { play() }
            wasPlayingBeforeInterruption = false
        default:
            break
        }
    }
    #endif
}

#endif
