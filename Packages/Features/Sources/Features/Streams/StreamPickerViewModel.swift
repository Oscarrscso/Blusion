import Foundation
import Observation
import PlayerKit
import StremioKit

/// Stream picker: results appear grouped by addon as each one answers; ambiguous URLs are probed in the background.
@MainActor
@Observable
public final class StreamPickerViewModel {
    public enum Choice: Equatable {
        case play(PlaybackPlan)
        case openExternal(URL)
        /// The stream goes to another player app: open this link, which starts it there.
        case openInPlayer(ExternalPlayer, URL)
        /// The format needs an engine this build doesn't have. The picker offers the next stream.
        case unsupported(next: RankedStream?)
    }

    /// One addon's streams in the picker. Links to web pages are not in here: they have a group of their own (`links`).
    public struct AddonSection: Identifiable, Equatable {
        public let addon: AddonSummary
        public let streams: [RankedStream]
        public var id: UUID { addon.id }
    }

    public let request: StreamRequest
    public private(set) var listing: StreamListing {
        didSet {
            if listing.items != oldValue.items || listing.isLoading != oldValue.isLoading { refreshDerivedListing() }
        }
    }
    /// True when no installed addon can answer this request at all (as opposed to "still loading" or "nothing found").
    public private(set) var nobodyCanAnswer = false
    public private(set) var settings = PlaybackSettings()
    public private(set) var hasLoaded = false
    public private(set) var isAutoPicking = false
    public private(set) var autoPickMessage: String?
    public private(set) var autoPickedStream: RankedStream?

    private let services: AppServices
    private var sniffTasks: [Task<Void, Never>] = []
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var bestAssessment: AutoStreamRanking.Assessment?
    /// The player apps on this device, as the view reported them. Kept here so a load after it still routes with them.
    private var installedPlayers: Set<ExternalPlayer> = []

