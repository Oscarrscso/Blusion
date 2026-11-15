import Foundation
import Observation
import Persistence
import PlayerKit
import StremioKit

extension PlayerViewModel {
    // MARK: Subtitles

    /// The media's own tracks, without files loaded into the engine (those are listed with the other files).
    var embeddedSubtitleTracks: [MediaTrack] { state.embeddedSubtitleTracks.filter { !$0.isExternal } }

    var subtitleStyle: SubtitleStyle { coordinator?.subtitleStyle ?? settings.player.subtitleStyle }

    /// The line to draw, or nil. Reads the engine clock through `state.position`, so it updates with playback.
    var cueText: String? {
        guard case .external = subtitleChoice, case .overlay(let text, _, _) = drawing else { return nil }
        return text?.text(at: state.position, offset: subtitleOffset)
    }

    /// The styled cues to draw now (empty when the engine draws them, or for picture subtitles).
    var activeCues: [SubtitleCue] {
        guard case .external = subtitleChoice, case .overlay(let text, _, _) = drawing else { return [] }
        return text?.cues(at: state.position, offset: subtitleOffset) ?? []
    }

    /// The picture subtitle (PGS) to draw now.
    var activeBitmapCue: BitmapSubtitleCue? {
        guard case .external = subtitleChoice, case .overlay(_, let bitmap, _) = drawing else { return nil }
        return bitmap?.cue(at: state.position, offset: subtitleOffset)
    }

    /// Whether timing can be shifted for the current choice: the overlay always can; the engine only for what it draws.
    var canShiftSubtitles: Bool {
        switch subtitleChoice {
        case .off: return false
        case .embedded: return capabilities.contains(.subtitleDelay)
        case .external: return !engineDrawsFile || capabilities.contains(.subtitleDelay)
        }
    }

    func selectSubtitle(_ choice: SubtitleChoice) async {
        pendingResume?.subtitleTrack = nil
        pendingResume?.subtitlesOff = false
        userChoseSubtitle = true
        automaticChoice = nil
        showControls()
        await apply(choice)
    }

    /// The Mac's C key: the next subtitle choice in the menu's order, Off first, then the embedded tracks, then the external ones, and
    /// back to Off. A load still in flight counts as the choice, so presses during it keep advancing.
    func cycleSubtitles() async {
        let choices: [SubtitleChoice] = [.off]
            + embeddedSubtitleTracks.map { SubtitleChoice.embedded($0.id) }
            + subtitleOptions.map { SubtitleChoice.external($0.id) }
        guard choices.count > 1 else { return }
        let current = choices.firstIndex(of: pendingChoice ?? subtitleChoice) ?? 0
        await selectSubtitle(choices[(current + 1) % choices.count])
    }

    func adjustSubtitleOffset(by delta: TimeInterval) {
        let limit = Self.maximumSubtitleOffset
        subtitleOffset = min(limit, max(-limit, ((subtitleOffset + delta) * 10).rounded() / 10))
        syncEngineSubtitleDelay()
        showControls()
    }

    func resetSubtitleOffset() {
        subtitleOffset = 0
        syncEngineSubtitleDelay()
    }

    func setSubtitleStyle(_ style: SubtitleStyle) {
        coordinator?.setSubtitleStyle(style)
        savePreferences { $0.subtitleStyle = style }
    }

    /// A subtitle file the user opened (SRT, VTT, ASS/SSA, SUP). It joins the list and is selected.
    func loadSubtitleFile(at url: URL) async {
        guard let copy = copyIn(url) else {
            subtitleActivity = .failed("Couldn't open that file.")
            return
        }
        let name = url.lastPathComponent
        let language = Self.language(inFileName: name)
        let option = SubtitleOption(id: "local|\(copy.path)", language: language ?? "und",
                                    title: "\(language.map(LanguageCodes.displayName) ?? url.deletingPathExtension().lastPathComponent) · File",
                                    url: copy, source: .local, format: .detect(copy, name: name))
        subtitleOptions = SubtitleService.merge(subtitleOptions, [option])
        await selectSubtitle(.external(option.id))
    }

    /// The engine's own delay follows the offset while the engine draws the current choice, and is zero otherwise.
    private func syncEngineSubtitleDelay() {
        guard capabilities.contains(.subtitleDelay) else { return }
        let engineDraws: Bool = switch subtitleChoice {
        case .embedded: true
        case .external: engineDrawsFile
        case .off: false
        }
        let delay = engineDraws ? subtitleOffset : 0
        if coordinator?.subtitleDelay != delay { coordinator?.setSubtitleDelay(delay) }
    }

