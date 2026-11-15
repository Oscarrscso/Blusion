#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI
import UIKit

extension StreamPickerView {
    // MARK: choosing

    /// Starts `item`. `automatically` is set for the start made when the streams open (see `finishAutomaticStart`). Tapping the stream
    /// Blusion is readying again calls that off; tapping another stream moves to it.
    func select(_ item: RankedStream, automatically: Bool = false) {
        if streamPreparation.isReadying {
            let isSame = activePreparationItemID == item.id
            cancelPreparation()
            if isSame, !automatically { return }
        }
        guard !isOpeningPlayer else { return }
        isOpeningPlayer = true
        clearFailedPreparation()
        hasSelectedManually = true
        autoPickTask?.cancel()
        autoPickTask = Task {
            let choice: StreamPickerViewModel.Choice?
            if automatically, let preferredAutomaticPlayer {
                choice = await model.handoffChoice(for: item, player: preferredAutomaticPlayer)
            } else {
                choice = await model.choose(item)
            }
            guard let choice else {
                isOpeningPlayer = false
                if automatically { finishAutomaticStart(started: false) }
                return
            }
            guard !Task.isCancelled else { isOpeningPlayer = false; return }
            let started = await present(choice, for: item)
            // Called off while the film was readied: whoever called it off has already reset the picker.
            guard !Task.isCancelled else { return }
            if automatically { finishAutomaticStart(started: started) }
        }
    }

    /// Calls off foreground preparation: its play button and Auto Pick stop spinning. The player keeps loading in the background, so playing
    /// that stream after all is still quick.
    func cancelPreparation() {
        autoPickTask?.cancel()
        if streamPreparation.isReadying { streamPreparation = .idle }
        preparingViaAutoPick = false
        isOpeningPlayer = false
        if awaitsAutomaticStart { finishAutomaticStart(started: false) }
    }

    /// A failed readying's message goes once another start begins.
    private func clearFailedPreparation() {
        if case .failed = streamPreparation { streamPreparation = .idle }
    }

    /// Follow automatic candidate changes, without showing any foreground indicators for a background preload.
    var activePreparationItemID: RankedStream.ID? {
        guard case .readying(let itemID, _) = streamPreparation else { return nil }
        return prepared?.player.coordinator?.current?.id ?? itemID
    }

    var readyingBeganAt: Date? {
        if case .readying(_, let beganAt) = streamPreparation { return beganAt }
        return nil
    }

    /// Readies `next` (the plan for `item`) and opens the player once the film is ready to play: its first frame is in, held paused, and
    /// it plays the moment the screen is up. The stream's play button spins meanwhile. A player already readied for this stream (the
    /// first stream's background load) is used as it is. False when it was called off.
    private func openWhenReady(_ next: PlaybackPlan, for item: RankedStream) async -> Bool {
        guard !Task.isCancelled else { return false }
        let player = preparedPlayer(for: next, item: item)
        // Walking back into the previous session (the app was left or killed, and this is its stream): the player takes its
        // position, track choices and picture over, before it is readied to play.
        if let snapshot = model.resumeHandoff(for: item), let resuming = player as? any PlaybackSnapshotResuming {
            resuming.resumePlayback(from: snapshot)
        }
        streamPreparation = .readying(itemID: item.id, beganAt: readyingBeganAt ?? Date())
        await player.prepare()
        guard !Task.isCancelled, prepared?.player === player else { return false }
        let finishedItemID = activePreparationItemID ?? item.id
        let beganAt = readyingBeganAt
        streamPreparation = .idle
        preparingViaAutoPick = false
        isOpeningPlayer = false
        if !isHeadless, let progress = player.preparationProgress, progress.failure != nil {
            let endedAt = Date()
            streamPreparation = .failed(.init(itemID: finishedItemID, progress: progress, beganAt: beganAt ?? endedAt, endedAt: endedAt))
            discardPrepared()
            return false
        }
        // The screen takes the player over as soon as the existing preparation completes.
        prepared = nil
        presentedPlayer = player
        plan = player.plan
        return true
    }

    /// The player readied for `item`: the one already loading for it, or a new one, which replaces a player readied for another stream.
    private func preparedPlayer(for next: PlaybackPlan, item: RankedStream) -> PlayerViewModel {
        if let prepared, prepared.itemID == item.id { return prepared.player }
        discardPrepared()
        let player = PlayerContent.makeModel(plan: next, services: services)
        // The stream's opening bytes start downloading at once, where its engine can take them.
        PlayerPreload.begin(next, services: services)
        prepared = PreparedPlayer(player: player, itemID: item.id)
        return player
    }

    /// Closes a readied player nobody is going to watch.
    func discardPrepared() {
        guard let player = prepared?.player else { return }
        backgroundLoadTask?.cancel()
        prepared = nil
        Task { await player.close() }
    }

    /// Starts loading the first stream listed in the background, once it is there, in case it is the one played: muted, held paused
    /// on its first frame, with no progress saved. Only a stream Blusion plays, and not when a stream is starting by itself anyway.
    func startBackgroundLoad() {
        guard OptimisationSettings.readiesFirstStream(), !hasStartedBackgroundLoad, !hasSelectedManually, !awaitsAutomaticStart,
              !isHeadless, prepared == nil, plan == nil, scenePhase == .active, let first = model.automaticStartCandidate, first.route.isPlayable else { return }
        hasStartedBackgroundLoad = true
        backgroundLoadTask = Task {
            guard case .play(let next)? = await model.choose(first), prepared == nil, plan == nil, !hasSelectedManually,
                  !awaitsAutomaticStart, !Task.isCancelled, scenePhase == .active else { return }
            await preparedPlayer(for: next, item: first).prepare()
        }
    }