    /// Extensions a file can carry for Infuse to name it by. Release names often end in something else ("...H.265-playWEB"), so only these
    /// count as the file's extension.
    private static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "webm", "wmv", "flv", "mpg", "mpeg"]

    public init(request: StreamRequest, services: AppServices) {
        self.request = request
        self.services = services
        self.listing = StreamListing(asking: [])
    }

    public var isLoading: Bool { !hasLoaded || listing.isLoading }
    /// Nothing found, and every addon that was asked failed because the device is offline.
    public var isOffline: Bool { hasLoaded && listing.isEmpty && Connectivity.isOffline(listing.failures.map(\.error)) }
    public var showsNothingFound: Bool { hasLoaded && !listing.isLoading && listing.isEmpty && !nobodyCanAnswer && !isOffline }

    /// Each addon's streams that Blusion or another app can play, in the user's addon order.
    public private(set) var addonSections: [AddonSection] = []

    /// Links to addon web pages, displayed separately from playable streams.
    public private(set) var links: [RankedStream] = []

    private func refreshDerivedListing() {
        addonSections = listing.groups.compactMap { group in
            let streams = group.streams.filter { !Self.isLink($0) }
            return streams.isEmpty ? nil : AddonSection(addon: group.addon, streams: streams)
        }
        links = listing.items.filter(Self.isLink)
        bestAssessment = listing.isLoading ? nil : AutoStreamRanking.best(from: infuseCandidates, duration: request.expectedDuration)
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        settings = await services.settings.load()
        let (asked, responses) = await services.streams.fetch(request)
        guard !Task.isCancelled, generation == loadGeneration else { return }
        var config = settings.policy(fallbackEngineLinked: services.fallbackEngineLinked)
        config.installedPlayers = installedPlayers
        listing = StreamListing(asking: asked, config: config, preferences: settings.rankingPreferences)
        nobodyCanAnswer = asked.isEmpty
        hasLoaded = true
        guard !asked.isEmpty else { return }

        await withTaskCancellationHandler {
            var requested = Set<String>()
            for await response in responses {
                guard !Task.isCancelled, generation == loadGeneration else { return }
                listing.apply(response)
                let targets = listing.sniffTargets.filter { requested.insert($0.key).inserted }
                if !targets.isEmpty { startSniffing(targets) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.loadGeneration == generation else { return }
                self?.cancelSniffing()
            }
        }
    }

    /// Automatic playback has a total selection deadline; slower answers still improve the open picker.
    public func loadForAutomaticSelection(timeout: Duration = .seconds(5)) async {
        if !hasLoaded, loadingTask == nil {
            loadingTask = Task { [weak self] in
                guard let self else { return }
                await self.load()
            }
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while isLoading, ContinuousClock.now < deadline, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
        }
        if Task.isCancelled { cancelLoading() }
    }

    public func cancelLoading() {
        loadGeneration += 1
        if listing.isLoading { hasLoaded = false }
        loadingTask?.cancel()
        loadingTask = nil
        cancelSniffing()
    }

    // MARK: best Blu-ray edition

    /// Where a lookup of this film's best Blu-ray edition on bestblurays.com stands.
    public enum BestEditionState: Equatable {
        case idle
        case loading
        case found(BestBlurayEdition)
        /// The site has a page for the film but has named no best release on it yet.
        case listedWithoutEdition(title: String, url: URL)
        /// The site has no page for the film; the link searches it for the title.
        case notListed(searchURL: URL)
        case failed(String)
    }

    public private(set) var bestEdition: BestEditionState = .idle

    /// The lookup is for films: the site is a guide to films' discs.
    public var canFindBestEdition: Bool { request.type == "movie" && LetterboxdRatings.isIMDbID(request.id) }

    /// Reads the film's page on bestblurays.com. Done once per stream picker: an answer is kept, and only a failure asks again.
    public func findBestEdition() async {
        guard canFindBestEdition else { return }
        switch bestEdition {
        case .loading, .found, .listedWithoutEdition, .notListed: return
        case .idle, .failed: break
        }
        bestEdition = .loading
        do {
            let result = try await services.bestBlurays.bestEdition(imdbID: request.id, title: request.title, year: request.year)
            guard !Task.isCancelled else {
                bestEdition = .idle
                return
            }
            switch result {
            case .edition(let edition): bestEdition = .found(edition)
            case .pageWithoutEdition(let title, let url): bestEdition = .listedWithoutEdition(title: title, url: url)
            case .noPage(let searchURL): bestEdition = .notListed(searchURL: searchURL)
            }
        } catch {
            // Leaving the stream picker cancels the lookup; it can run again when the page returns.
            bestEdition = Task.isCancelled ? .idle : .failed(AddonError.from(error).shortDescription)
        }
    }

    /// The player apps installed on this device. Streams are only handed to these. The view asks once, when the picker opens.
    public func setInstalledPlayers(_ players: Set<ExternalPlayer>) {
        installedPlayers = players
        var config = listing.config
        config.installedPlayers = players
        listing.update(config: config)
    }

    private func startSniffing(_ targets: [StreamListing.SniffTarget]) {
        let results = services.streams.sniff(targets)
        let generation = loadGeneration
        sniffTasks.append(Task { [weak self] in
            for await result in results {
                guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
                if let container = result.container { self.listing.setContainer(container, forKey: result.key) }
            }
        })
    }

    private func cancelSniffing() {
        sniffTasks.forEach { $0.cancel() }
    }

    /// What happens when the user taps a stream.
    public func choose(_ item: RankedStream) async -> Choice? {
        switch item.route {
        case .native, .fallback:
            return PlaybackPlan.make(request: request, chosen: item, from: listing).map(Choice.play)
        case .handoff(let player, _):
            return await handoffChoice(for: item, player: player)
        case .external(let url):
            return .openExternal(url)
        case .unsupported:
            return .unsupported(next: nextPlayable(after: item))
        case .hidden:
            return nil
        }
    }

    /// The best stream the user can start, in Blusion or in the app they chose, for a one-tap "Play best".
    public func playBest() async -> Choice? {
        guard let best = listing.best else { return nil }
        return await choose(best)
    }

    /// Called only by the explicit Auto Pick action. All resolutions, including REMUX, are compared together.
    public func autoPickBest() async -> Choice? {
        guard !isAutoPicking else { return nil }
        isAutoPicking = true
        autoPickMessage = nil
        defer { isAutoPicking = false }
        // The normal fetch already asks every installed addon whose manifest supports this title.
        // Wait for their releases instead of inventing unsupported resolution-specific addon queries.
        while isLoading {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return nil }
        }
        guard !Task.isCancelled else { return nil }
        guard let pick = bestAssessment else {
            autoPickMessage = "No streams compatible with Infuse were found."
            return nil
        }
        guard !Task.isCancelled else { return nil }
        autoPickedStream = pick.item
        autoPickMessage = "Selected \(pick.item.quality.resolutionLabel ?? "stream") · \(pick.isRemux ? "REMUX" : pick.item.quality.source?.rawValue ?? "release")"
        return await handoffChoice(for: pick.item, player: .infuse)
    }

    /// The stream Auto Pick would start, marked in the list before anyone asks for it. Nil while the addons are still answering, so the
    /// mark does not jump from one release to another as they arrive.
    public var recommendedStream: RankedStream? {
        guard !isLoading else { return nil }
        return bestAssessment?.item
    }

    /// The streams Infuse can take as they are: what Auto Pick ranks.
    private var infuseCandidates: [RankedStream] {
        listing.items.filter { item in
            guard let url = PlaybackPolicy.playbackURL(for: item.stream, config: listing.config) else { return false }
            return ExternalPlayer.infuse.canPlay(streamURL: url, headers: item.stream.behaviorHints.proxyHeaders?.request ?? [:])
        }
    }

    /// The first stream Blusion plays itself after `item`: what "Try the next stream" plays.
    public func nextPlayable(after item: RankedStream) -> RankedStream? {
        guard let index = listing.items.firstIndex(where: { $0.id == item.id }) else { return listing.playable.first }
        return listing.items[(index + 1)...].first { $0.route.isPlayable } ?? listing.playable.first
    }

    /// For binge-watching: the stream continuing the previous episode's group, if this listing has one.
    public func bingeChoice(continuing previous: BingeContext?) async -> Choice? {
        guard let pick = BingeSelection.pick(from: listing.items, continuing: previous) else { return nil }
        return await choose(pick)
    }

    /// The hand-off for `item` in `player`, remembered in the hand-off store so the callback can be recorded.
    /// nil when the player cannot take this stream (not an http(s) URL, or it needs request headers).
    public func handoffChoice(for item: RankedStream, player: ExternalPlayer) async -> Choice? {
        let headers = item.stream.behaviorHints.proxyHeaders?.request ?? [:]
        guard let streamURL = PlaybackPolicy.playbackURL(for: item.stream, config: listing.config),
              player.canPlay(streamURL: streamURL, headers: headers) else { return nil }
        let saved = await services.progress.progress(for: request.identity)
        let token = UUID().uuidString
        let link = ExternalPlaybackRequest(streamURL: streamURL,
                                           position: Self.wholeSeconds(ProgressRecorder.resumePosition(for: saved)),
                                           filename: fileName(for: item, streamURL: streamURL),
                                           subtitleURL: subtitleURL(for: item),
                                           successCallback: ExternalPlayerCallback.successURL(token: token),
                                           errorCallback: ExternalPlayerCallback.errorURL(token: token))
        guard let url = player.playURL(for: link) else { return nil }
        await services.handoffs.save(PlaybackHandoff(id: token, request: request, player: player))
        return .openInPlayer(player, url)
    }

    /// Installed players that could take this stream as an alternative to its default route (the row's context menu and the "unsupported
    /// format" alert use them). Empty when the route already is a hand-off to that player.
    public func alternativePlayers(for item: RankedStream) -> [ExternalPlayer] {
        guard let streamURL = PlaybackPolicy.playbackURL(for: item.stream, config: listing.config) else { return [] }
        let headers = item.stream.behaviorHints.proxyHeaders?.request ?? [:]
        return ExternalPlayer.allCases.filter { player in
            listing.config.installedPlayers.contains(player) && item.route.handoffTarget?.player != player
                && player.canPlay(streamURL: streamURL, headers: headers)
        }
    }

    /// Plays the stream in Blusion even though it would be handed off, when Blusion itself can play it. nil when it cannot.
    public func inAppChoice(for item: RankedStream) -> Choice? {
        var builtIn = listing.config
        builtIn.playerPreference = .builtIn
        let route = PlaybackPolicy.route(for: item.stream, container: item.container, quality: item.quality, config: builtIn)
        guard route.isPlayable else { return nil }
        return PlaybackPlan.make(request: request, chosen: item.rerouted(route), from: listing).map(Choice.play)
    }

    public func retry() async {
        cancelLoading()
        sniffTasks = []
        hasLoaded = false
        await load()
    }

    // MARK: details

    private static func isLink(_ item: RankedStream) -> Bool {
        if case .external = item.route { return true }
        return false
    }

    /// Whole seconds, rounded down. nil when there is less than a second to resume from.
    private static func wholeSeconds(_ seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, seconds >= 1, seconds < TimeInterval(Int.max) else { return nil }
        return Int(seconds)
    }

    /// The name Infuse gets: the series for an episode, the title for a movie, with the extension the file has.
    private func fileName(for item: RankedStream, streamURL: URL) -> String {
        ExternalPlayerCallback.filename(title: request.seriesName ?? request.title, year: request.year, season: request.season,
                                        episode: request.episode, fileExtension: fileExtension(for: item, streamURL: streamURL))
    }

    /// The file's extension, taken from the first of these that is a video extension: the addon's filename hint, the stream's path, the container
    /// Blusion knows. nil when none of them says (the name then defaults to mp4).
    private func fileExtension(for item: RankedStream, streamURL: URL) -> String? {
        let hint = item.stream.behaviorHints.filename
        if let hint, let ext = Self.videoExtension(of: (hint as NSString).pathExtension) { return ext }
        if let ext = Self.videoExtension(of: streamURL.pathExtension) { return ext }
        return (item.container ?? ContainerSniffer.container(url: streamURL, filename: hint))?.fileExtension
    }

    private static func videoExtension(of ext: String) -> String? {
        let lowered = ext.lowercased()
        return videoExtensions.contains(lowered) ? lowered : nil
    }

    /// The stream's own subtitle in the user's language, when the settings name one and the stream offers it.
    private func subtitleURL(for item: RankedStream) -> URL? {
        guard let language = settings.subtitleLanguage, !language.isEmpty else { return nil }
        return item.stream.subtitles.first { LanguageCodes.matches($0.lang, preferred: language) }?.url
    }
}