    func apply(_ choice: SubtitleChoice) async {
        // An option the list does not have is ignored, before it can supersede a load in flight.
        if case .external(let id) = choice, !subtitleOptions.contains(where: { $0.id == id }) { return }
        // Each choice supersedes a subtitle load still in flight, so a load that returns late is dropped instead of overwriting the choice made since.
        subtitleGeneration += 1
        let generation = subtitleGeneration
        subtitleActivity = .idle
        switch choice {
        case .off:
            clearOverlay()
            coordinator?.selectEmbeddedSubtitleTrack(id: nil)
            subtitleChoice = .off
            syncEngineSubtitleDelay()
        case .embedded(let id):
            clearOverlay()
            coordinator?.selectEmbeddedSubtitleTrack(id: id)
            subtitleChoice = .embedded(id)
            syncEngineSubtitleDelay()
        case .external(let id):
            guard let option = subtitleOptions.first(where: { $0.id == id }) else { return }
            // An engine that draws subtitle files draws them all: full ASS styling, pictures, its HDR brightness and its timing.
            if capabilities.contains(.engineSubtitles) {
                drawing = .engine(optionID: id)
                coordinator?.addEngineSubtitle(engineSubtitle(for: option))
                subtitleChoice = .external(id)
                syncEngineSubtitleDelay()
                return
            }
            // What the overlay draws now stays up until the new file has loaded.
            subtitleActivity = .loading(choice)
            coordinator?.selectEmbeddedSubtitleTrack(id: nil)
            do {
                let loaded = try await loadOverlay(option)
                guard generation == subtitleGeneration else { return }
                subtitleActivity = .idle
                guard !Task.isCancelled else { return }
                // The engine that started while this loaded draws files itself: it gets the file instead.
                if capabilities.contains(.engineSubtitles) {
                    await apply(choice)
                    return
                }
                drawing = .overlay(text: loaded.text, bitmap: loaded.bitmap,
                                   simplified: loaded.simplified && plan.retriesInFallbackEngine)
                subtitleChoice = .external(id)
                syncEngineSubtitleDelay()
            } catch {
                guard generation == subtitleGeneration else { return }
                clearOverlay()
                if case SubtitleError.bitmap = error, plan.retriesInFallbackEngine {
                    // VobSub has no decoder in the app: the advanced player draws it, from where the stream is now.
                    subtitleActivity = .switchingPlayer
                    subtitleChoice = .external(id)
                    drawing = .engine(optionID: id)
                    await coordinator?.reopenInFallbackEngine()
                    guard generation == subtitleGeneration else { return }   // another choice was made during the reopen
                    if capabilities.contains(.engineSubtitles) {
                        coordinator?.addEngineSubtitle(engineSubtitle(for: option))
                        subtitleActivity = .idle
                    } else {
                        drawing = .none
                        subtitleActivity = .failed("Couldn't show these subtitles.")
                        subtitleChoice = .off
                    }
                    return
                }
                subtitleActivity = .failed((error as? SubtitleError).map(Self.message) ?? "Couldn't load these subtitles.")
                subtitleChoice = .off
            }
        }
    }

    private func clearOverlay() {
        drawing = .none
    }

    private static func message(_ error: SubtitleError) -> String {
        switch error {
        case .bitmap: "These are picture subtitles (VobSub), which need the advanced player."
        case .tooLarge: "This subtitle file is too large."
        case .empty, .unreadable: "Couldn't load these subtitles."
        }
    }

    /// Text files parse to cues; PGS files decode to pictures.
    private func loadOverlay(_ option: SubtitleOption) async throws -> (text: SubtitleTimeline?, bitmap: BitmapSubtitleTimeline?, simplified: Bool) {
        let data = try await services.subtitles.data(for: option, maxBytes: option.format == .pgs ? PGSDecoder.maximumBytes : SubtitleParser.largestAcceptedBytes)
        if option.format == .pgs || data.starts(with: Array("PG".utf8)) {
            let cues = try await Task.detached(priority: .userInitiated) { try PGSDecoder.decode(data) }.value
            guard !cues.isEmpty else { throw SubtitleError.empty }
            return (nil, BitmapSubtitleTimeline(cues: cues), false)
        }
        let parsed = try SubtitleParser.parse(data: data)
        return (SubtitleTimeline(cues: parsed.cues), nil, SubtitleParser.needsEngineRendering(parsed.cues, format: parsed.format))
    }

