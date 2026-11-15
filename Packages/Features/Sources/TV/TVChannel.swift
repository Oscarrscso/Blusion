import Foundation
import Observation
import PlayerKit
import StremioKit

struct TVChannel: Codable, Equatable, Identifiable, Sendable {
    enum Order: String, Codable, CaseIterable, Identifiable, Sendable {
        case shuffle, episodes
        var id: Self { self }
        var title: String { self == .episodes ? "In Order" : "Random" }
    }

    var id = UUID()
    var name = ""
    var shows: [MetaPreview] = []
    var order = Order.shuffle
    /// When the channel went on air. Its schedule runs from that day's midnight, so it is the same every time it is opened.
    var onAir: Date?
}

/// A channel's schedule, as a broadcaster's: it runs on the clock from the day the channel went on air, whatever has been watched.
/// Random channels pick a show for each slot at random (never three in a row) and deal its episodes like a shuffled deck, so none
/// comes round again until the show has aired them all. In Order channels take the shows in turn, each airing its episodes in
/// sequence. A slot is the show's runtime rounded up to five minutes, so programmes start on the clock's five-minute marks.
struct TVLineup: Sendable {
    struct Programme: Sendable, Identifiable {
        let start: Date
        /// Time on air, to the next programme's start.
        let slot: TimeInterval
        let request: StreamRequest
        let show: MetaPreview
        let episodeTitle: String
        /// The episode's own length.
        let duration: TimeInterval
        var id: Date { start }
        var end: Date { start.addingTimeInterval(slot) }
        var episodeLabel: String {
            guard let season = request.season, let episode = request.episode else { return "" }
            return "S\(season) E\(episode)"
        }
        var artwork: URL? { show.background ?? MetahubArtwork.background(imdbID: show.id) ?? show.poster }
        var logo: URL? { show.logo ?? MetahubArtwork.logo(imdbID: show.id) }

        /// How far into the episode the broadcast is at `date`.
        func elapsed(at date: Date) -> TimeInterval { min(duration, max(0, date.timeIntervalSince(start))) }
        func fraction(at date: Date) -> Double { duration > 0 ? elapsed(at: date) / duration : 0 }
    }

    /// From the programme on air when the lineup was built, for the next two days.
    let programmes: [Programme]

    /// The programmes from the one on air at `date`. Empty once the lineup has run out.
    func schedule(at date: Date) -> ArraySlice<Programme> {
        guard let index = programmes.firstIndex(where: { $0.end > date }) else { return [] }
        return programmes[index...]
    }

    init(channel: TVChannel, details: [MetaDetail], now: Date = Date(), horizon: TimeInterval = 48 * 3600, limit: Int = 400) {
        let shows = details.compactMap { Show($0, now: now) }
        guard !shows.isEmpty else {
            programmes = []
            return
        }
        let present = now.timeIntervalSinceReferenceDate
        let end = present + horizon
        var time = Calendar.current.startOfDay(for: min(channel.onAir ?? now, now)).timeIntervalSinceReferenceDate
        var random = Generator(seed: Self.hash(channel.id.uuidString))
        var aired = [Int](repeating: 0, count: shows.count)
        var decks: [Int: (cycle: Int, order: [Int])] = [:]
        var turn = 0, last = -1, run = 0
        var built: [Programme] = []
        // Every slot since the channel went on air is played out, so the schedule is the same each time it is worked out.
        while time < end, built.count < limit {
            let pick: Int
            if channel.order == .episodes || shows.count == 1 {
                pick = turn % shows.count
            } else if run >= 2 {
                // Two in a row is a double bill; a third would not be.
                let other = random.below(shows.count - 1)
                pick = other >= last ? other + 1 : other
            } else {
                pick = random.below(shows.count)
            }
            turn += 1
            run = pick == last ? run + 1 : 1
            last = pick
            let show = shows[pick]
            if time + show.slot > present {
                let count = show.episodes.count
                let episode: Int
                if channel.order == .episodes {
                    episode = aired[pick] % count
                } else {
                    let cycle = aired[pick] / count
                    if decks[pick]?.cycle != cycle {
                        let seed = Self.hash("\(channel.id.uuidString)/\(show.detail.preview.identity)/\(cycle)")
                        decks[pick] = (cycle, Self.deck(count, seed: seed))
                    }
                    episode = decks[pick]?.order[aired[pick] % count] ?? 0
                }
                built.append(show.programme(episode, start: Date(timeIntervalSinceReferenceDate: time)))
            }
            aired[pick] += 1
            time += show.slot
        }
        programmes = built
    }

