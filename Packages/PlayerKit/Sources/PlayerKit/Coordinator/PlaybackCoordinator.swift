import Foundation
import Observation
import StremioKit

/// Plays a `PlaybackPlan`: creates the right engine for each candidate, and moves to the next candidate when one fails to start,
/// stalls at startup, or fails mid-stream (resuming where it stopped). Engine-agnostic: it only sees `PlaybackEngine`.
@MainActor
@Observable
public final class PlaybackCoordinator {
    public enum Phase: Equatable {
        case idle
        /// Waiting for the current candidate to start.
        case starting
        case playing
        /// Every candidate failed.
        case exhausted
        case finished
    }

    public struct FailedAttempt: Equatable, Identifiable {
        public let id: String
        public let title: String
        public let failure: PlaybackFailure
    }

    public private(set) var phase: Phase = .idle
    public private(set) var state = PlaybackState()
    public private(set) var current: PlaybackCandidate?
    public private(set) var candidateIndex = 0
    public private(set) var failedAttempts: [FailedAttempt] = []
    /// A short, human-readable line about what just happened ("…didn't work. Trying the next stream.").
    public private(set) var notice: String?
    /// The engine currently in use; the video surface attaches to it.
    public private(set) var engine: (any PlaybackEngine)?
    public private(set) var engineGeneration = 0
    /// The listener's volume and mute, for the UI to show.
    public private(set) var volume: Float = 1
    public private(set) var isMuted = false
    /// What the listener has chosen, once they have chosen it. Only these carry over to a new engine, so an engine keeps its own
    /// defaults until then (a snapshot run mutes its AVEngine, for example).
    private var chosenVolume: Float?
    private var chosenMuted: Bool?

    public let plan: PlaybackPlan
    public var onEnded: (@MainActor () -> Void)?

    private let makeEngine: @MainActor (PlaybackCandidate) -> (any PlaybackEngine)?
    private let resumeFrom: TimeInterval
    private let startupTimeout: Duration
    private let stallTimeout: Duration
    private let progress: ProgressSession?
    private var observer: Task<Void, Never>?
    private var stallTimer: Task<Void, Never>?
    private var startContinuation: CheckedContinuation<Bool, Never>?
    private var hasStartedCurrent = false
    /// How the current candidate failed before it started, if it did. `tryCandidate` decides what happens next.
    private var startFailure: PlaybackFailure?
    private var lastPosition: TimeInterval = 0
    private var stopped = false

    public init(plan: PlaybackPlan, resumeFrom: TimeInterval = 0, startupTimeout: Duration = .seconds(20),
                stallTimeout: Duration = .seconds(20), progress: ProgressSession? = nil,
                makeEngine: @escaping @MainActor (PlaybackCandidate) -> (any PlaybackEngine)?) {
        self.plan = plan
        self.resumeFrom = resumeFrom
        self.startupTimeout = startupTimeout
        self.stallTimeout = stallTimeout
        self.progress = progress
        self.makeEngine = makeEngine
    }

    // MARK: Lifecycle

    /// Starts the first candidate and returns when something is playing, or when every candidate has failed.
    public func start() async {
        guard phase == .idle else { return }
        stopped = false
        phase = .starting
        await tryCandidate(at: 0, startPosition: resumeFrom)
    }

    /// "Try the next stream" from the UI.
    public func advance() async {
        guard !stopped else { return }
        guard candidateIndex + 1 < plan.candidates.count else {
            notice = "There are no other streams to try."   // keep what is playing
            return
        }
        await moveOn(startPosition: lastPosition)
    }

    public func stop() async {
        stopped = true
        observer?.cancel()
        stallTimer?.cancel()
        resolveStart(false)
        engine?.stop()
        await progress?.finish()
        if phase != .exhausted { phase = .finished }
    }

    // MARK: Transport

    public func play() { engine?.play() }
    public func pause() { engine?.pause() }
    public func togglePlayPause() { state.isPlaying ? pause() : play() }
    public func seek(to position: TimeInterval) async { await engine?.seek(to: max(0, position)) }
    public func skip(by seconds: TimeInterval) async {
        let target = state.position + seconds
        await seek(to: state.duration.map { min(target, max(0, $0 - 1)) } ?? target)
    }
    public func setRate(_ rate: Float) { engine?.setRate(rate) }
    public func setVolume(_ volume: Float) {
        self.volume = min(1, max(0, volume))
        chosenVolume = self.volume
        engine?.setVolume(self.volume)
    }
    public func setMuted(_ muted: Bool) {
        isMuted = muted
        chosenMuted = muted
        engine?.setMuted(muted)
    }
    public func selectAudioTrack(id: String?) { engine?.selectAudioTrack(id: id) }
    public func selectEmbeddedSubtitleTrack(id: String?) { engine?.selectEmbeddedSubtitleTrack(id: id) }

    // MARK: Candidates

