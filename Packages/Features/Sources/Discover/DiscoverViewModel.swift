import Foundation
import Observation
import PlayerKit
import StremioKit

/// Discover: mix TMDb recommendations for a shuffled sample of the library, filter and sort locally, and paginate.
@MainActor
@Observable
final class DiscoverViewModel {
    enum State: Equatable {
        case idle
        case loadingFirstPage
        case loaded
        case loadingMore
        case failed(AddonError)
    }

    /// One library title chosen as a recommendation seed.
    struct Seed: Equatable, Hashable, Sendable {
        let id: String
        let type: String

        init(id: String, type: String) {
            self.id = id
            self.type = type
        }

        var identity: String { "\(type)/\(id)" }
    }

    static let windowSize = 24
    static let seedLimit = 6
    static let keywordPageLimit = 4
    private static let imdbBatchSize = 6
    private static let discoverPageSize = 20

    private(set) var sources: [CatalogSource] = []
    /// Nil combines movies and series.
    private(set) var selectedType: String?
    private(set) var selectedGenre: String?
    var showsAllTypes: Bool { selectedType == nil }
    private(set) var items: [MetaPreview] = []
    private(set) var state: State = .idle
    private(set) var canLoadMore = false
    var isOffline: Bool { state == .failed(.offline) }
    var sort: CatalogListSort = .original
    var minimumRating: Double?

    /// The release-year span the Year menu chose, inclusive bounds. Titles outside it are hidden from `visibleItems`; nothing is fetched again.
    var minimumYear: Int?
    var maximumYear: Int?

    /// The library seeds chosen on the latest reload, kept across `loadMore()`.
    private(set) var seeds: [Seed] = []

    /// The year span as a filter chip words it, the same as the Library's chips ("1990–1999"); nil when no span is set.
    var yearSpanLabel: String? {
        switch (minimumYear, maximumYear) {
        case let (low?, high?): low == high ? "\(low)" : "\(low)–\(high)"
        case let (low?, nil): "From \(low)"
        case let (nil, high?): "Until \(high)"
        case (nil, nil): nil
        }
    }

    private let services: AppServices
    private let shuffleSeeds: ([Seed]) -> [Seed]
    private let titleIDs = TMDbTitleIDCache()
    private let imdbIDs = TMDbIMDbIDCache()
    private var generation = 0
    private var libraryIdentities: Set<String> = []
    private var knownIdentities: Set<String> = []
    private var seenTMDb: Set<String> = []
    private var candidates: [TMDbRelatedTitle] = []
    private var overflow: [MetaPreview] = []
    private var activeSeedIndices: [Int] = []
    private var recommendationPage = 1
    private var keywordQueries: [TMDbDiscoverQuery]?
    private var keywordSkip = 0
    private var hasMoreKeywords = true
    private var popularSkip = 0

    init(services: AppServices, shuffle: @escaping ([Seed]) -> [Seed] = { $0.shuffled() }) {
        self.services = services
        self.shuffleSeeds = shuffle
    }

    /// The Genre menu's choices: the genres the loaded titles list, named as title pages name them, one of each, A to Z.
    var genres: [String] { MediaGenres.choices(in: items.flatMap(\.genres)) }

    static func genres(of catalogs: [CatalogDescriptor]) -> [String] {
        MediaGenres.choices(in: catalogs.flatMap(genreOptions(of:)))
    }

    /// The same recognised genre options as Search, excluding orders, years and curated topics.
    static func genreOptions(of catalog: CatalogDescriptor) -> [String] {
        MediaGenres.options(of: catalog)
    }

