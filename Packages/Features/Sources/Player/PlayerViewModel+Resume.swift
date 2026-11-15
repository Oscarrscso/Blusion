import Foundation
import Observation
import Persistence
import PlayerKit
import StremioKit

extension PlayerViewModel {
    // MARK: The previous session

    /// Takes over a saved session: where it stopped, whether it was paused, its track choices and its picture. Called before the
    /// player is readied, so the start itself resumes there; called on a running player, it applies at once.
    func resumePlayback(from snapshot: PlaybackSnapshot) {
        guard persistsSession, !isPrivateSession() else { return }
        pendingResume = snapshot
        resumeWasPaused = snapshot.wasPaused
        guard hasStartedPlayback else { return }
        applyRestoredPicture(snapshot)
        if snapshot.position > 0 { Task { await seek(to: snapshot.position) } }
        if snapshot.wasPaused { coordinator?.pause() }
        restoreChoicesIfPossible()
    }

    /// The session's own state, for the store to keep while it plays: no link and no header, only where and how it is.
    var saveState: PlaybackSaveState {
        PlaybackSaveState(position: position, duration: state.duration, isPaused: !wantsPlayback,
                          audioTrack: state.audioTracks.first { $0.id == state.selectedAudioTrackID }.map(SnapshotTrack.init),
                          subtitleTrack: subtitleSnapshotTrack, subtitlesOff: subtitleChoice == .off,
                          layout: videoLayout, processing: processing)
    }

    /// Keeps the saved session current with where the viewer is, so a kill loses at most `snapshotRefreshInterval` of playback.
    /// A pause, a seek or the app leaving the front refreshes it at once (`force`). A prepared player has not started for the viewer
    /// yet, and a closed one has no session.
    func recordSessionSnapshot(force: Bool = false) async {
        guard persistsSession, !isPrivateSession(), lifecycle == .live, hasStartedPlayback else { return }
        let current = now()
        if !force, let last = lastSnapshotRefresh, current.timeIntervalSince(last) < Self.snapshotRefreshInterval { return }
        lastSnapshotRefresh = current
        guard var snapshot = await snapshotStore.load(), snapshot.request.identity == plan.request.identity else { return }
        guard !isPrivateSession(), lifecycle == .live, !Task.isCancelled else { return }
        snapshot.apply(saveState)
        try? await snapshotStore.save(snapshot)
    }

    /// Saves the session a hand-over starts: the next episode's own stream, so killing the app during it walks back into that episode.
    /// The picture is the one Settings keeps: Zoom Mode, with the next title's own Aspect Ratio.
    func saveSessionSnapshot(for next: PlaybackPlan, candidateIndex: Int = 0) async {
        guard persistsSession, !isPrivateSession() else { return }
        guard next.candidates.indices.contains(candidateIndex) else { return }
        let candidate = next.candidates[candidateIndex]
        guard !next.isOffline, let identity = PlaybackStreamIdentity(candidate: candidate) else { return }
        let layout = VideoLayout(zoomMode: settings.player.zoomMode,
                                 aspectRatio: settings.player.aspectRatios[AspectRatioChoice.titleKey(for: next.request)] ?? .original)
        let snapshot = PlaybackSnapshot(request: next.request, stream: identity, addonName: candidate.addonName,
                                        position: 0, duration: nil, wasPaused: false,
                                        layout: layout, processing: settings.player.processing)
        try? await snapshotStore.save(snapshot)
        lastSnapshotRefresh = now()
    }

    /// Closing a private session must not erase the last session recorded outside Ghost mode.
    func clearSessionSnapshot() async {
        guard persistsSession, !isPrivateSession() else { return }
        await snapshotStore.clear()
    }

    private var subtitleSnapshotTrack: SnapshotTrack? {
        switch subtitleChoice {
        case .off:
            return nil
        case .embedded(let id):
            return embeddedSubtitleTracks.first { $0.id == id }.map(SnapshotTrack.init)
        case .external(let id):
            guard let option = subtitleOptions.first(where: { $0.id == id }) else { return nil }
            return SnapshotTrack(title: option.title, language: option.language, isForced: option.isForced,
                                 isHearingImpaired: option.isHearingImpaired, isExternal: true)
        }
    }

    private func applyRestoredPicture(_ snapshot: PlaybackSnapshot) {
        // Settings and the controls remain authoritative, just as when restoring before playback starts.
        // Old snapshots can contain an accumulated zoom or a crop chosen by the former aspect-ratio implementation.
        applyPicture()
        if let processing = snapshot.processing { coordinator?.setProcessing(processing) }
    }

    /// Applies the restored audio and subtitle choices once their lists exist. A list that is still empty keeps the choice waiting,
    /// so a track that arrives a moment later is still taken over; a fresh choice made meanwhile wins.
    func restoreChoicesIfPossible() {
        guard var restored = pendingResume, hasStartedPlayback else { return }
        var applied = true
        if let pick = restored.audioTrack {
            if let track = Self.track(pick, in: state.audioTracks) {
                userChoseAudio = true
                audioTrackSelectionID = track.id
                coordinator?.selectAudioTrack(id: track.id)
                restored.audioTrack = nil
            } else if state.audioTracks.isEmpty {
                applied = false
            }
        }
        if restored.subtitlesOff {
            userChoseSubtitle = true
            automaticChoice = nil
            Task { [weak self] in await self?.apply(.off) }
            restored.subtitlesOff = false
        } else if let pick = restored.subtitleTrack {
            if !pick.isExternal, let track = Self.track(pick, in: embeddedSubtitleTracks) {
                userChoseSubtitle = true
                automaticChoice = nil
                Task { [weak self] in await self?.apply(.embedded(track.id)) }
                restored.subtitleTrack = nil
            } else if let option = Self.option(pick, in: subtitleOptions) {
                userChoseSubtitle = true
                automaticChoice = nil
                Task { [weak self] in await self?.apply(.external(option.id)) }
                restored.subtitleTrack = nil
            } else if (pick.isExternal && pendingSubtitleLookups > 0) || (embeddedSubtitleTracks.isEmpty && subtitleOptions.isEmpty) {
                applied = false
            }
        }
        pendingResume = applied ? nil : restored
    }

    /// A saved track against a fresh engine's own: its name and language, then its language and flags, then its name alone. A fresh
    /// engine numbers its tracks its own way, so its ids never match.
    private static func track(_ pick: SnapshotTrack, in tracks: [MediaTrack]) -> MediaTrack? {
        tracks.first { $0.title == pick.title && $0.language == pick.language && $0.isForced == pick.isForced
                && $0.isHearingImpaired == pick.isHearingImpaired }
            ?? tracks.first { !pick.title.isEmpty && $0.title == pick.title && $0.language == pick.language }
            ?? tracks.first { $0.language != nil && $0.language == pick.language && $0.isForced == pick.isForced
                && $0.isHearingImpaired == pick.isHearingImpaired }
            ?? tracks.first { !pick.title.isEmpty && $0.title == pick.title }
    }

    private static func option(_ pick: SnapshotTrack, in options: [SubtitleOption]) -> SubtitleOption? {
        options.first { $0.title == pick.title && $0.language == pick.language && $0.isForced == pick.isForced
                && $0.isHearingImpaired == pick.isHearingImpaired }
            ?? options.first { !pick.title.isEmpty && $0.title == pick.title && $0.language == pick.language }
            ?? options.first { $0.language == pick.language && $0.isForced == pick.isForced && $0.isHearingImpaired == pick.isHearingImpaired }
    }
}