    private struct Show {
        let detail: MetaDetail
        let episodes: [Video]
        let duration: TimeInterval
        let slot: TimeInterval

        init?(_ detail: MetaDetail, now: Date) {
            var seen = Set<String>()
            episodes = detail.episodesCountingAsWatched(by: now).filter { seen.insert($0.id).inserted }
            guard !episodes.isEmpty else { return nil }
            self.detail = detail
            duration = min(4 * 3600, StreamRequest.duration(fromRuntime: detail.preview.runtime) ?? 30 * 60)
            slot = (duration / 300).rounded(.up) * 300
        }

        func programme(_ index: Int, start: Date) -> Programme {
            let video = episodes[index]
            // The schedule supplies successors, so no episode looks up the next one in its show.
            var request = StreamRequest(movie: detail.preview)
            request.type = detail.type.isEmpty ? "series" : detail.type
            request.id = video.id
            request.title = "\(detail.name) · \(video.title)"
            request.season = video.season
            request.episode = video.episode
            request.seriesName = detail.name
            return Programme(start: start, slot: slot, request: request, show: detail.preview, episodeTitle: video.title,
                             duration: duration)
        }
    }

    /// SplitMix64: the same numbers from the same seed on every device and launch, unlike the system generator.
    private struct Generator {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(max(1, bound))) }
    }

    private static func deck(_ count: Int, seed: UInt64) -> [Int] {
        var order = Array(0..<count)
        var random = Generator(seed: seed)
        for index in stride(from: count - 1, to: 0, by: -1) {
            order.swapAt(index, random.below(index + 1))
        }
        return order
    }

    /// FNV-1a: the same number for the same text on every launch, unlike `Hasher`.
    static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}

/// Every channel, shared by Home's Blusion TV widget and the Blusion TV page, so a change on one shows on the other.
@MainActor
@Observable
final class BlusionTVModel {
    struct Tuning: Equatable {
        let channel: UUID
        let start: Date
    }

    private struct AutoSet: Codable {
        let day: Date
        let channels: [TVChannel]
    }

    /// The channels you made.
    private(set) var channels: [TVChannel]
    /// The channels Blusion makes from the shows you like, made again each day.
    private(set) var autoChannels: [TVChannel] = []
    private(set) var isMakingAutoChannels = false
    var allChannels: [TVChannel] { autoChannels + channels }
    private(set) var lineups: [UUID: TVLineup] = [:]
    private(set) var loading = Set<UUID>()
    private(set) var issues: [UUID: String] = [:]
    private(set) var tuning: Tuning?
    private(set) var startedEpisodes = Set<String>()
    private let services: AppServices
    private let defaults: UserDefaults
    private var details: [String: (detail: MetaDetail, loaded: Date)] = [:]
    private var revisions: [UUID: UUID] = [:]
    private var tuneTask: Task<Void, Never>?
    private var tuneID = UUID()
    private static let key = "blusionTV.channels.v1"
    private static let autoKey = "blusionTV.auto.v1"
    private var autoDay: Date?
    /// How long a show's episode list is reused before Home or the guide asks for it again.
    private static let detailLifetime: TimeInterval = 6 * 3600
    /// Joining this close to a programme's end starts the next one instead.
    private static let joinMargin: TimeInterval = 120
    private static var instance: BlusionTVModel?

