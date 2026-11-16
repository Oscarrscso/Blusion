import Foundation
import Observation
import Persistence
import PlayerKit
import StremioKit

enum PlayerTime {
    /// `2:03` or `1:02:03`.
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Everything the player screen shows and does, on top of `PlaybackCoordinator`. Contains no SwiftUI, so it is tested on the host.
@MainActor
@Observable
final class PlayerViewModel {
    enum SubtitleChoice: Hashable, Sendable {
        case off
        case external(String)
        case embedded(String)
    }

    static let controlsHideDelay: TimeInterval = 3
    static let maximumSubtitleOffset: TimeInterval = 60
    static let maximumAudioDelay: TimeInterval = 10
    /// How often a playing session refreshes its snapshot: often enough that a kill loses seconds, rare enough that the file is
    /// not written on every tick. A pause or the app leaving the front refreshes it at once.
    static let snapshotRefreshInterval: TimeInterval = 15

    let plan: PlaybackPlan
    private(set) var coordinator: PlaybackCoordinator?
    var subtitleOptions: [SubtitleOption] = [] {
        didSet { externalSubtitleRows = PlayerTrackPresentation.external(subtitleOptions) }
    }
    private(set) var externalSubtitleRows: [PlayerTrackRow] = []
    var embeddedSubtitleRows: [PlayerTrackRow] = []
    var audioTrackRows: [PlayerTrackRow] = []
    var audioTrackSelectionID: String?
    var subtitleChoice: SubtitleChoice = .off
    /// The line under the subtitle menu: a choice under way, or what stopped the last one.
    var subtitleStatus: String? {
        switch subtitleActivity {
        case .idle: nil
        case .loading: "Loading subtitles…"
        case .switchingPlayer: "Switching to the advanced player for picture subtitles…"
        case .failed(let message): message
        }
    }
    /// Positive delays the subtitles. Applies to whichever draws them: the app's overlay, or the engine for its own tracks and files.
    var subtitleOffset: TimeInterval = 0
    var controlsVisible = true
    var isScrubbing = false
    var scrubFraction = 0.0
    /// Picture drags keep only the newest target while the engine finishes its current seek.
    var pendingScrubSeek: TimeInterval?
    var scrubSeekTask: Task<Void, Never>?
    private(set) var settings = PlaybackSettings()
    private(set) var hasFinished = false
    /// A styled (ASS) file the overlay draws simplified; the advanced player would draw its effects.
    var hasSimplifiedStyling: Bool {
        if case .overlay(_, _, let simplified) = drawing { return simplified }
        return false
    }
    var openSubtitlesResults: [OpenSubtitlesResult] = []
    var openSubtitlesStatus: String?
    var isSearchingOpenSubtitles = false

