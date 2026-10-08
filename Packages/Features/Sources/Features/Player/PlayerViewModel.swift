import Foundation
import Observation
import PlayerKit
import StremioKit

public enum PlayerTime {
    /// `2:03` or `1:02:03`.
    public static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Everything the player screen shows and does, on top of `PlaybackCoordinator`. Contains no SwiftUI, so it is tested on the host.
@MainActor
@Observable
public final class PlayerViewModel {
    public enum SubtitleChoice: Hashable, Sendable {
        case off
        case external(String)
        case embedded(String)
    }

    public static let controlsHideDelay: TimeInterval = 3
    public static let maximumSubtitleOffset: TimeInterval = 60

    public let plan: PlaybackPlan
    public private(set) var coordinator: PlaybackCoordinator?
    public private(set) var subtitleOptions: [SubtitleOption] = []
    public private(set) var subtitleChoice: SubtitleChoice = .off
    public private(set) var subtitleStatus: String?
    public private(set) var subtitleOffset: TimeInterval = 0
    public private(set) var controlsVisible = true
    public private(set) var isScrubbing = false
    public private(set) var scrubFraction = 0.0
    public private(set) var settings = PlaybackSettings()
    public private(set) var hasFinished = false

    private let services: AppServices
    private let now: @Sendable () -> Date
    private var timeline: SubtitleTimeline?
    private var lastInteraction: Date
    private var userChoseSubtitle = false
    private var subtitleTask: Task<Void, Never>?

    public init(plan: PlaybackPlan, services: AppServices, now: @escaping @Sendable () -> Date = Date.init) {
        self.plan = plan
        self.services = services
        self.now = now
        self.lastInteraction = now()
    }

    // MARK: Lifecycle

    /// Loads settings and resume position, starts playback (returns when playing or every stream failed), and fetches subtitles alongside.
    public func start() async {
        settings = await services.settings.load()
        let previous = await services.progress.progress(for: plan.request.identity)
        let resume = ProgressRecorder.resumePosition(for: previous)
        let session = ProgressSession(request: plan.request, previous: previous, store: services.progress)
        let coordinator = PlaybackCoordinator(plan: plan, resumeFrom: resume, progress: session, makeEngine: services.makeEngine)
        coordinator.onEnded = { [weak self] in self?.hasFinished = true }
        self.coordinator = coordinator
        startSubtitles()
        await coordinator.start()
    }

    public func close() async {
        subtitleTask?.cancel()
        await coordinator?.stop()
    }

    // MARK: Playback state (read-through)

    public var state: PlaybackState { coordinator?.state ?? PlaybackState() }
    public var title: String { coordinator?.current?.title ?? plan.request.title }
    public var isPlaying: Bool { state.isPlaying }
    public var isBuffering: Bool {
        switch state.status {
        case .loading, .buffering: return true
        default: return coordinator?.phase == .starting
        }
    }
    public var position: TimeInterval { isScrubbing ? scrubFraction * (state.duration ?? 0) : state.position }
    public var duration: TimeInterval? { state.duration }
    public var fraction: Double { isScrubbing ? scrubFraction : (state.duration.map { $0 > 0 ? min(1, state.position / $0) : 0 } ?? 0) }
    public var positionText: String { PlayerTime.format(position) }
    public var remainingText: String { state.duration.map { "-" + PlayerTime.format(max(0, $0 - position)) } ?? "" }
    public var notice: String? { coordinator?.notice }
    public var hasNextStream: Bool { (coordinator?.candidateIndex ?? 0) + 1 < plan.candidates.count }
    public var hasNextEpisode: Bool { plan.request.nextRequest != nil }
    public var canPictureInPicture: Bool { coordinator?.current?.route.isNative == true }

    /// Set once every stream failed.
    public var failureMessage: String? {
        guard coordinator?.phase == .exhausted else { return nil }
        let reasons = Array(Set(coordinator?.failedAttempts.map(\.failure.message) ?? [])).sorted().prefix(2).joined(separator: " ")
        return reasons.isEmpty ? "This couldn't be played." : "None of the streams could be played. \(reasons)"
    }

    // MARK: Transport

    public func togglePlayPause() {
        coordinator?.togglePlayPause()
        showControls()
    }

    public func skip(by seconds: TimeInterval) async {
        showControls()
        await coordinator?.skip(by: seconds)
    }

    public func nextStream() async {
        showControls()
        await coordinator?.advance()
    }

    public func setRate(_ rate: Float) {
        coordinator?.setRate(rate)
        showControls()
    }

    public func beginScrub() {
        isScrubbing = true
        scrubFraction = fraction
        showControls()
    }

    public func updateScrub(fraction: Double) {
        scrubFraction = min(1, max(0, fraction))
        showControls()
    }