    /// Finish the automatic attempt. The saved Auto Pick preference keeps the selector hidden even if playback fails.
    func finishAutomaticStart(started: Bool) {
        if !started { awaitsAutomaticStart = false }
        onAutomaticStart?(started)
    }

    /// Manual Auto Pick uses the same ranked, preference-aware player route as Play.
    func autoPick() {
        guard !isOpeningPlayer else { return }
        isOpeningPlayer = true
        clearFailedPreparation()
        hasSelectedManually = true
        autoPickTask?.cancel()
        autoPickTask = Task {
            guard let choice = await model.autoPickBest(), !Task.isCancelled, let item = model.autoPickedStream else {
                isOpeningPlayer = false
                return
            }
            if case .play = choice { preparingViaAutoPick = true }
            _ = await present(choice, for: item)
        }
    }

    func openIn(_ player: ExternalPlayer, _ item: RankedStream) {
        guard !isOpeningPlayer else { return }
        isOpeningPlayer = true
        hasSelectedManually = true
        autoPickTask?.cancel()
        autoPickTask = Task {
            guard let choice = await model.handoffChoice(for: item, player: player), !Task.isCancelled else {
                isOpeningPlayer = false
                return
            }
            await present(choice, for: item)
        }
    }

    func playInBlusion(_ item: RankedStream) {
        if streamPreparation.isReadying { cancelPreparation() }
        guard !isOpeningPlayer else { return }
        hasSelectedManually = true
        autoPickTask?.cancel()
        guard let choice = model.inAppChoice(for: item) else { return }
        isOpeningPlayer = true
        autoPickTask = Task { await present(choice, for: item) }
    }

    /// Starts `choice`. True when a stream started here or went to another app; false when an alert asks the viewer to pick again, or
    /// when readying the film was called off. A stream Blusion plays opens only once it is ready to play (see `openWhenReady`).
    @discardableResult
    func present(_ choice: StreamPickerViewModel.Choice, for item: RankedStream) async -> Bool {
        guard !Task.isCancelled else { return false }
        // In ghost mode nothing is handed to another player except Infuse, which the viewer allows: Infuse keeps its own history and its own
        // Trakt. Anything else that would leave Blusion plays here when Blusion can play it, and otherwise does not start.
        if GhostMode.isOn {
            switch choice {
            case .openInPlayer(.infuse, _):
                break
            case .openInPlayer, .openExternal:
                if case .play(let next)? = model.inAppChoice(for: item) {
                    return await openWhenReady(next, for: item)
                }
                ghostBlocked = true
                isOpeningPlayer = false
                return false
            case .play, .unsupported:
                break
            }
        }
        switch choice {
        case .play(let next):
            isOpeningPlayer = true
            // The session this start becomes: where the app is left or killed from now until it is closed.
            await model.saveResumeSnapshot(for: item)
            guard !Task.isCancelled else { return false }
            return await openWhenReady(next, for: item)
        case .openExternal(let url):
            isOpeningPlayer = false
            openURL(url)
        case .openInPlayer(let player, let link):
            isOpeningPlayer = true
            openURL(link) { accepted in
                if !accepted {
                    isOpeningPlayer = false
                    Task { await model.discardHandoff(for: link) }
                    missing = MissingPlayer(player: player, item: item)
                } else {
                    onOpenedInPlayer?(player)
                }
            }
        case .unsupported:
            isOpeningPlayer = false
            unsupported = item   // the alert offers the next playable stream, or another player
            return false
        }
        return true
    }

    /// Bookmark saves return to Blusion on confirmation. Downloads stay in Infuse unless
    /// Infuse reports an error; neither action claims the video has finished downloading.
    func save(_ item: RankedStream, to player: ExternalPlayer, download: Bool = false) {
        guard !isOpeningPlayer, download || !savedStreams.contains(item.id) else { return }
        isOpeningPlayer = true
        autoPickTask?.cancel()
        autoPickTask = Task {
            guard let link = await model.saveLink(for: item, download: download),
                  !Task.isCancelled else { isOpeningPlayer = false; return }
            if download {
                openURL(link) { accepted in
                    isOpeningPlayer = false
                    if !accepted {
                        Task { await model.discardHandoff(for: link) }
                        missing = MissingPlayer(player: player, item: item)
                    }
                }
                return
            }
            guard let token = StreamPickerViewModel.handoffToken(in: link) else { isOpeningPlayer = false; return }
            pendingSaves[token] = item.id
            openURL(link) { accepted in
                if !accepted {
                    isOpeningPlayer = false
                    pendingSaves[token] = nil
                    Task { await model.discardHandoff(for: link) }
                    missing = MissingPlayer(player: player, item: item)
                }
            }
        }
    }

    // MARK: players and alerts

    /// Whether the player app is on this device. Its scheme is listed in LSApplicationQueriesSchemes, which is what lets the system answer.
    /// Only asked once per opening of the picker, never while a row or a menu is drawn.
    func isInstalled(_ player: ExternalPlayer) -> Bool {
        guard let url = URL(string: "\(player.scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func unsupportedMessage(for item: RankedStream) -> String {
        if let player = model.alternativePlayers(for: item).first {
            return "Blusion can't play this container or audio yet. \(player.displayName) can."
        }
        return "Blusion can't play this container or audio yet. Pick another stream."
    }

    var isShowingUnsupported: Binding<Bool> {
        Binding(get: { unsupported != nil }, set: { if !$0 { unsupported = nil } })
    }

    var isShowingMissing: Binding<Bool> {
        Binding(get: { missing != nil }, set: { if !$0 { missing = nil } })
    }
}
#endif