    /// "2024", "1990s" or "1990's".
    static func isYear(_ option: String) -> Bool {
        option.range(of: #"^\s*\d{4}'?s?\s*$"#, options: .regularExpression) != nil
    }

    /// An option that orders or narrows the catalog rather than naming a genre: "Recently Added", "Release Date (Newest)", "Title Z-A",
    /// "Top Rated", "Shortest", "Random", "Not Watched".
    static func isOrder(_ option: String) -> Bool {
        let text = option.lowercased()
        if text.unicodeScalars.contains(where: { "↑↓⬆⬇▲▼".unicodeScalars.contains($0) }) { return true }
        if text.range(of: #"\b[az]\s*[-–—]\s*[az]\b"#, options: .regularExpression) != nil { return true }
        let orderWords: Set<Substring> = ["added", "newest", "oldest", "latest", "recent", "recently", "release", "released", "date", "year",
                                          "title", "name", "alphabetical", "ascending", "descending", "asc", "desc", "sort", "rated",
                                          "rating", "popularity", "shortest", "longest", "random", "shuffle", "shuffled", "watched",
                                          "unwatched", "runtime", "duration", "length"]
        return text.split(whereSeparator: { !$0.isLetter }).contains { orderWords.contains($0) }
    }

    var hasSources: Bool { true }

    /// Sort and filter the loaded titles locally using the same rules as a catalog's See All page. Under a rating threshold or Top Rated,
    /// each title's scores come from the rating store, and a view reading this draws again as each one arrives.
    var visibleItems: [MetaPreview] {
        let filter = CatalogListFilter(sort: sort, type: selectedType, genre: selectedGenre, minimumYear: minimumYear,
                                       maximumYear: maximumYear, minimumRating: minimumRating)
        guard filter.minimumRating != nil || filter.sort == .rating else { return CatalogListFiltering.apply(filter, to: items) }
        let store = services.posterRatings
        return CatalogListFiltering.apply(filter, to: items, rating: { item in store.judgedRating(for: item) ?? JudgedRating.catalogue(item) })
    }

    /// Discover's content types on both platforms.
    var types: [String] { ["movie", "series"] }

    var visibleSources: [CatalogSource] { sources }

    /// Starts the initial load without touching addon catalogs.
    func loadSources() async {
        if state == .idle || state == .loadingFirstPage {
            await reload()
        }
    }

    /// Changing type reloads the library seeds for that type.
    func select(type: String) async {
        let normalized = type.lowercased()
        guard types.contains(normalized) else { return }
        selectedType = normalized
        await reload()
    }

    func selectAllTypes() async {
        selectedType = nil
        await reload()
    }

    /// `nil` clears the filter. Genre filters the loaded titles locally without reloading the seeds.
    func select(genre: String?) async {
        selectedGenre = genre
    }

    func reload() async {
        guard !Task.isCancelled else { return }
        generation += 1
        let current = generation
        items = []
        canLoadMore = false
        seeds = []
        libraryIdentities = []
        knownIdentities = []
        seenTMDb = []
        candidates = []
        overflow = []
        activeSeedIndices = []
        recommendationPage = 1
        keywordQueries = nil
        keywordSkip = 0
        hasMoreKeywords = true
        popularSkip = 0

        let rawToken = await services.settings.load().tmdbReadToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled, current == generation else { return }
        guard let token = rawToken, !token.isEmpty else {
            state = .loaded
            return
        }

        state = .loadingFirstPage
        let (pool, known) = await loadLibraryPool(for: selectedType)
        guard !Task.isCancelled, current == generation else {
            state = items.isEmpty ? .idle : .loaded
            return
        }
        libraryIdentities = known
        seeds = Array(shuffleSeeds(pool).prefix(Self.seedLimit))
        activeSeedIndices = Array(seeds.indices)

        let tmdb = makeTMDb(token: token)
        if seeds.isEmpty {
            await loadPopularPage(tmdb: tmdb, generation: current)
        } else {
            await loadSeededWindow(tmdb: tmdb, generation: current)
        }
    }

    func loadMore() async {
        guard canLoadMore, state == .loaded else { return }
        let current = generation
        let rawToken = await services.settings.load().tmdbReadToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled, current == generation, let token = rawToken, !token.isEmpty else { return }
        state = .loadingMore
        let tmdb = makeTMDb(token: token)
        if seeds.isEmpty {
            await loadPopularPage(tmdb: tmdb, generation: current)
        } else {
            await loadSeededWindow(tmdb: tmdb, generation: current)
        }
    }

    private func makeTMDb(token: String) -> TMDbRatings {
        TMDbRatings(client: services.client, readAccessToken: token, titleIDs: titleIDs, imdbIDs: imdbIDs)
    }

    /// Reads the saved and watched titles from the library stores. `known` holds every library title's identity so recommendations skip
    /// them; `pool` holds the eligible IMDb seeds for `type` (`nil` keeps both movies and series).
    private func loadLibraryPool(for type: String?) async -> (pool: [Seed], known: Set<String>) {
        let saved = await services.library.all()
        let progress = await services.progress.all()
        var known: Set<String> = []
        var seenSeeds: Set<Seed> = []
        var pool: [Seed] = []

        func consider(id: String, rawType: String) {
            let kind = rawType.lowercased()
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else { return }
            known.insert("\(kind)/\(trimmedID)")
            guard ["movie", "series"].contains(kind), LetterboxdRatings.isIMDbID(trimmedID) else { return }
            if let type, kind != type { return }
            let seed = Seed(id: trimmedID, type: kind)
            if seenSeeds.insert(seed).inserted {
                pool.append(seed)
            }
        }

        for item in saved {
            consider(id: item.contentID, rawType: item.type)
        }
        for record in progress where record.isWatched {
            consider(id: record.seriesID ?? record.contentID, rawType: record.type)
        }
        return (pool, known)
    }

    /// Empty-library fallback: one popular movie page and one popular series page interleaved on All, or one popular page of the selected
    /// type when narrowed.
    private func loadPopularPage(tmdb: TMDbRatings, generation current: Int) async {
        let region = Locale.current.region?.identifier ?? "US"
        let kinds: [TMDbDiscoverQuery.Kind]
        switch selectedType {
        case "movie": kinds = [.movie]
        case "series": kinds = [.series]
        default: kinds = [.movie, .series]
        }
        let skip = popularSkip
        let outcomes = await withTaskGroup(of: (Int, Result<[MetaPreview], Error>).self,
                                           returning: [(Int, Result<[MetaPreview], Error>)].self) { group in
            for (index, kind) in kinds.enumerated() {
                let query = TMDbDiscoverQuery(kind: kind, ordering: .popular)
                group.addTask {
                    do {
                        let page = try await tmdb.discoverItems(query, limit: Self.discoverPageSize, skip: skip, defaultRegion: region)
                        return (index, .success(page))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[MetaPreview], Error>)] = []
            for await outcome in group { collected.append(outcome) }
            return collected.sorted { $0.0 < $1.0 }
        }
        guard current == generation else { return }
        guard !Task.isCancelled else {
            state = items.isEmpty ? .idle : .loaded
            return
        }
        var pages: [[MetaPreview]] = []
        var firstError: Error?
        for (_, result) in outcomes {
            switch result {
            case .success(let page): pages.append(page)
            case .failure(let error): firstError = firstError ?? error
            }
        }
        if pages.isEmpty, let firstError {
            finishWithError(firstError)
            return
        }
        popularSkip += Self.discoverPageSize
        let merged = Self.interleave(pages).filter { item in
            !libraryIdentities.contains(item.identity) && knownIdentities.insert(item.identity).inserted
        }
        items.append(contentsOf: merged)
        canLoadMore = !merged.isEmpty
        state = .loaded
    }

    /// Loads the next 24-title window from the current seeds' recommendation pages, resolving IMDb ids six at a time, and tops up from
    /// up to 4 keyword discover pages when the window is still short.
    private func loadSeededWindow(tmdb: TMDbRatings, generation current: Int) async {
        var added: [MetaPreview] = []
        if !overflow.isEmpty {
            let take = min(Self.windowSize, overflow.count)
            added.append(contentsOf: overflow.prefix(take))
            overflow.removeFirst(take)
        }

        if added.count < Self.windowSize, !candidates.isEmpty {
            let resolved = await resolveNextCandidates(tmdb: tmdb, needed: Self.windowSize - added.count, generation: current)
            guard current == generation, !Task.isCancelled else {
                if current == generation { state = items.isEmpty ? .idle : .loaded }
                return
            }
            added.append(contentsOf: resolved)
        }

        var seedError: Error?
        var anySeedAnswered = !added.isEmpty
        if added.count < Self.windowSize, !activeSeedIndices.isEmpty {
            let page = recommendationPage
            recommendationPage += 1
            let pending = activeSeedIndices
            let currentSeeds = seeds
            let outcomes = await withTaskGroup(of: (Int, Result<[TMDbRelatedTitle], Error>).self,
                                               returning: [(Int, Result<[TMDbRelatedTitle], Error>)].self) { group in
                for index in pending {
                    let seed = currentSeeds[index]
                    group.addTask {
                        do {
                            let list = try await tmdb.relatedTitles(imdbID: seed.id, type: seed.type, page: page)
                            return (index, .success(list))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }
                var collected: [(Int, Result<[TMDbRelatedTitle], Error>)] = []
                for await outcome in group { collected.append(outcome) }
                return collected.sorted { $0.0 < $1.0 }
            }
            guard current == generation else { return }
            guard !Task.isCancelled else {
                state = items.isEmpty ? .idle : .loaded
                return
            }

            var lists: [[TMDbRelatedTitle]] = []
            var nextActive: [Int] = []
            for (index, outcome) in outcomes {
                switch outcome {
                case .success(let list):
                    anySeedAnswered = true
                    if !list.isEmpty {
                        lists.append(list)
                        nextActive.append(index)
                    }
                case .failure(let error):
                    seedError = seedError ?? error
                }
            }
            activeSeedIndices = nextActive

            if !anySeedAnswered, let seedError, items.isEmpty, added.isEmpty {
                finishWithError(seedError)
                return
            }

            for title in Self.interleave(lists) where seenTMDb.insert(title.id).inserted {
                candidates.append(title)
            }

            let resolved = await resolveNextCandidates(tmdb: tmdb, needed: Self.windowSize - added.count, generation: current)
            guard current == generation, !Task.isCancelled else {
                if current == generation { state = items.isEmpty ? .idle : .loaded }
                return
            }
            added.append(contentsOf: resolved)
        }

        if added.count < Self.windowSize {
            let filled = await fillWithKeywords(tmdb: tmdb, needed: Self.windowSize - added.count, generation: current)
            guard current == generation, !Task.isCancelled else {
                if current == generation { state = items.isEmpty ? .idle : .loaded }
                return
            }
            added.append(contentsOf: filled)
        }

        items.append(contentsOf: added)
        let hasMoreSeedWork = !overflow.isEmpty || !candidates.isEmpty || !activeSeedIndices.isEmpty
            || (hasMoreKeywords && !(keywordQueries?.isEmpty ?? true))
        canLoadMore = !added.isEmpty && hasMoreSeedWork
        state = .loaded
    }

    /// Resolves IMDb ids for `candidates` six at a time until `needed` valid titles are kept or `candidates` is empty. Any extra valid
    /// titles from the final batch of six are kept in `overflow` for the next page.
    private func resolveNextCandidates(tmdb: TMDbRatings, needed: Int, generation current: Int) async -> [MetaPreview] {
        var kept: [MetaPreview] = []
        while kept.count < needed, !candidates.isEmpty {
            guard current == generation, !Task.isCancelled else { return kept }
            let count = min(Self.imdbBatchSize, candidates.count)
            let batch = Array(candidates.prefix(count))
            candidates.removeFirst(count)
            let ids = await withTaskGroup(of: (Int, String?).self, returning: [String?].self) { group in
                for (offset, title) in batch.enumerated() {
                    group.addTask {
                        (offset, try? await tmdb.imdbID(tmdbID: title.tmdbID, mediaType: title.mediaType))
                    }
                }
                var resolved = [String?](repeating: nil, count: batch.count)
                for await (offset, id) in group { resolved[offset] = id }
                return resolved
            }
            guard current == generation, !Task.isCancelled else { return kept }
            for (title, imdbID) in zip(batch, ids) {
                guard let imdbID else { continue }
                let preview = title.preview(imdbID: imdbID)
                guard !libraryIdentities.contains(preview.identity), knownIdentities.insert(preview.identity).inserted else { continue }
                if kept.count < needed {
                    kept.append(preview)
                } else {
                    overflow.append(preview)
                }
            }
        }
        return kept
    }

    /// Looks up keywords on the current seeds when the 24-title window is short and mixes in up to 4 discover pages, one keyword each.
    private func fillWithKeywords(tmdb: TMDbRatings, needed: Int, generation current: Int) async -> [MetaPreview] {
        guard needed > 0, hasMoreKeywords, !seeds.isEmpty else { return [] }
        if keywordQueries == nil {
            let currentSeeds = seeds
            let lists = await withTaskGroup(of: (Int, [TMDbDiscoverQuery.Named]).self,
                                            returning: [[TMDbDiscoverQuery.Named]].self) { group in
                for (index, seed) in currentSeeds.enumerated() {
                    group.addTask {
                        let found = (try? await tmdb.titleKeywords(imdbID: seed.id, type: seed.type)) ?? []
                        return (index, found)
                    }
                }
                var bySeed = Array(repeating: [TMDbDiscoverQuery.Named](), count: currentSeeds.count)
                for await (index, list) in group { bySeed[index] = list }
                return bySeed
            }
            guard current == generation, !Task.isCancelled else { return [] }
            var seenKeywords: Set<Int> = []
            var queries: [TMDbDiscoverQuery] = []
            let longest = lists.map(\.count).max() ?? 0
            outer: for position in 0..<longest {
                for (seedIndex, list) in lists.enumerated() where position < list.count {
                    let keyword = list[position]
                    guard seenKeywords.insert(keyword.id).inserted else { continue }
                    let kind: TMDbDiscoverQuery.Kind = currentSeeds[seedIndex].type == "series" ? .series : .movie
                    queries.append(TMDbDiscoverQuery(kind: kind, ordering: .popular, keywords: [keyword]))
                    if queries.count == Self.keywordPageLimit { break outer }
                }
            }
            keywordQueries = queries
        }

        guard let queries = keywordQueries, !queries.isEmpty else {
            hasMoreKeywords = false
            return []
        }

        let region = Locale.current.region?.identifier ?? "US"
        let skip = keywordSkip
        let pages = await withTaskGroup(of: (Int, [MetaPreview]).self, returning: [[MetaPreview]].self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    let items = (try? await tmdb.discoverItems(query, limit: Self.discoverPageSize, skip: skip, defaultRegion: region)) ?? []
                    return (index, items)
                }
            }
            var ordered = Array(repeating: [MetaPreview](), count: queries.count)
            for await (index, page) in group { ordered[index] = page }
            return ordered
        }
        guard current == generation, !Task.isCancelled else { return [] }
        keywordSkip += Self.discoverPageSize
        let interleaved = Self.interleave(pages)
        if interleaved.isEmpty {
            hasMoreKeywords = false
            return []
        }
        var kept: [MetaPreview] = []
        for item in interleaved {
            guard !libraryIdentities.contains(item.identity), knownIdentities.insert(item.identity).inserted else { continue }
            if kept.count < needed {
                kept.append(item)
            } else {
                overflow.append(item)
            }
        }
        return kept
    }

    private func finishWithError(_ error: Error) {
        let addonError = AddonError.from(error)
        if Task.isCancelled || addonError == .cancelled {
            state = items.isEmpty ? .idle : .loaded
        } else {
            state = items.isEmpty ? .failed(addonError) : .loaded
        }
    }

    private static func interleave<Element>(_ lists: [[Element]]) -> [Element] {
        var merged: [Element] = []
        let longest = lists.map(\.count).max() ?? 0
        for position in 0..<longest {
            for list in lists where position < list.count {
                merged.append(list[position])
            }
        }
        return merged
    }
}