    let services: AppServices
    /// The session store this player keeps current: the app's one, or a test's memory.
    let snapshotStore: any PlaybackSnapshotStore
    /// A session begun in Ghost mode stays private even if the preference changes before it closes.
    let persistsSession: Bool
    let isPrivateSession: @Sendable () -> Bool
    let now: @Sendable () -> Date
    /// Who draws the chosen subtitle file: the engine (loaded into it), or the app's overlay from the cues it loaded. None for Off, an
    /// embedded track (the engine's own) and a file still loading for the first time.
    enum SubtitleDrawing {
        case none
        case engine(optionID: String)
        /// `simplified`: a styled (ASS) file drawn without its effects, which the advanced player would draw.
        case overlay(text: SubtitleTimeline?, bitmap: BitmapSubtitleTimeline?, simplified: Bool)
    }
    var drawing = SubtitleDrawing.none
    var engineDrawsFile: Bool {
        if case .engine = drawing { return true }
        return false
    }
    /// A subtitle choice under way, or what stopped the last one.
    enum SubtitleActivity: Equatable {
        case idle
        /// A file loading for the overlay: presses during it, and a repeat of the same default, see this choice as made.
        case loading(SubtitleChoice)
        /// Picture subtitles the overlay cannot draw: the stream is reopening in the advanced player, which draws them.
        case switchingPlayer
        case failed(String)
    }
    var subtitleActivity = SubtitleActivity.idle
    /// The subtitle choice a load in flight is working towards.
    var pendingChoice: SubtitleChoice? {
        if case .loading(let choice) = subtitleActivity { return choice }
        return nil
    }
    /// Written on every pointer move over the Mac player and read only by the idle timer, so it is kept out of observation.
    @ObservationIgnored var lastInteraction: Date
    var userChoseSubtitle = false
    var userChoseAudio = false
    /// The choice the defaults made, while the listener has not made one: a better default (an embedded track) may still replace it.
    var automaticChoice: SubtitleChoice?
    /// Goes up with each choice, so a load that returns after a newer choice is dropped.
    var subtitleGeneration = 0
    var subtitleTask: Task<Void, Never>?
    var lookupTasks: [Task<Void, Never>] = []
    var pendingSubtitleLookups = 0
    var lookedUpCandidates: Set<String> = []
    var skippedMarkers: Set<SkipMarker> = []
    private var temporaryFiles: [URL] = []
    private var saveTask: Task<Void, Never>?
    /// Where the session stands, from its start to its close.
    enum Lifecycle: Equatable {
        /// Nothing begun.
        case idle
        /// Loading its settings and saved progress before it makes its player: for the screen at once (`start`), or to hold until
        /// the screen shows (`prepare`).
        case beginning(holding: Bool)
        /// Readied by `prepare`: muted, paused on its first frame, and saving no progress until its screen shows.
        case held
        /// Playing, or paused, for the viewer.
        case live
        /// Closed by `close`: a start still loading its settings then makes no player, and a screen rejoining its session never gets
        /// a closed one (`LivePlaybackSession.session(for:)`).
        case closed
    }
    var lifecycle = Lifecycle.idle
    /// The start made by `prepare`, so `start` (the screen appearing) waits for it instead of starting again.
    private var preparation: Task<Void, Never>?
    private var progressSession: ProgressSession?
    var isClosed: Bool { lifecycle == .closed }
    /// A session being walked back into: its position, pause, track choices and picture, taken over as the engine comes up. Its
    /// track choices are applied once the engine lists its tracks; it is cleared then, so a later track list never overrides a fresh
    /// choice.
    var pendingResume: PlaybackSnapshot?
    /// The session was left paused: the screen showing does not start it again.
    var resumeWasPaused = false
    /// When the snapshot was last refreshed, so playback writes it every few seconds rather than every tick.
    var lastSnapshotRefresh: Date?

    init(plan: PlaybackPlan, services: AppServices, now: @escaping @Sendable () -> Date = Date.init,
                snapshotStore: (any PlaybackSnapshotStore)? = nil,
                isPrivateSession: @escaping @Sendable () -> Bool = { GhostMode.isOn }) {
        self.plan = plan
        self.services = services
        self.snapshotStore = snapshotStore ?? PlaybackSession.store
        self.isPrivateSession = isPrivateSession
        // Channels reopen through their current guide, not a stale episode snapshot after the schedule has moved on.
        self.persistsSession = !isPrivateSession() && plan.queue == nil
        self.now = now
        self.lastInteraction = now()
    }

    // MARK: Lifecycle

    /// Loads settings and resume position, starts playback (returns when playing or every stream failed), and fetches subtitles alongside.
    /// A player readied by `prepare` is not started again: it waits for that start, then plays from where it held.
    func start() async {
        guard !isClosed, !Task.isCancelled else { return }
        if let preparation {
            await preparation.value
            releaseHold()
            return
        }
        // Already running: a screen rejoining its session (a rebuild while the app was away, or a second start) does not begin again.
        guard lifecycle == .idle else { return }
        lifecycle = .beginning(holding: false)
        await begin(holding: false)
    }

    /// Readies playback before the player's screen shows: the stream loads and starts muted, then holds paused on its first frame with
    /// no progress saved. Returns once it is ready, or once every stream has failed. `start` then plays it at once. Calling it again
    /// waits for the same start.
    func prepare() async {
        guard !isClosed, !Task.isCancelled else { return }
        if let preparation {
            await preparation.value
            return
        }
        // A start already under way for the screen is not readied a second time.
        guard lifecycle == .idle else { return }
        lifecycle = .beginning(holding: true)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.begin(holding: true)
        }
        preparation = task
        await task.value
    }

    /// True once a prepared player has a stream ready to play (or has nothing to play: every stream failed).
    var isPrepared: Bool {
        guard preparation != nil, let phase = coordinator?.phase else { return false }
        return phase == .playing || phase == .exhausted
    }

    var preparationProgress: PlaybackPreparation? {
        guard !isClosed else { return nil }
        return coordinator?.preparationProgress ?? PlaybackPreparation(stage: .loadingMedia)
    }