    /// Engines match their tracks by title, so two files with the same title get distinct ones.
    private func engineSubtitle(for option: SubtitleOption) -> ExternalSubtitle {
        let same = subtitleOptions.filter { $0.title == option.title }
        let title = same.count > 1 ? "\(option.title) (\((same.firstIndex(of: option) ?? 0) + 1))" : option.title
        let language = option.language == "und" ? nil : LanguageCodes.iso639_1(option.language) ?? option.language
        return ExternalSubtitle(url: option.url, title: title, language: language, headers: [:])
    }

    func startSubtitles() {
        guard let first = plan.candidates.first else { return }
        lookedUpCandidates.insert(first.id)
        pendingSubtitleLookups += 1
        subtitleTask = Task { [weak self] in
            guard let self else { return }
            defer { pendingSubtitleLookups -= 1; restoreChoicesIfPossible() }
            subtitleOptions = SubtitleService.merge(subtitleOptions, SubtitleService.options(from: first.subtitles))
            restoreChoicesIfPossible()
            await applyDefaultSubtitle()
            if !plan.isOffline { await collect(services.subtitles.fetch(for: first, request: plan.request)) }
        }
    }

    private func collect(_ responses: AsyncStream<AddonResponse<[SubtitleItem]>>) async {
        for await response in responses {
            if let items = response.value {
                subtitleOptions = SubtitleService.merge(subtitleOptions, SubtitleService.options(from: items, addon: response.addon.name))
            }
            restoreChoicesIfPossible()
            await applyDefaultSubtitle()
        }
    }

    /// Another stream took over: its own subtitles (bundled, and those addons match to its hash and file name) join the list.
    /// The list keeps what it had, so a choice already made stays available.
    func lookUpSubtitles(for candidate: PlaybackCandidate) {
        guard !plan.isOffline, lookedUpCandidates.insert(candidate.id).inserted else { return }
        pendingSubtitleLookups += 1
        lookupTasks.append(Task { [weak self] in
            guard let self else { return }
            defer { pendingSubtitleLookups -= 1; restoreChoicesIfPossible() }
            subtitleOptions = SubtitleService.merge(subtitleOptions, SubtitleService.options(from: candidate.subtitles))
            await applyDefaultSubtitle()
            await collect(services.subtitles.fetch(for: candidate, request: plan.request))
        })
    }

    /// Move external subtitles between engine-drawn and overlay-drawn paths as capabilities change across engines.
    func engineChanged() {
        // A replacement engine ends the old picture's hold, including an automatic fallback or reconnect.
        endHeldSpeed()
        guard case .external(let id) = subtitleChoice else { return }
        let engineDraws = capabilities.contains(.engineSubtitles)
        if engineDrawsFile != engineDraws {
            let choice = subtitleChoice
            Task { [weak self] in await self?.apply(choice) }
        } else if engineDraws {
            drawing = .engine(optionID: id)
        }
    }

    func tracksChanged() {
        // These snapshots change only with the track list, so a paused menu is
        // not re-laid out on every playback-clock tick.
        let audioRows = PlayerTrackPresentation.embedded(state.audioTracks, audio: true)
        let subtitleRows = PlayerTrackPresentation.embedded(embeddedSubtitleTracks)
        if audioTrackRows != audioRows { audioTrackRows = audioRows }
        if embeddedSubtitleRows != subtitleRows { embeddedSubtitleRows = subtitleRows }
        if audioTrackSelectionID != state.selectedAudioTrackID { audioTrackSelectionID = state.selectedAudioTrackID }
        restoreChoicesIfPossible()
        if !userChoseAudio, let track = SubtitleDefaults.audioTrack(in: state.audioTracks, selected: state.selectedAudioTrackID,
                                                                    language: settings.player.audioLanguage ?? PlayerPreferences.defaultAudioLanguage) {
            coordinator?.selectAudioTrack(id: track.id)
        }
        Task { [weak self] in await self?.applyDefaultSubtitle() }
    }

    /// Picks subtitles from the Settings preferences until the listener chooses: language, Always or Forced only, SDH. An embedded track
    /// that turns up after a file was picked replaces it. A load already in flight for the pick is not repeated.
    private func applyDefaultSubtitle() async {
        guard !userChoseSubtitle, pendingChoice == nil || pendingChoice == automaticChoice else { return }
        let audioLanguage = state.audioTracks.first { $0.id == state.selectedAudioTrackID }?.language
        guard let pick = SubtitleDefaults.choice(embedded: embeddedSubtitleTracks, external: subtitleOptions, language: settings.subtitleLanguage,
                                                 audioLanguage: audioLanguage, mode: settings.player.subtitleMode, prefersSDH: settings.player.prefersSDH),
              pick != automaticChoice, subtitleChoice == automaticChoice ?? .off else { return }
        // A file picked first gives way only to an embedded track.
        if automaticChoice != nil, case .external = pick { return }
        automaticChoice = pick
        await apply(pick)
    }