    static func shared(services: AppServices) -> BlusionTVModel {
        if let instance { return instance }
        let model = BlusionTVModel(services: services)
        instance = model
        return model
    }

    init(services: AppServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        var saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([TVChannel].self, from: $0) } ?? []
        // Channels made when lineups followed watch progress go on air now, at random.
        let migrating = saved.contains { $0.onAir == nil }
        for index in saved.indices where saved[index].onAir == nil {
            saved[index].onAir = Date()
            saved[index].order = .shuffle
        }
        channels = saved
        if migrating { persist() }
        if let auto = defaults.data(forKey: Self.autoKey).flatMap({ try? JSONDecoder().decode(AutoSet.self, from: $0) }) {
            autoChannels = auto.channels
            autoDay = auto.day
        }
    }

    func isAuto(_ channel: TVChannel) -> Bool { autoChannels.contains { $0.id == channel.id } }

    func save(_ draft: TVChannel) {
        var channel = draft
        channel.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        channel.shows = channel.shows.filter { $0.type == "series" && seen.insert($0.identity).inserted }
        guard !channel.name.isEmpty, !channel.shows.isEmpty else { return }
        if channel.onAir == nil { channel.onAir = Date() }
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[index] = channel
        } else {
            channels.append(channel)
        }
        lineups[channel.id] = nil
        issues[channel.id] = nil
        persist()
        Task { await load(channel) }
    }

    func delete(_ channel: TVChannel) {
        if tuning?.channel == channel.id { cancelTuning() }
        revisions[channel.id] = UUID()
        channels.removeAll { $0.id == channel.id }
        lineups[channel.id] = nil
        issues[channel.id] = nil
        loading.remove(channel.id)
        persist()
    }

    /// Loads every channel's lineup from now, making Blusion's channels first on a new day. `force` asks again for episode lists
    /// already loaded and makes Blusion's channels again.
    func refresh(force: Bool = false) async {
        await readStartedEpisodes()
        if force { details = [:] }
        await makeAutoChannels(force: force)
        for channel in allChannels {
            guard !Task.isCancelled else { return }
            await load(channel)
        }
    }

    /// After playback: re-reads which episodes have been started, for spoiler-free titles, and runs each lineup on from now.
    func refreshProgress() async {
        await readStartedEpisodes()
        for channel in allChannels where !loading.contains(channel.id) {
            if let built = lineup(for: channel, from: channel.shows.compactMap { details[$0.identity]?.detail }) {
                lineups[channel.id] = built
            }
        }
    }

    func load(_ channel: TVChannel) async {
        guard allChannels.contains(channel) else { return }
        let revision = UUID()
        revisions[channel.id] = revision
        loading.insert(channel.id)
        defer { if revisions[channel.id] == revision { loading.remove(channel.id) } }
        var loaded: [MetaDetail] = []
        var unavailable: [String] = []
        for show in channel.shows {
            guard !Task.isCancelled, revisions[channel.id] == revision else { return }
            if let saved = details[show.identity], Date().timeIntervalSince(saved.loaded) < Self.detailLifetime {
                loaded.append(saved.detail)
                continue
            }
            let result = await services.browse.detail(for: show)
            guard !Task.isCancelled, revisions[channel.id] == revision else { return }
            if result.isFallback || result.detail.videos.isEmpty {
                // An earlier list is better than none when the addon does not answer this time.
                if let saved = details[show.identity] { loaded.append(saved.detail) } else { unavailable.append(show.name) }
                continue
            }
            details[show.identity] = (result.detail, Date())
            loaded.append(result.detail)
        }
        guard !Task.isCancelled, revisions[channel.id] == revision, allChannels.contains(channel) else { return }
        if let built = lineup(for: channel, from: loaded) {
            lineups[channel.id] = built
            issues[channel.id] = nil
        } else {
            lineups[channel.id] = nil
            issues[channel.id] = unavailable.isEmpty ? "No aired episodes" : "Couldn't load \(unavailable.joined(separator: ", "))"
        }
    }

    /// Tunes in, in Blusion's player, then plays on through the schedule, each programme from its beginning. With no `start`, joins
    /// what is on now part-way through, as a broadcast would, or from its beginning with `fromStart`; the next programme takes over
    /// when it is all but over or has no playable stream. With a `start`, plays that programme from its beginning.
    func tune(_ channel: TVChannel, at start: Date? = nil, fromStart: Bool = false,
              play: @escaping @MainActor (PlaybackPlan) -> Void, fail: @escaping @MainActor (String) -> Void) {
        cancelTuning()
        guard let programmes = lineups[channel.id]?.programmes else { return }
        let live = start == nil
        let date = Date()
        let match = if let start { programmes.firstIndex(where: { $0.start == start }) } else { programmes.firstIndex(where: { $0.end > date }) }
        guard let found = match else { return }
        // Joining in the credits starts the next programme instead.
        let ending = live && !fromStart && programmes[found].duration - programmes[found].elapsed(at: date) < Self.joinMargin
        let first = ending && programmes.indices.contains(found + 1) ? found + 1 : found
        let id = UUID()
        tuneID = id
        tuning = Tuning(channel: channel.id, start: programmes[first].start)
        tuneTask = Task { [weak self] in
            guard let self else { return }
            defer { if tuneID == id { tuning = nil } }
            // Live, a programme with no playable stream gives way to the next, so the channel never goes dark.
            for index in first..<min(programmes.count, first + (live ? 3 : 1)) {
                let programme = programmes[index]
                tuning = Tuning(channel: channel.id, start: programme.start)
                let picker = StreamPickerViewModel(request: programme.request, services: services)
                await picker.loadForAutomaticSelection(stopsForWaitTarget: false)
                picker.cancelLoading()
                guard !Task.isCancelled, tuneID == id else { return }
                guard let plan = picker.bestInAppPlan else { continue }
                // Where the broadcast has got to by the time the stream is ready, short of the credits.
                let position = live && !fromStart ? min(programme.elapsed(at: Date()), max(0, programme.duration - Self.joinMargin)) : 0
                let queue = PlaybackQueue(title: channel.name, requests: programmes[index...].map(\.request), startsFromBeginning: true)
                play(plan.inQueue(queue, startingAt: position))
                return
            }
            let programme = programmes[first]
            fail(live ? "No playable stream was found for what is on \(channel.name)."
                      : "No playable stream was found for \(programme.show.name) \(programme.episodeLabel).")
        }
    }

    func cancelTuning() {
        tuneTask?.cancel()
        tuneTask = nil
        tuneID = UUID()
        tuning = nil
    }

    /// For You, genre channels and New to You, from the shows saved and watched most and TMDb's recommendations for them. Kept for the
    /// day, so their schedules hold until tomorrow.
    private func makeAutoChannels(force: Bool) async {
        let today = Calendar.current.startOfDay(for: Date())
        guard force || autoDay != today, !isMakingAutoChannels else { return }
        isMakingAutoChannels = true
        defer { isMakingAutoChannels = false }
        let taste = TVTaste(progress: await services.progress.all(), library: await services.library.all())
        let picks = await recommendations(for: taste)
        await loadDetails(taste.favourites + picks)
        guard !Task.isCancelled else { return }
        var genres: [String: [String]] = [:]
        for show in taste.favourites + picks {
            let known = details[show.identity]?.detail.preview.genres ?? []
            genres[show.identity] = known.isEmpty ? show.genres : known
        }
        // A show its addons do not know would leave a channel short.
        let made = TVTaste.channels(favourites: taste.favourites.filter { details[$0.identity] != nil },
                                    picks: picks.filter { details[$0.identity] != nil }, genres: genres, onAir: today)
        // Nothing liked yet, or nothing loaded: yesterday's channels stay, and the next refresh tries again.
        guard !made.isEmpty else { return }
        for old in autoChannels where !made.contains(old) { lineups[old.id] = nil }
        autoChannels = made
        autoDay = today
        if let data = try? JSONEncoder().encode(AutoSet(day: today, channels: made)) { defaults.set(data, forKey: Self.autoKey) }
    }

    /// Shows TMDb recommends for the favourites that have not been saved or watched, those recommended for most favourites first.
    /// Empty without a TMDb token.
    private func recommendations(for taste: TVTaste) async -> [MetaPreview] {
        guard let token = await services.settings.load().tmdbReadToken, !token.isEmpty else { return [] }
        let tmdb = TMDbRatings(client: services.client, readAccessToken: token)
        let seeds = Array(taste.favourites.filter { LetterboxdRatings.isIMDbID($0.id) }.prefix(5))
        let lists = await withTaskGroup(of: [TMDbRelatedTitle].self) { group in
            for seed in seeds {
                group.addTask { (try? await tmdb.relatedTitles(imdbID: seed.id, type: "series")) ?? [] }
            }
            var lists: [[TMDbRelatedTitle]] = []
            for await list in group { lists.append(list) }
            return lists
        }
        var scores: [Int: Double] = [:]
        var titles: [Int: TMDbRelatedTitle] = [:]
        for list in lists {
            for (rank, title) in list.prefix(10).enumerated() where title.mediaType == "tv" {
                scores[title.tmdbID, default: 0] += 1 + 1 / Double(rank + 1)
                titles[title.tmdbID] = title
            }
        }
        let ranked = scores.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(16).compactMap { titles[$0.key] }
        let found = await withTaskGroup(of: (Int, MetaPreview?).self) { group in
            for (rank, title) in ranked.enumerated() {
                group.addTask {
                    guard let imdb = try? await tmdb.imdbID(tmdbID: title.tmdbID, mediaType: "tv") else { return (rank, nil) }
                    return (rank, MetaPreview(id: imdb, type: "series", name: title.title, poster: title.poster, background: title.backdrop,
                                              description: title.overview, releaseInfo: title.releaseDate.map { String($0.prefix(4)) }))
                }
            }
            var found: [(Int, MetaPreview)] = []
            for await (rank, preview) in group { if let preview { found.append((rank, preview)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return found.filter { !taste.known.contains($0.identity) }
    }

    /// Fetches the episode lists not already held, all at once.
    private func loadDetails(_ shows: [MetaPreview]) async {
        let now = Date()
        let missing = shows.filter { details[$0.identity].map { now.timeIntervalSince($0.loaded) >= Self.detailLifetime } ?? true }
        let browse = services.browse
        let loaded = await withTaskGroup(of: (String, MetaDetail?).self) { group in
            for show in missing {
                group.addTask {
                    let result = await browse.detail(for: show)
                    return (show.identity, result.isFallback || result.detail.videos.isEmpty ? nil : result.detail)
                }
            }
            var loaded: [(String, MetaDetail)] = []
            for await (identity, detail) in group { if let detail { loaded.append((identity, detail)) } }
            return loaded
        }
        for (identity, detail) in loaded { details[identity] = (detail, now) }
    }

    private func readStartedEpisodes() async {
        startedEpisodes = Set(await services.progress.all().filter { $0.isWatched || $0.position > 0 }.map(\.id))
    }

    private func lineup(for channel: TVChannel, from details: [MetaDetail]) -> TVLineup? {
        guard !details.isEmpty else { return nil }
        let lineup = TVLineup(channel: channel, details: details)
        return lineup.programmes.isEmpty ? nil : lineup
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(channels) { defaults.set(data, forKey: Self.key) }
    }
}