    /// The stream has started playing: until then the player shows no play or seek controls, only that it is loading.
    var hasStartedPlayback: Bool {
        guard let phase = coordinator?.phase else { return false }
        return phase == .playing || phase == .finished
    }

    func begin(holding: Bool) async {
        // Both at once: the stream starts loading only after them.
        async let loadedSettings = services.settings.load()
        async let savedProgress = services.progress.progress(for: plan.request.identity)
        settings = await loadedSettings
        let previous = await savedProgress
        guard !isClosed, !Task.isCancelled else {
            if case .beginning = lifecycle { lifecycle = .idle }
            return
        }
        if let id = plan.downloadID {
            services.downloads?.opened(id)
            if persistsSession, !isPrivateSession() {
                if let snapshot = await snapshotStore.load(), snapshot.downloadID == id { pendingResume = snapshot } else if !isClosed,
                    !Task.isCancelled, !isPrivateSession() {
                    let snapshot = PlaybackSnapshot(downloadID: id, request: plan.request, stream: PlaybackStreamIdentity(kind: .direct))
                    try? await snapshotStore.save(snapshot)
                }
            }
        }
        guard !isClosed, !Task.isCancelled else {
            // A start called off before it made a player (its screen went) leaves the next start free to begin again.
            if case .beginning = lifecycle { lifecycle = .idle }
            return
        }
        // The saved session knows where the viewer actually was, past what the progress store had flushed; progress still resumes a
        // session whose snapshot was at its start.
        var resume = ProgressRecorder.resumePosition(for: previous)
        if let position = pendingResume?.position, position > 0 { resume = position }
        if let position = plan.initialPosition { resume = position }
        if plan.queue != nil, !holding, !isPrivateSession() { await snapshotStore.clear() }
        guard !isClosed, !Task.isCancelled else { return }
        resumeWasPaused = pendingResume?.wasPaused ?? false
        let session = ProgressSession(request: plan.request, previous: previous, store: services.progress)
        session.isRecording = !holding
        progressSession = session
        let player = settings.player
        // The picture is Zoom Mode's, kept for every video, with this title's Aspect Ratio (as in Infuse).
        zoomMode = player.zoomMode.onThisDevice
        aspectRatio = player.aspectRatios[AspectRatioChoice.titleKey(for: plan.request)] ?? .original
        let coordinator = PlaybackCoordinator(plan: plan, resumeFrom: resume, progress: session, layout: pictureLayout,
                                              processing: pendingResume?.processing ?? player.processing,
                                              subtitleStyle: player.subtitleStyle, makeEngine: services.makeEngine)
        // Settings → Player's speed. Kept by the coordinator, which gives it to each engine it makes.
        if player.playbackSpeed != 1 { coordinator.setRate(Float(player.playbackSpeed)) }
        coordinator.onEnded = { [weak self] in
            self?.hasFinished = true
            // The film ended mid-hold: it must not carry on at the held speed into whatever plays next.
            self?.endHeldSpeed()
        }
        coordinator.onCandidateChange = { [weak self] candidate in
            self?.lookUpSubtitles(for: candidate)
        }
        coordinator.onEngineChange = { [weak self] in self?.engineChanged() }
        coordinator.onTracksChange = { [weak self] in self?.tracksChanged() }
        self.coordinator = coordinator
        lifecycle = holding ? .held : .live
        // Muted before the first engine is made, so the start makes no sound while the screen is not up.
        if holding { coordinator.setMuted(true) }
        startSubtitles()
        await coordinator.start()
        // A restored session takes its track choices over once the engine lists them.
        restoreChoicesIfPossible()
        // Ready: it waits, paused on its first frame, for the screen.
        if lifecycle == .held, coordinator.phase == .playing { coordinator.pause() }
        // A session left paused stays paused when its screen shows.
        else if resumeWasPaused, coordinator.phase == .playing { coordinator.pause() }
    }

    /// The screen is up: a held player saves progress, gets its sound back and plays, unless the session was left paused.
    private func releaseHold() {
        guard lifecycle == .held, let coordinator else { return }
        lifecycle = .live
        progressSession?.isRecording = true
        coordinator.setMuted(false)
        if coordinator.phase == .playing, !resumeWasPaused { coordinator.play() }
    }

