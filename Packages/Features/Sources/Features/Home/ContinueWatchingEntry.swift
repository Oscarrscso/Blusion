import Foundation
import PlayerKit
import StremioKit

public struct ContinueWatchingEntry: Identifiable, Equatable, Sendable {
    public let request: StreamRequest
    public let fraction: Double
    public let updatedAt: Date
    public var id: String { request.identity }

    public var subtitle: String {
        guard let season = request.season, let episode = request.episode else { return "" }
        return "S\(season) E\(episode)"
    }

    static func merge(local: [WatchProgress], remote: [TraktPlaybackItem]) -> [ContinueWatchingEntry] {
        var entries: [String: ContinueWatchingEntry] = [:]
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt > $1.updatedAt ? $0 : $1 })
        for item in remote {
            // A newer local completion or pause wins over an older Trakt pause.
            if let saved = localByID[item.id], saved.updatedAt >= item.pausedAt { continue }
            entries[item.id] = ContinueWatchingEntry(request: item.request, fraction: item.progress / 100, updatedAt: item.pausedAt)
        }
        for item in local where !item.isWatched && ProgressRecorder.resumePosition(for: item) > 0 {
            if let remote = entries[item.id], remote.updatedAt > item.updatedAt { continue }
            var request = LibraryViewModel.request(for: item)
            request.expectedDuration = item.duration > 0 ? item.duration : nil
            entries[item.id] = ContinueWatchingEntry(request: request, fraction: item.fraction, updatedAt: item.updatedAt)
        }
        var series = Set<String>()
        return entries.values.sorted { $0.updatedAt > $1.updatedAt }.filter { entry in
            guard entry.request.type == "series" else { return true }
            return series.insert(ContentID(entry.request.id).baseID).inserted
        }
    }
}
