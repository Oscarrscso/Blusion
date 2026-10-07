import Foundation
import PlayerKit
import StremioKit

/// A scripted engine. Tests drive it with `simulate…` instead of waiting on a clock.
@MainActor
public final class MockEngine: PlaybackEngine {
    public enum Outcome: Sendable {
        /// Becomes ready after `loadDelay`, with this duration.
        case plays(duration: TimeInterval)
        case failsToLoad(PlaybackFailure)
        /// Never reports ready (exercises the startup timeout).
        case hangs
    }

    public private(set) var state = PlaybackState()
    public private(set) var loadedItems: [PlaybackItem] = []
    public private(set) var seeks: [TimeInterval] = []
    public private(set) var playCalls = 0
    public private(set) var pauseCalls = 0
    public private(set) var rates: [Float] = []
    public private(set) var selectedAudio: [String?] = []
    public private(set) var selectedEmbeddedSubtitles: [String?] = []
    public private(set) var isStopped = false

    private let outcome: Outcome
    private let loadDelay: Duration
    private let broadcaster = PlaybackStateBroadcaster()
    private var wantsPlay = false
    private var loadTask: Task<Void, Never>?

    public init(_ outcome: Outcome = .plays(duration: 100), loadDelay: Duration = .milliseconds(5)) {
        self.outcome = outcome
        self.loadDelay = loadDelay
    }

    public func makeStateStream() -> AsyncStream<PlaybackState> { broadcaster.makeStream(current: state) }

    public func load(_ item: PlaybackItem) {
        loadedItems.append(item)
        update { $0.status = .loading }
        loadTask = Task { [weak self, loadDelay, outcome] in
            try? await Task.sleep(for: loadDelay)
            guard let self, !Task.isCancelled else { return }
            switch outcome {
            case .plays(let duration):
                self.update {
                    $0.duration = duration
                    $0.position = item.startPosition
                    $0.status = self.wantsPlay ? .playing : .ready
                }
            case .failsToLoad(let failure):
                self.update { $0.status = .failed(failure) }
            case .hangs:
                break
            }
        }
    }

    public func play() {
        playCalls += 1
        wantsPlay = true
        if state.status == .ready || state.status == .paused { update { $0.status = .playing } }
    }

    public func pause() {
        pauseCalls += 1
        wantsPlay = false
        if state.status == .playing { update { $0.status = .paused } }
    }

    public func seek(to position: TimeInterval) async {
        seeks.append(position)
        update { $0.position = position }
    }

    public func setRate(_ rate: Float) {
        rates.append(rate)
        update { $0.rate = rate }
    }

    public func selectAudioTrack(id: String?) {
        selectedAudio.append(id)
        update { $0.selectedAudioTrackID = id }
    }

    public func selectEmbeddedSubtitleTrack(id: String?) {
        selectedEmbeddedSubtitles.append(id)
        update { $0.selectedEmbeddedSubtitleID = id }
    }

    public func stop() {
        isStopped = true
        loadTask?.cancel()
        update { $0.status = .idle }
        broadcaster.finish()
    }

    // MARK: Test controls

    public func simulate(position: TimeInterval, duration: TimeInterval? = nil) {
        update {
            $0.position = position
            if let duration { $0.duration = duration }
        }
    }

    public func simulateFailure(_ failure: PlaybackFailure) { update { $0.status = .failed(failure) } }
    public func simulateEnd() { update { $0.status = .ended } }
    public func simulateBuffering() { update { $0.status = .buffering } }
    public func simulate(tracks audio: [MediaTrack], subtitles: [MediaTrack]) {
        update {
            $0.audioTracks = audio
            $0.embeddedSubtitleTracks = subtitles
        }
    }

    private func update(_ change: (inout PlaybackState) -> Void) {
        change(&state)
        broadcaster.yield(state)
    }
}
