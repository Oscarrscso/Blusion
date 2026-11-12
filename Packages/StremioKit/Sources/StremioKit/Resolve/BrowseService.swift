import Foundation

/// A catalog of one installed addon, shown as a Board row or a Discover source.
public struct CatalogSource: Sendable, Equatable, Hashable, Identifiable {
    public let addon: AddonSummary
    public let baseURL: URL
    public let catalog: CatalogDescriptor

    public init(addon: AddonSummary, baseURL: URL, catalog: CatalogDescriptor) {
        self.addon = addon
        self.baseURL = baseURL
        self.catalog = catalog
    }

    public var id: String { "\(addon.id.uuidString)/\(catalog.key)" }
    public var type: String { catalog.type }
    public var title: String { catalog.name }
}

/// Browsing across the user's addons: catalog rows, paged catalogs with genre filter, multi-addon search, Detail with fallback.
public final class BrowseService: Sendable {
    public let registry: AddonRegistry
    public let client: AddonClient
    private let metadata = BrowseMetadataCache()
    private let genreMemory: GenreMemory
    /// Content types the UI shows. `nil`, the default, shows every type an addon offers (movie, series, anime, `tv`, custom types
    /// such as `all`); a set keeps only those types.
    public let visibleTypes: Set<String>?

    /// `genreFile` keeps each title's genres across launches; without it they last for this run.
    public init(registry: AddonRegistry, client: AddonClient, visibleTypes: Set<String>? = nil, genreFile: URL? = nil) {
        self.registry = registry
        self.client = client
        self.visibleTypes = visibleTypes
        genreMemory = GenreMemory(file: genreFile)
    }

    /// `nil` means every type is visible.
    static func isVisible(_ type: String, in visible: Set<String>?) -> Bool { visible?.contains(type) ?? true }

    /// Browsable catalogs of enabled addons, in the user's addon order, then the addon's own catalog order.
    public func catalogSources(type: String? = nil) async -> [CatalogSource] {
        let visible = visibleTypes
        return await registry.addons(providing: .catalog).flatMap { addon in
            addon.manifest.browsableCatalogs(type: type).filter { BrowseService.isVisible($0.type, in: visible) }.map {
                CatalogSource(addon: addon.summary, baseURL: addon.baseURL, catalog: $0)
            }
        }
    }

    /// The enabled addons `search` asks, in the user's order: those with a searchable catalog of a visible type.
    /// Empty means search has nothing to ask (for example, only stream addons are installed).
    public func searchableAddons() async -> [AddonSummary] {
        await searchableInstalled().map(\.summary)
    }

    /// One page. `skip` is the number of items already loaded (the protocol's pagination).
    public func page(_ source: CatalogSource, genre: String? = nil, skip: Int = 0) async throws -> [MetaPreview] {
        var extras: [ExtraParam] = []
        if let genre, !genre.isEmpty, source.catalog.extra(named: "genre") != nil { extras.append(ExtraParam("genre", genre)) }
        if skip > 0, source.catalog.supportsSkip { extras.append(ExtraParam("skip", String(skip))) }
        return try await client.catalog(base: source.baseURL, type: source.catalog.type, id: source.catalog.id, extras: extras)
    }

