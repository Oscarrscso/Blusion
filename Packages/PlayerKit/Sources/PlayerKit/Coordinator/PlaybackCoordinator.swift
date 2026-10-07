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

    public let plan: PlaybackPlan
    public var onEnded: (@MainActor () -> Void)?

    private let makeEngine: @MainActor (PlaybackCandidate) -> (any PlaybackEngine)?
    private let resumeFrom: TimeInterval
    private let startupTimeout: Duration
    private let progress: ProgressSession?
    private var observer: Task<Void, Never>?
    private var startContinuation: CheckedContinuation<Bool, Never>?
    private var hasStartedCurrent = false
    private var lastPosition: TimeInterval = 0
    private var stopped = false

    public init(plan: PlaybackPlan, resumeFrom: TimeInterval = 0, startupTimeout: Duration = .seconds(20), progress: ProgressSession? = nil,
                makeEngine: @escaping @MainActor (PlaybackCandidate) -> (any PlaybackEngine)?) {
        self.plan = plan
        self.resumeFrom = resumeFrom
        self.startupTimeout = startupTimeout
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
    public func selectAudioTrack(id: String?) { engine?.selectAudioTrack(id: id) }
    public func selectEmbeddedSubtitleTrack(id: String?) { engine?.selectEmbeddedSubtitleTrack(id: id) }

    // MARK: Candidates

    private func tryCandidate(at index: Int, startPosition: TimeInterval) async {
        guard !stopped else { return }
        guard index < plan.candidates.count else {
            phase = .exhausted
            notice = plan.candidates.isEmpty ? "There is nothing to play." : "None of the streams could be played."
            return
        }
        candidateIndex = index
        let candidate = plan.candidates[index]
        current = candidate

        guard let engine = makeEngine(candidate), let url = candidate.url else {
            recordFailure(candidate, PlaybackFailure(.noEngine, "No player is available for this stream."))
            await moveOn(startPosition: startPosition)
            return
        }
        observer?.cancel()
        self.engine?.stop()
        self.engine = engine
        engineGeneration += 1
        state = engine.state
        hasStartedCurrent = false
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
            phase = .playing
            notice = failedAttempts.isEmpty ? nil : notice
        } else if !hasStartedCurrent {
            if state.failure == nil { recordFailure(candidate, PlaybackFailure(.timeout, "The stream took too long to start.")) }
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

    /// Resolves true when the engine reports it can play, false on failure or timeout.
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
        state = next
        if next.hasStarted, !hasStartedCurrent {
            hasStartedCurrent = true
            resolveStart(true)
        }
        if next.status == .playing || next.status == .paused { lastPosition = next.position }
        if next.hasStarted { progress?.observe(position: next.position, duration: next.duration) }

        switch next.status {
        case .failed(let failure):
            guard let candidate = current else { return }
            if hasStartedCurrent {
                // Failed mid-stream: remember it and carry on from where it stopped.
                recordFailure(candidate, failure)
                Task { [weak self] in await self?.moveOn(startPosition: self?.lastPosition ?? 0) }
            } else {
                recordFailure(candidate, failure)
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
}