    /// Waits for the subtitle lookup (used by tests).
    func waitForSubtitles() async {
        await subtitleTask?.value
        for task in lookupTasks { await task.value }
    }

    // MARK: OpenSubtitles

    var hasOpenSubtitlesKey: Bool { !(settings.openSubtitlesAPIKey ?? "").isEmpty }

    /// Searches OpenSubtitles.com for this title (and episode) in the preferred subtitle language, matched to the stream's hash when known.
    func searchOpenSubtitles() async {
        guard !plan.isOffline else { return }
        guard let client = openSubtitles() else {
            openSubtitlesStatus = "Add an OpenSubtitles API key in Settings to search."
            return
        }
        guard let imdb = plan.request.id.split(separator: ":").first.map(String.init), imdb.hasPrefix("tt") else {
            openSubtitlesStatus = "OpenSubtitles needs an IMDb title, which this one doesn't have."
            return
        }
        isSearchingOpenSubtitles = true
        openSubtitlesStatus = nil
        defer { isSearchingOpenSubtitles = false }
        let languages = [settings.subtitleLanguage, settings.player.audioLanguage, "eng"].compactMap { $0 }.compactMap(LanguageCodes.iso639_1)
        let hash = await currentMovieHash()
        do {
            openSubtitlesResults = try await client.search(imdbID: imdb, season: plan.request.season, episode: plan.request.episode,
                                                           languages: Array(Set(languages)), movieHash: hash)
            if openSubtitlesResults.isEmpty { openSubtitlesStatus = "No subtitles found on OpenSubtitles." }
        } catch {
            openSubtitlesResults = []
            openSubtitlesStatus = Self.message(error as? OpenSubtitlesError)
        }
    }

    /// Downloads one result; it joins the list and is selected.
    /// True when the downloaded file is the subtitle now shown.
    @discardableResult
    func downloadOpenSubtitle(_ result: OpenSubtitlesResult) async -> Bool {
        guard !plan.isOffline else { return false }
        guard let client = openSubtitles() else { return false }
        openSubtitlesStatus = "Downloading…"
        do {
            let download = try await client.download(result)
            let language = LanguageCodes.normalise(result.language)
            let flags = [result.isForeignPartsOnly ? "Forced" : nil, result.isHearingImpaired ? "SDH" : nil, result.matchesHash ? "Matched" : nil]
            let title = ([LanguageCodes.displayName(language)] + flags.compactMap { $0 } + ["OpenSubtitles"]).joined(separator: " · ")
            let option = SubtitleOption(id: "opensubtitles|\(result.fileID)", language: language, title: title, url: download.url,
                                        source: .openSubtitles, format: .detect(download.url, name: download.fileName ?? result.fileName),
                                        isForced: result.isForeignPartsOnly, isHearingImpaired: result.isHearingImpaired)
            subtitleOptions = SubtitleService.merge(subtitleOptions, [option])
            openSubtitlesStatus = download.remaining.map { "\($0) downloads left today." }
            await selectSubtitle(.external(option.id))
            if case .external(let id) = subtitleChoice { return id == option.id }
            return false
        } catch {
            openSubtitlesStatus = Self.message(error as? OpenSubtitlesError)
            return false
        }
    }

    private func openSubtitles() -> OpenSubtitlesClient? {
        guard let key = settings.openSubtitlesAPIKey, !key.isEmpty else { return nil }
        return OpenSubtitlesClient(client: services.client, credentials: OpenSubtitlesCredentials(
            apiKey: key, username: settings.openSubtitlesUsername, password: settings.openSubtitlesPassword))
    }

    private func currentMovieHash() async -> String? {
        guard let candidate = coordinator?.current ?? plan.candidates.first else { return nil }
        if let hash = candidate.videoHash { return hash }
        guard let url = candidate.url, !url.isFileURL else { return nil }
        return await MovieHash.compute(url: url, headers: candidate.headers, size: candidate.videoSize, client: services.client)
    }

    private static func message(_ error: OpenSubtitlesError?) -> String {
        switch error {
        case .missingAPIKey: "Add an OpenSubtitles API key in Settings."
        case .unauthorized: "OpenSubtitles didn't accept the API key or login in Settings."
        case .quotaExceeded(let reset): "The OpenSubtitles download limit is used up\(reset.map { " until \($0)" } ?? " for today")."
        case .notFound: "OpenSubtitles doesn't have that file any more."
        case .server, .decoding, nil: "OpenSubtitles couldn't be reached. Try again."
        }
    }
}