    /// `failure` is set when this is a retry: AVPlayer could not open the stream, so it plays in the fallback engine. If no engine can be
    /// made for the retry, the failure AVPlayer gave is reported, as the first attempt would.
    private func tryCandidate(at index: Int, startPosition: TimeInterval, retryingAfter failure: PlaybackFailure? = nil) async {
        guard !stopped else { return }
        engineGeneration += 1
        resolveStart(false)
        stallTimer?.cancel()
        stallTimer = nil
        guard index < plan.candidates.count else {
            observer?.cancel()
            engine?.stop()
            phase = .exhausted
            notice = plan.candidates.isEmpty ? "There is nothing to play." : "None of the streams could be played."
            return
        }
        candidateIndex = index
        var candidate = plan.candidates[index]
        if failure != nil, let url = candidate.url {
            candidate = candidate.rerouted(to: .fallback(url, .unknownFormat))
        }
        current = candidate

        guard let engine = makeEngine(candidate), let url = candidate.url else {
            recordFailure(candidate, failure ?? PlaybackFailure(.noEngine, "No player is available for this stream."))
            await moveOn(startPosition: startPosition)
            return
        }
        observer?.cancel()
        self.engine?.stop()
        self.engine = engine
        if let chosenVolume { engine.setVolume(chosenVolume) }
        if let chosenMuted { engine.setMuted(chosenMuted) }
        phase = .starting
        state = engine.state
        hasStartedCurrent = false
        startFailure = nil
        lastPosition = startPosition

        let stream = engine.makeStateStream()
        let generation = engineGeneration
        observer = Task { [weak self] in
            for await next in stream {
                guard let self, !Task.isCancelled, self.engineGeneration == generation else { return }
                self.handle(next)
            }
        }
        engine.load(PlaybackItem(url: url, headers: candidate.headers, title: candidate.title, startPosition: startPosition, filename: candidate.filename))
        engine.play()

        let started = await waitForStart()
        guard !stopped, generation == engineGeneration else { return }
        if started {
            if phase != .finished { phase = .playing }
            notice = failedAttempts.isEmpty ? nil : notice
        } else if !hasStartedCurrent {
            // AVPlayer cannot open a codec it lacks (DTS in MP4, AV1 on older chips): the same stream goes to the fallback engine, once.
            if failure == nil, let pending = startFailure, canRetryInFallbackEngine(candidate, after: pending) {
                await tryCandidate(at: index, startPosition: startPosition, retryingAfter: pending)
                return
            }
            // A start failure was recorded in handle(); only a timeout is left to record here.
            if startFailure == nil { recordFailure(candidate, PlaybackFailure(.timeout, "The stream took too long to start.")) }
            await moveOn(startPosition: startPosition)
        }
    }

    private func moveOn(startPosition: TimeInterval) async {
        let next = candidateIndex + 1
        if next < plan.candidates.count {
            notice = "“\(current?.title ?? "That stream")” didn't work. Trying “\(plan.candidates[next].title)”…"
        }
        await tryCandidate(at: next, startPosition: startPosition)
    }

    private func recordFailure(_ candidate: PlaybackCandidate, _ failure: PlaybackFailure) {
        failedAttempts.append(FailedAttempt(id: candidate.id, title: candidate.title, failure: failure))
    }

    /// Resolves true on playback, false on failure or timeout.
    private func waitForStart() async -> Bool {
        let timeout = startupTimeout
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resolveStart(false)
        }
        let started = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            if hasStartedCurrent { continuation.resume(returning: true) } else { startContinuation = continuation }
        }
        timer.cancel()
        return started
    }

    private func resolveStart(_ started: Bool) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        continuation.resume(returning: started)
    }

    private func handle(_ next: PlaybackState) {
        let previous = state
        state = next
        if next.hasStarted, !hasStartedCurrent {
            hasStartedCurrent = true
            resolveStart(true)
        }
        if hasStartedCurrent, next.status == .playing || next.status == .paused || next.status == .buffering {
            lastPosition = next.position
        }
        if hasStartedCurrent { progress?.observe(position: next.position, duration: next.duration) }
        if hasStartedCurrent, next.status == .playing || next.status == .buffering {
            if stallTimer == nil || next.position != previous.position { watchForStall() }
        } else {
            stallTimer?.cancel()
            stallTimer = nil
        }

        switch next.status {
        case .failed(let failure):
            guard let candidate = current else { return }
            if hasStartedCurrent {
                // Failed mid-stream: remember it and carry on from where it stopped.
                recordFailure(candidate, failure)
                Task { [weak self] in await self?.moveOn(startPosition: self?.lastPosition ?? 0) }
            } else {
                // Recorded now, unless tryCandidate retries the stream in the fallback engine: then the retry decides what is recorded.
                if !canRetryInFallbackEngine(candidate, after: failure) { recordFailure(candidate, failure) }
                startFailure = failure
                resolveStart(false)
            }
        case .ended:
            phase = .finished
            Task { [weak self] in
                await self?.progress?.finish()
                self?.onEnded?()
            }
        default:
            break
        }
    }

    /// AVPlayer could not open this stream before it started, and the plan allows one retry in the fallback engine.
    private func canRetryInFallbackEngine(_ candidate: PlaybackCandidate, after failure: PlaybackFailure) -> Bool {
        guard plan.retriesInFallbackEngine, failure.kind == .format, case .native = candidate.route else { return false }
        return true
    }

    private func watchForStall() {
        stallTimer?.cancel()
        let generation = engineGeneration
        let timeout = stallTimeout
        stallTimer = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, !self.stopped, self.engineGeneration == generation,
                  let candidate = self.current else { return }
            self.recordFailure(candidate, PlaybackFailure(.timeout, "Playback stopped making progress."))
            await self.moveOn(startPosition: self.lastPosition)
        }
    }
}
