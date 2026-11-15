import Foundation
import Observation
import StremioKit

extension PosterRatingsStore {
    /// The hero artwork already fetched for this title this session, read without waiting. Nil until a lookup for it has succeeded.
    public func cachedHeroArtwork(for item: MetaPreview) -> TMDbArtwork? {
        heroArtworkByID[item.id]
    }

    /// Original-resolution portrait and landscape artwork for the featured carousel, independent of poster rating visibility.
    /// Successful answers are kept for the session, so a title coming back into the spotlight is ready at once. A title asked for again
    /// while its lookup runs waits for that lookup rather than making another request.
    public func heroArtwork(for item: MetaPreview) async -> TMDbArtwork? {
        if let known = heroArtworkByID[item.id] { return known }
        guard let tmdb, !isClearing else { return nil }
        if let running = heroArtworkTasks[item.id] { return await running.value }
        let task = Task<TMDbArtwork?, Never> { try? await tmdb.artwork(imdbID: item.id, type: item.type) }
        heroArtworkTasks[item.id] = task
        let artwork = await task.value
        // Forgotten while it ran (the data was cleared): the answer is handed back but not kept.
        guard heroArtworkTasks[item.id] == task else { return artwork }
        heroArtworkTasks[item.id] = nil
        if let artwork { heroArtworkByID[item.id] = artwork }
        return artwork
    }

    /// The age rating already fetched for this title this session, read without waiting. Nil until a lookup for it has answered, and
    /// when TMDb has none.
    public func cachedCertification(for item: MetaPreview, region: String = "US") -> String? {
        certificationByID["\(item.identity)|\(region.uppercased())"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The title's age rating in one country. Answers are kept for the session, "none" included, so a title coming
    /// back into the spotlight asks nothing. A lookup that failed is not kept, and a title asked for again while its lookup runs waits
    /// for that lookup.
    public func certification(for item: MetaPreview, region: String = "US") async -> String? {
        let key = "\(item.identity)|\(region.uppercased())"
        if certificationByID[key] != nil { return cachedCertification(for: item, region: region) }
        guard let tmdb, !isClearing else { return nil }
        if let running = certificationTasks[key] { return try? await running.value }
        let task = Task<String?, Error> { try await tmdb.certification(imdbID: item.id, type: item.type, region: region) }
        certificationTasks[key] = task
        let answer: String?
        do {
            answer = try await task.value
        } catch {
            if certificationTasks[key] == task { certificationTasks[key] = nil }
            return nil
        }
        // Forgotten while it ran (the data was cleared): the answer is handed back but not kept.
        guard certificationTasks[key] == task else { return answer }
        certificationTasks[key] = nil
        certificationByID[key] = answer ?? ""
        return answer
    }

    /// Whether hero artwork can be asked for at all: a TMDb client is configured. Without one, prewarming is skipped entirely.
    public var canLookUpHeroArtwork: Bool { tmdb != nil && !isClearing }

    /// Looks up a title's hero artwork before its page opens, for a card that has been on screen for a moment. Only the TMDb answer is asked
    /// for, never a picture. At most `maxPrewarmLookups` run at once, so a fast scroll does not burst TMDb, and a lookup still waiting for its
    /// turn is dropped when its card scrolls away. Does nothing without a TMDb client, or when the title's artwork is already known.
    public func prewarmHeroArtwork(for item: MetaPreview) async {
        guard tmdb != nil, !isClearing, heroArtworkByID[item.id] == nil else { return }
        let waiter = UUID()
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if prewarmRunning < Self.maxPrewarmLookups {
                    prewarmRunning += 1
                    continuation.resume(returning: true)
                } else {
                    prewarmWaiting.append((waiter, continuation))
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelPrewarmWait(waiter) }
        }
        guard granted else { return }
        defer { releasePrewarmSlot() }
        guard !Task.isCancelled else { return }
        _ = await heroArtwork(for: item)
    }

    /// Passes the slot to the next prewarm waiting for one, or frees it when none is waiting.
    private func releasePrewarmSlot() {
        if prewarmWaiting.isEmpty { prewarmRunning -= 1 } else { prewarmWaiting.removeFirst().continuation.resume(returning: true) }
    }

    /// Drops a prewarm that is still waiting for its turn. It is resumed without a slot.
    private func cancelPrewarmWait(_ waiter: UUID) {
        guard let index = prewarmWaiting.firstIndex(where: { $0.id == waiter }) else { return }
        prewarmWaiting.remove(at: index).continuation.resume(returning: false)
    }
}