    public func endScrub() async {
        guard isScrubbing else { return }
        let target = scrubFraction * (state.duration ?? 0)
        await coordinator?.seek(to: target)
        isScrubbing = false
    }

    // MARK: Controls visibility

    public func showControls() {
        controlsVisible = true
        lastInteraction = now()
    }

    public func toggleControls() {
        if controlsVisible { controlsVisible = false } else { showControls() }
    }

    /// Call periodically. Hides the controls after a few idle seconds, but only while playing and not scrubbing.
    public func hideControlsIfIdle() {
        guard controlsVisible, isPlaying, !isScrubbing, now().timeIntervalSince(lastInteraction) >= Self.controlsHideDelay else { return }
        controlsVisible = false
    }

    // MARK: Audio and embedded subtitles

    public var audioTracks: [MediaTrack] { state.audioTracks }
    public var selectedAudioTrackID: String? { state.selectedAudioTrackID }

    public func selectAudioTrack(id: String) {
        coordinator?.selectAudioTrack(id: id)
        showControls()
    }

    // MARK: Subtitles

    public var embeddedSubtitleTracks: [MediaTrack] { state.embeddedSubtitleTracks }

    /// The line to draw, or nil. Reads the engine clock through `state.position`, so it updates with playback.
    public var cueText: String? {
        guard case .external = subtitleChoice else { return nil }
        return timeline?.text(at: state.position, offset: subtitleOffset)
    }

    public func selectSubtitle(_ choice: SubtitleChoice) async {
        userChoseSubtitle = true
        showControls()
        await apply(choice)
    }

    public func adjustSubtitleOffset(by delta: TimeInterval) {
        let limit = Self.maximumSubtitleOffset
        subtitleOffset = min(limit, max(-limit, ((subtitleOffset + delta) * 10).rounded() / 10))
        showControls()
    }

    public func resetSubtitleOffset() {
        subtitleOffset = 0
    }

    private func apply(_ choice: SubtitleChoice) async {
        switch choice {
        case .off:
            timeline = nil
            coordinator?.selectEmbeddedSubtitleTrack(id: nil)
            subtitleStatus = nil
            subtitleChoice = .off
        case .embedded(let id):
            timeline = nil
            coordinator?.selectEmbeddedSubtitleTrack(id: id)
            subtitleStatus = nil
            subtitleChoice = .embedded(id)
        case .external(let id):
            guard let option = subtitleOptions.first(where: { $0.id == id }) else { return }
            coordinator?.selectEmbeddedSubtitleTrack(id: nil)
            subtitleStatus = "Loading subtitles…"
            do {
                let loaded = try await services.subtitles.load(option)
                guard !Task.isCancelled else { return }
                timeline = loaded
                subtitleStatus = nil
                subtitleChoice = .external(id)
            } catch {
                timeline = nil
                subtitleStatus = "Couldn't load these subtitles."
                subtitleChoice = .off
            }
        }
    }

    private func startSubtitles() {
        guard let first = plan.candidates.first else { return }
        subtitleTask = Task { [weak self] in
            guard let self else { return }
            var options = SubtitleService.options(from: first.subtitles)
            subtitleOptions = options
            await applyDefaultSubtitle()
            for await response in await services.subtitles.fetch(for: first, request: plan.request) {
                if let items = response.value {
                    options = SubtitleService.merge(options, SubtitleService.options(from: items, addon: response.addon.name))
                    subtitleOptions = options
                }
                await applyDefaultSubtitle()
            }
        }
    }

    /// Picks the subtitle matching the user's default language, once, unless they already chose.
    private func applyDefaultSubtitle() async {
        guard !userChoseSubtitle, subtitleChoice == .off,
              let option = SubtitleService.defaultOption(in: subtitleOptions, preferredLanguage: settings.subtitleLanguage) else { return }
        await apply(.external(option.id))
    }

    /// Waits for the subtitle lookup (used by tests).
    public func waitForSubtitles() async {
        await subtitleTask?.value
    }

    // MARK: Next episode

    /// Streams for the next episode, auto-selecting one in the same bingeGroup as the current stream (PLAN M4).
    /// nil when there is no next episode or no matching stream: the caller then shows the picker for it.
    public func prepareNextEpisode() async -> PlaybackPlan? {
        guard let next = plan.request.nextRequest else { return nil }
        let picker = StreamPickerViewModel(request: next, services: services)
        await picker.load()
        let context = plan.candidates.indices.contains(coordinator?.candidateIndex ?? 0) ? plan.candidates[coordinator?.candidateIndex ?? 0].bingeContext : nil
        if case .play(let nextPlan)? = await picker.bingeChoice(continuing: context) { return nextPlan }
        return nil
    }
}

extension PlaybackRoute {
    var isNative: Bool {
        if case .native = self { return true }
        return false
    }
}