    func close() async {
        lifecycle = .closed
        preparation?.cancel()
        // Closing ends any hold without a further engine call: the engine is being stopped.
        heldSpeed = nil
        cancelScrub()
        subtitleTask?.cancel()
        lookupTasks.forEach { $0.cancel() }
        await coordinator?.stop()
        temporaryFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryFiles = []
        if let id = plan.downloadID {
            let progress = await services.progress.progress(for: plan.request.identity)
            await services.downloads?.closed(id, watched: progress?.isWatched == true)
        }
    }

    /// True once a session exists and has not been closed: the app-level holder keeps such a session alive across its screen's
    /// appearances and disappearances (including backgrounding), and hands it back to a screen that reopens the same plan.
    var isSessionLive: Bool { lifecycle == .held || lifecycle == .live }

    // MARK: Playback state (read-through)

    var state: PlaybackState { coordinator?.state ?? PlaybackState() }
    var title: String { coordinator?.current?.title ?? plan.request.title }
    var isPlaying: Bool { state.isPlaying }
    var isBuffering: Bool {
        switch state.status {
        case .loading, .buffering: return true
        default: return coordinator?.phase == .starting
        }
    }
    /// A requested playback that is waiting on the engine, including a reconnect or an engine that briefly reports ready/paused.
    /// Pausing explicitly clears the requested-playback flag, so an intentional pause never shows a spinner.
    var isStalled: Bool {
        guard let coordinator, coordinator.isPlaybackRequested, failureMessage == nil,
              coordinator.phase == .playing || coordinator.phase == .starting else { return false }
        switch state.status {
        case .loading, .ready, .paused, .buffering: return true
        default: return false
        }
    }
    /// The stall spinner stands alone while the controls are hidden; with them showing it takes the play button's place.
    var showsBufferingIndicator: Bool { isStalled && !controlsVisible }
    /// Pause means cancel the current play request, even if the engine is still buffering or ready.
    var wantsPlayback: Bool { coordinator?.isPlaybackRequested == true }
    var position: TimeInterval { isScrubbing ? scrubFraction * (state.duration ?? 0) : state.position }
    var duration: TimeInterval? { state.duration }
    var fraction: Double { isScrubbing ? scrubFraction : (state.duration.map { $0 > 0 ? min(1, state.position / $0) : 0 } ?? 0) }
    var positionText: String { PlayerTime.format(position) }
    var remainingText: String { state.duration.map { "-" + PlayerTime.format(max(0, $0 - position)) } ?? "" }
    var notice: String? { coordinator?.notice }
    var hasNextStream: Bool { (coordinator?.candidateIndex ?? 0) + 1 < plan.candidates.count }
    var currentStreamIndex: Int { coordinator?.candidateIndex ?? 0 }
    /// The stream playing now, as its addon listed it (the options panel's Info).
    var currentCandidate: PlaybackCandidate? { coordinator?.current }
    var hasNextEpisode: Bool { !plan.isOffline && (plan.queue?.next != nil || plan.request.nextRequest != nil) }
    /// AVPlayer and AetherEngine play in a layer Picture in Picture can take. mpv has none, so its window never becomes possible.
    var canPictureInPicture: Bool {
        guard let route = coordinator?.current?.route else { return false }
        switch route {
        case .native, .fallback: return true
        default: return false
        }
    }
    var volume: Float { coordinator?.volume ?? 1 }
    var isMuted: Bool { coordinator?.isMuted ?? false }
    var capabilities: EngineCapabilities { coordinator?.capabilities ?? [] }
    var preferences: PlayerPreferences { settings.player }
    /// A fallback engine is there to take the stream over, and the current engine cannot draw subtitles with full styling itself.
    var canOpenInAdvancedPlayer: Bool {
        plan.retriesInFallbackEngine && coordinator?.current?.url != nil && !capabilities.contains(.engineSubtitles)
    }

    /// Set once every stream failed.
    var failureMessage: String? {
        guard coordinator?.phase == .exhausted else { return nil }
        let reasons = Array(Set(coordinator?.failedAttempts.map(\.failure.message) ?? [])).sorted().prefix(2).joined(separator: " ")
        return reasons.isEmpty ? "This couldn't be played." : "None of the streams could be played. \(reasons)"
    }

    func statistics() -> PlaybackStatistics? { coordinator?.statistics() }

    /// Set from `beginHeldSpeed` until `endHeldSpeed`; nil otherwise.
    var heldSpeed: HeldSpeed?

