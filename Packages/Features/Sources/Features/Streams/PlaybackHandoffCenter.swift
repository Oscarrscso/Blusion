import Foundation
import PlayerKit
import StremioKit

/// Turns a player app's callback into watch progress: where the viewer stopped becomes their resume point, and a stop near the end
/// of a title with a known length marks it watched.
public struct PlaybackHandoffCenter: Sendable {
    private let services: AppServices
    private let now: @Sendable () -> Date

    public init(services: AppServices, now: @escaping @Sendable () -> Date = { Date() }) {
        self.services = services
        self.now = now
    }

    /// Handles one of Blusion's callback URLs. Returns false for any other URL (the caller may then try other handlers).
    @discardableResult
    public func handle(_ url: URL) async -> Bool {
        guard let callback = ExternalPlayerCallback.parse(url) else { return false }
        // Taken in every case, so one callback is recorded at most once. A token Blusion does not know was never its hand-off.
        guard let handoff = await services.handoffs.take(id: callback.token) else { return true }
        guard case .finished(let stoppedAt) = callback.result, let position = stoppedAt, position >= 0 else { return true }
        await record(position: position, for: handoff.request)
        return true
    }

    private func record(position: TimeInterval, for request: StreamRequest) async {
        let previous = await services.progress.progress(for: request.identity)
        // A title whose runtime the addon did not give keeps the length an earlier session measured, so its watched mark still works.
        let duration = request.expectedDuration ?? previous?.duration ?? 0
        let reachedEnd = duration > 0 && position / duration >= ProgressPolicy.default.watchedThreshold
        let record = WatchProgress(id: request.identity, type: request.type, contentID: request.id, title: request.title, poster: request.poster,
                                   position: position, duration: duration, isWatched: reachedEnd || previous?.isWatched == true,
                                   updatedAt: now(), season: request.season, episode: request.episode)
        await services.progress.save(record)
    }
}