    /// With incremental updates, each addon publishes its merged results as individual catalogs finish.
    /// The default retains one final answer per addon for callers that collect the stream.
    public func search(_ query: String, incremental: Bool = false) async -> AsyncStream<AddonResponse<[MetaPreview]>> {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return AsyncStream { $0.finish() } }
        let addons = await searchableInstalled()
        let client = self.client
        let visible = visibleTypes
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { addonsGroup in
                    for addon in addons {
                        addonsGroup.addTask {
                            let catalogs = Self.searchCatalogs(of: addon.manifest, visible: visible)
                            await withTaskGroup(of: (Int, Result<[MetaPreview], AddonError>).self) { group in
                                for (index, catalog) in catalogs.enumerated() {
                                    group.addTask {
                                        do {
                                            let items = try await client.catalog(base: addon.baseURL, type: catalog.type, id: catalog.id,
                                                                                 extras: [ExtraParam("search", term)])
                                            return (index, .success(items))
                                        } catch { return (index, .failure(AddonError.from(error))) }
                                    }
                                }
                                var pages: [Int: [MetaPreview]] = [:]
                                var firstError: AddonError?
                                var remaining = catalogs.count
                                for await (index, outcome) in group {
                                    guard !Task.isCancelled else { return }
                                    remaining -= 1
                                    switch outcome {
                                    case .success(let items): pages[index] = items
                                    case .failure(let error): firstError = firstError ?? error
                                    }
                                    if !pages.isEmpty, incremental || remaining == 0 {
                                        var seen = Set<String>()
                                        let merged = pages.keys.sorted().flatMap { pages[$0] ?? [] }.filter { seen.insert($0.identity).inserted }
                                        continuation.yield(AddonResponse(addon: addon.summary, result: .success(merged)))
                                    } else if remaining == 0, let firstError {
                                        continuation.yield(AddonResponse(addon: addon.summary, result: .failure(firstError)))
                                    }
                                }
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The addons `search` asks, shared with `searchableAddons()` so the two can never disagree.
    private func searchableInstalled() async -> [InstalledAddon] {
        let visible = visibleTypes
        return await registry.addons(providing: .catalog).filter { !BrowseService.searchCatalogs(of: $0.manifest, visible: visible).isEmpty }
    }

    /// The catalogs `search` asks one addon: its searchable catalogs of a visible type.
    static func searchCatalogs(of manifest: Manifest, visible: Set<String>?) -> [CatalogDescriptor] {
        manifest.searchableCatalogs.filter { isVisible($0.type, in: visible) }
    }

    /// Full metadata for Detail. Asks every addon that supports `meta` for this id at once, and takes the answer of the first addon in the
    /// user's order that has one, as Stremio does: an addon further down that answers sooner waits until those above it have answered or
    /// failed, so an addon that answers for any id cannot replace Cinemeta's details with its own. When none answers, Detail is built from
    /// the catalog preview (`isFallback`).
    public func detail(for preview: MetaPreview) async -> (detail: MetaDetail, isFallback: Bool) {
        let type = preview.type.isEmpty ? "movie" : preview.type
        let addons = await registry.addons(for: .meta, type: type, id: preview.id)
        let result = await detail(for: preview, type: type, addons: addons)
        return (result.detail, result.isFallback)
    }

    /// `isFinal` is false when no addon answered and one of them could not be reached, so the fallback may not be what the page shows.
    private func detail(for preview: MetaPreview, type: String,
                        addons: [InstalledAddon]) async -> (detail: MetaDetail, isFallback: Bool, isFinal: Bool) {
        let client = self.client
        let key = BrowseMetadataCache.Key(type: type, id: preview.id, sources: addons.map(\.baseURL))
        let answer = await metadata.value(for: key) {
            var answers: [Int: MetaDetail] = [:]
            var settled = Set<Int>()
            var isFinal = true
            for await response in FanOut.run(over: addons, operation: { try await client.meta(base: $0.baseURL, type: type, id: preview.id) }) {
                guard !Task.isCancelled else { return BrowseMetadataCache.Answer(isFinal: false) }
                guard let index = addons.firstIndex(where: { $0.summary == response.addon }) else { continue }
                settled.insert(index)
                if let detail = response.value {
                    answers[index] = detail
                } else if let error = response.error, Self.isTransient(error) {
                    isFinal = false
                }
                if let detail = Self.firstAnswerInOrder(answers, settled: settled, count: addons.count) {
                    return BrowseMetadataCache.Answer(detail: detail)
                }
            }
            return BrowseMetadataCache.Answer(isFinal: isFinal)
        }
        var detail = answer.detail?.filling(from: preview) ?? .fallback(from: preview)
        detail.preview.genres = MediaGenres.normalised(detail.preview.genres)
        // What the title page lists is what every genre filter matches.
        if answer.detail != nil {
            await genreMemory.store(detail.preview.genres, for: Self.genreKey(type: type, id: preview.id, sources: key.sources))
        }
        // The page leads with the genre its card led with: a title opened from a genre's list shows that genre first.
        detail.preview.genres = MediaGenres.leading(Array(preview.genres.prefix(1)), in: detail.preview.genres)
        return (detail, answer.detail == nil, answer.isFinal)
    }

    /// A failure that says nothing about whether the addon has the title.
    private static func isTransient(_ error: AddonError) -> Bool {
        switch error {
        case .offline, .cancelled: return true
        default: return error.isRetryable
        }
    }

    /// A title's genres as its page lists them, led by the genre the item leads with: remembered ones at once, otherwise from the same
    /// metadata as Detail. Empty when the page could not be read just now: such a title sits out a genre filter rather than pass on
    /// its catalog's word.
    public func genres(for item: MetaPreview) async -> [String] {
        let type = item.type.isEmpty ? "movie" : item.type
        let addons = await registry.addons(for: .meta, type: type, id: item.id)
        if let known = await genreMemory.genres(for: Self.genreKey(type: type, id: item.id, sources: addons.map(\.baseURL))) {
            return MediaGenres.leading(Array(item.genres.prefix(1)), in: known)
        }
        let result = await detail(for: item, type: type, addons: addons)
        return result.isFinal ? result.detail.preview.genres : []
    }

    /// The titles with the genres their pages list, a few lookups at a time. Remembered and in-flight lookups are shared.
    public func resolvingGenres(in items: [MetaPreview]) async -> [MetaPreview] {
        var result = items
        await withTaskGroup(of: (Int, [String]).self) { group in
            var next = 0
            while next < min(10, items.count) {
                let (index, item) = (next, items[next])
                group.addTask { (index, await self.genres(for: item)) }
                next += 1
            }
            for await (index, genres) in group {
                result[index].genres = genres
                guard next < items.count, !Task.isCancelled else { continue }
                let (position, item) = (next, items[next])
                group.addTask { (position, await self.genres(for: item)) }
                next += 1
            }
        }
        return result
    }

    /// Names a title and the addons that answer for it, in order, so a change of addons asks again. The addons are a hash, never their URLs.
    static func genreKey(type: String, id: String, sources: [URL]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in sources.map(\.absoluteString).joined(separator: "\n").utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return "\(type)/\(id)@\(String(hash, radix: 36))"
    }

    /// The answer of the first addon, in order, that has one, once every addon before it has answered or failed. Nil while an addon before
    /// the first answer has not settled yet, and when none has an answer.
    static func firstAnswerInOrder<Answer>(_ answers: [Int: Answer], settled: Set<Int>, count: Int) -> Answer? {
        for index in 0..<count {
            guard settled.contains(index) else { return nil }
            if let answer = answers[index] { return answer }
        }
        return nil
    }
}

/// Only successful raw metadata is cached: missing answers never freeze one catalog's fallback genres into another's.
private actor BrowseMetadataCache {
    struct Key: Hashable, Sendable {
        let type: String
        let id: String
        let sources: [URL]
    }

    private struct Entry {
        let detail: MetaDetail
        let expires: Date
    }

    /// What the addons said. Without a detail, `isFinal` tells "none has the title" from "one could not be reached".
    struct Answer: Sendable {
        var detail: MetaDetail?
        var isFinal = true
    }

    private var entries: [Key: Entry] = [:]
    private var pending: [Key: Task<Answer, Never>] = [:]

    func value(for key: Key, load: @escaping @Sendable () async -> Answer) async -> Answer {
        if let entry = entries[key], entry.expires > Date() { return Answer(detail: entry.detail) }
        if let task = pending[key] { return await task.value }
        guard !key.sources.isEmpty else { return Answer() }
        guard !Task.isCancelled else { return Answer(isFinal: false) }
        let task = Task { await load() }
        pending[key] = task
        let answer = await task.value
        pending[key] = nil
        if let detail = answer.detail {
            if entries.count >= 512 {
                if let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key { entries[oldest] = nil }
            }
            entries[key] = Entry(detail: detail, expires: Date().addingTimeInterval(3600))
        }
        return answer
    }
}

/// Each title's genres as its page lists them, kept across launches so a genre filter does not ask the addons for every title again.
private actor GenreMemory {
    private struct Entry: Codable {
        var genres: [String]
        var saved: Date
    }

    private static let limit = 8000
    private static let lifetime: TimeInterval = 30 * 86_400

    private let file: URL?
    private var entries: [String: Entry]?
    private var saveTask: Task<Void, Never>?

    init(file: URL?) {
        self.file = file
    }

    func genres(for key: String) -> [String]? {
        guard let entry = loaded()[key], Date().timeIntervalSince(entry.saved) < Self.lifetime else { return nil }
        return entry.genres
    }

    func store(_ genres: [String], for key: String) {
        var all = loaded()
        let now = Date()
        // An unchanged answer is written again only once a day.
        if let entry = all[key], entry.genres == genres, now.timeIntervalSince(entry.saved) < 86_400 { return }
        if all[key] == nil, all.count >= Self.limit {
            for stale in all.sorted(by: { $0.value.saved < $1.value.saved }).prefix(Self.limit / 4) { all[stale.key] = nil }
        }
        all[key] = Entry(genres: genres, saved: now)
        entries = all
        scheduleSave()
    }

    private func loaded() -> [String: Entry] {
        if let entries { return entries }
        var read: [String: Entry] = [:]
        if let file, let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            read = decoded
        }
        entries = read
        return read
    }

    /// Lookups arrive in bursts; one write follows the burst.
    private func scheduleSave() {
        guard file != nil, saveTask == nil else { return }
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            self.save()
        }
    }

    private func save() {
        saveTask = nil
        guard let file, let entries, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