    /// As in Infuse: one global setting, kept for every video. Read from Settings when playback begins.
    var zoomMode: ZoomMode = .normal
    /// As in Infuse: kept per title (a film, or a TV season). Read when playback begins; Original when none was chosen.
    var aspectRatio: AspectRatioChoice = .original
    /// How far the safe area keeps the picture from each side, in points (beside a notch or Dynamic Island): Normal fits inside it.
    var safeAreaInset: Double = 0

    // MARK: Files and preferences

    /// A copy the player can read for as long as it plays: files from the document picker are security-scoped.
    func copyIn(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("blusion-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: copy)
            temporaryFiles.append(copy)
            return copy
        } catch {
            return nil
        }
    }

    /// "Movie.2020.en.srt", "Movie.English.forced.ass" → the language they name.
    static func language(inFileName name: String) -> String? {
        let parts = (name as NSString).deletingPathExtension.split(whereSeparator: { ".-_ ".contains($0) }).map(String.init)
        for part in parts.reversed().prefix(3) where part.count >= 2 {
            let code = LanguageCodes.normalise(part)
            if LanguageCodes.iso639_1(code) != nil { return code }
        }
        return nil
    }

    /// Player changes the listener makes are their new defaults (Settings shows them too).
    /// Saves run one after another, so quick changes in a row cannot overwrite each other.
    func savePreferences(_ change: @escaping @MainActor @Sendable (inout PlayerPreferences) -> Void) {
        change(&settings.player)
        let store = services.settings
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            _ = await store.update { change(&$0.player) }
        }
    }

    /// Waits for preference saves (used by tests).
    func waitForSavedPreferences() async {
        await saveTask?.value
    }

    // MARK: Next episode

    /// Streams for the next episode, auto-selecting one in the same bingeGroup as the current stream.
    /// nil when there is no next episode or no matching stream: the caller then shows the picker for it.
    func prepareNextEpisode() async -> PlaybackPlan? {
        if var nextQueue = plan.queue?.next {
            // A queue passes over up to two items with no playable stream, so a channel moves on rather than stopping.
            for _ in 0..<min(3, nextQueue.requests.count) {
                let picker = StreamPickerViewModel(request: nextQueue.requests[nextQueue.index], services: services)
                await picker.loadForAutomaticSelection(stopsForWaitTarget: false)
                picker.cancelLoading()
                guard !Task.isCancelled else { return nil }
                if let chosen = picker.bestInAppPlan { return chosen.inQueue(nextQueue, startingAt: nextQueue.startsFromBeginning ? 0 : nil) }
                guard let after = nextQueue.next else { return nil }
                nextQueue = after
            }
            return nil
        }
        guard !plan.isOffline, let next = plan.request.nextRequest else { return nil }
        let picker = StreamPickerViewModel(request: next, services: services)
        defer { picker.cancelLoading() }
        // Every addon's answers within the window, as before: the stream continuing this one may come from a slower addon.
        await picker.loadForAutomaticSelection(stopsForWaitTarget: false)
        if case .play(let nextPlan)? = await picker.bingeChoice(continuing: bingeContext) { return nextPlan }
        return nil
    }

    /// Readies a chosen episode's streams, as `prepareNextEpisode` does for the one after this: the stream continuing this binge where
    /// the addons have it, else the best they offer that Blusion itself can play. Nil when none of them can be played.
    func prepareEpisode(_ request: StreamRequest) async -> PlaybackPlan? {
        guard !plan.isOffline else { return nil }
        let picker = StreamPickerViewModel(request: request, services: services)
        defer { picker.cancelLoading() }
        await picker.loadForAutomaticSelection(stopsForWaitTarget: false)
        if case .play(let chosenPlan)? = await picker.bingeChoice(continuing: bingeContext) { return chosenPlan }
        // Already in the player: the chosen episode plays here even when the saved policy would hand streams to another app.
        guard let best = picker.bestToPlay, case .play(let chosenPlan)? = picker.inAppChoice(for: best) else { return nil }
        return chosenPlan
    }

    /// The release this playback continues, which the next episode's stream or a chosen one's keeps where the addons offer it.
    private var bingeContext: BingeContext? {
        let index = coordinator?.candidateIndex ?? 0
        guard plan.candidates.indices.contains(index) else { return nil }
        return plan.candidates[index].bingeContext
    }
}

/// The player as the snapshot store sees it: it takes a saved session over on restore, and reports where it is while it plays.
extension PlayerViewModel: PlaybackSnapshotResuming, PlaybackSnapshotRecording {}

extension PlaybackRoute {
    var isNative: Bool {
        if case .native = self { return true }
        return false
    }
}
