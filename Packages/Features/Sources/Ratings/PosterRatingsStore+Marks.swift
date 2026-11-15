import Foundation
import Observation
import StremioKit

extension PosterRatingsStore {
    /// The film's best disc as the device last heard it from Best Blurays, for the Highest Quality mark in Play's hold menu. Nil for a
    /// series, and for a film the site has not been asked about or names no disc for. Asks no one.
    func knownBestDisc(for item: MetaPreview) async -> BestDiscFormat? {
        guard item.type == "movie", LetterboxdRatings.isIMDbID(item.id) else { return nil }
        if let disc = entries[item.identity]?.bestDisc { return disc }
        return await marks.record(for: item.id)?.disc
    }

    /// The streamer the title's poster mark shows, from memory or the marks kept on this device, so the title page can name it at once
    /// rather than after its own lookups.
    func knownStreamer(for item: MetaPreview) async -> TMDbWatchService? {
        guard LetterboxdRatings.isIMDbID(item.id) else { return nil }
        if let streamer = entries[item.identity]?.streamer { return streamer }
        return await marks.record(for: item.id)?.streamer
    }

    /// Keeps the disc the stream picker found, so the film's posters and title page show it without asking the site again.
    func rememberBestEdition(_ result: BestBlurayResult, imdbID: String) async {
        await marks.storeDisc(Self.disc(in: result), for: imdbID, checkedAt: now())
        await showMarks(imdbID: imdbID)
    }

    /// Keeps the streamer the title page found, so its posters show it without asking TMDb again. Only for the region marks are kept for.
    func rememberWatch(_ watch: TMDbTitleWatch, imdbID: String, region: String) async {
        guard region == marks.region else { return }
        await marks.storeStreamer(watch.streaming.first, for: imdbID, checkedAt: now())
        await showMarks(imdbID: imdbID)
    }

    private func showMarks(imdbID: String) async {
        guard let record = await marks.record(for: imdbID) else { return }
        for entry in entries.values where entry.id.hasSuffix("/\(imdbID)") { applyMark(record, to: entry) }
    }

    private static func disc(in result: BestBlurayResult) -> BestDiscFormat? {
        if case .edition(let edition) = result { return edition.discFormat }
        return nil
    }

    /// Reads the title's marks from the mark store and shows them. Returns when this lookup's answer goes stale; nil when never asked.
    func readMark(_ lookup: Lookup) async -> Date? {
        let id = lookup.item.id
        var record = await marks.record(for: id)
        // Disc answers kept in the ratings cache before marks had a store of their own are carried over once, not asked for again.
        if lookup.provider == .bestBlurays, record?.discCheckedAt == nil, let old = await cache.value(for: lookup.cacheKey) {
            await marks.storeDisc(old.bestDisc, for: id, checkedAt: old.fetchedAt)
            record = await marks.record(for: id)
        }
        guard !Task.isCancelled, let record else { return nil }
        if let entry = entries[lookup.item.identity] { applyMark(record, to: entry) }
        switch lookup.provider {
        case .bestBlurays:
            guard let checked = record.discCheckedAt else { return nil }
            if record.disc == nil, showsBestDisc || lookup.includeReviews, tmdb != nil {
                enqueue(lookup.item, provider: .streaming, includeReviews: lookup.includeReviews)
            }
            // A film's best disc changes rarely: a named disc is kept a month, and "none named" a week.
            return checked.addingTimeInterval(record.disc != nil ? 30 * 86_400 : 7 * 86_400)
        default:
            // Streaming catalogues change monthly: a service is kept a week, and "none" three days.
            return record.streamerCheckedAt?.addingTimeInterval(record.streamer != nil ? 7 * 86_400 : 3 * 86_400)
        }
    }

    /// Asks bestblurays.com or TMDb for the title's mark, keeps the answer, and shows it. Returns when the answer goes stale.
    func lookUpMark(_ lookup: Lookup) async throws -> Date? {
        let item = lookup.item
        switch lookup.provider {
        case .bestBlurays:
            guard let bestBlurays else { return nil }
            let year = item.releaseInfo?.firstMatch(of: /[0-9]{4}/).map { String($0.output) }
            let result = try await bestBlurays.bestEdition(imdbID: item.id, title: item.name, year: year)
            guard !Task.isCancelled else { return nil }
            await marks.storeDisc(Self.disc(in: result), for: item.id, checkedAt: now())
        case .streaming:
            guard let tmdb else { return nil }
            let watch = try await tmdb.titleWatch(imdbID: item.id, type: item.type, region: marks.region)
            guard !Task.isCancelled else { return nil }
            await marks.storeStreamer(watch.streaming.first, for: item.id, checkedAt: now())
        case .letterboxd, .tmdb, .omdb, .myAnimeList:
            return nil
        }
        return await readMark(lookup)
    }

    /// Each write redraws the posters that show this title, so only changes are written.
    private func applyMark(_ record: TitleMarkRecord, to entry: TitleRatings) {
        if record.discCheckedAt != nil {
            entry.discChecked = true
            if entry.bestDisc != record.disc { entry.bestDisc = record.disc }
        }
        if record.streamerCheckedAt != nil, entry.streamer != record.streamer { entry.streamer = record.streamer }
    }
}
