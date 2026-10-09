import Foundation
import StremioKit

public struct MediaTrack: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let language: String?
    public let isDefault: Bool

    public init(id: String, title: String, language: String? = nil, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.language = language
        self.isDefault = isDefault
    }
}

public struct PlaybackFailure: Error, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case network, format, unauthorized, notFound, timeout, noEngine, other
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct PlaybackState: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case idle, loading, ready, playing, paused, buffering, ended
        case failed(PlaybackFailure)
    }

    public var status: Status = .idle
    public var position: TimeInterval = 0
    /// nil while unknown (or for live streams).
    public var duration: TimeInterval?
    public var bufferedUntil: TimeInterval = 0
    public var rate: Float = 1
    public var audioTracks: [MediaTrack] = []
    public var selectedAudioTrackID: String?
    /// Subtitle tracks inside the media. External subtitles are not engine tracks: they are drawn by the app (PLAN §5).
    public var embeddedSubtitleTracks: [MediaTrack] = []
    public var selectedEmbeddedSubtitleID: String?
    public var isExternalPlaybackActive = false

    public init() {}

    public var isPlaying: Bool { status == .playing }

    public var failure: PlaybackFailure? {
        if case .failed(let failure) = status { return failure }
        return nil
    }

    /// Ready and buffering alone do not show that playback has started.
    public var hasStarted: Bool {
        switch status {
        case .playing, .ended: return true
        case .idle, .loading, .ready, .paused, .buffering, .failed: return false
        }
    }
}

public struct PlaybackItem: Sendable, Equatable {
    public var url: URL
    /// Request headers for every media request (`proxyHeaders.request`).
    public var headers: [String: String]
    public var title: String
    public var startPosition: TimeInterval
    public var filename: String?

    public init(url: URL, headers: [String: String] = [:], title: String, startPosition: TimeInterval = 0, filename: String? = nil) {
        self.url = url
        self.headers = headers
        self.title = title
        self.startPosition = startPosition
        self.filename = filename
    }
}

/// AVPlayer and the fallback engine implement the same protocol, so the coordinator and the UI never know which one is playing.
/// Failures are reported through `state.status = .failed`, never thrown, so one observer sees every outcome.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var state: PlaybackState { get }
    /// A fresh stream of every state change (latest value wins if the consumer is slow).
    func makeStateStream() -> AsyncStream<PlaybackState>
    func load(_ item: PlaybackItem)
    func play()
    func pause()
    func seek(to position: TimeInterval) async
    func setRate(_ rate: Float)
    func selectAudioTrack(id: String?)
    func selectEmbeddedSubtitleTrack(id: String?)
    func stop()
}

/// Fan-out of state changes to any number of `AsyncStream` consumers. Engines own one.
@MainActor
public final class PlaybackStateBroadcaster {
    private var continuations: [UUID: AsyncStream<PlaybackState>.Continuation] = [:]

    public init() {}

    public func makeStream(current: PlaybackState) -> AsyncStream<PlaybackState> {
        let token = UUID()
        let (stream, continuation) = AsyncStream<PlaybackState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[token] = nil }
        }
        continuation.yield(current)
        return stream
    }

    public func yield(_ state: PlaybackState) {
        for continuation in continuations.values { continuation.yield(state) }
    }

    public func finish() {
        for continuation in continuations.values { continuation.finish() }
        continuations = [:]
    }
}
