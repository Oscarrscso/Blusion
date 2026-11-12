import Foundation
import Observation
import StremioKit

/// Discover: combine every installed catalog, filter and sort titles, and paginate each source.
@MainActor
@Observable
public final class DiscoverViewModel {
    public enum State: Equatable {
        case idle
        case loadingFirstPage
        case loaded
        case loadingMore
        case failed(AddonError)
    }

    public private(set) var sources: [CatalogSource] = []
    /// Nil combines all content types.
    public private(set) var selectedType: String?
    public private(set) var selectedGenre: String?
    public var showsAllTypes: Bool { selectedType == nil }
    public private(set) var items: [MetaPreview] = []
    public private(set) var state: State = .idle
    public private(set) var canLoadMore = false
    public var isOffline: Bool { state == .failed(.offline) }
    public var sort: CatalogListSort = .original
    public var minimumRating: Double?

    /// The release-year span the Year menu chose, inclusive bounds. Titles outside it are hidden from `visibleItems`; nothing is fetched again.
    public var minimumYear: Int?
    public var maximumYear: Int?

    /// The year span as a filter chip words it, the same as the Library's chips ("1990–1999"); nil when no span is set.
    public var yearSpanLabel: String? {
        switch (minimumYear, maximumYear) {
        case let (low?, high?): low == high ? "\(low)" : "\(low)–\(high)"
        case let (low?, nil): "From \(low)"
        case let (nil, high?): "Until \(high)"
        case (nil, nil): nil
        }
    }

    /// One catalog feeding the "All" mix, with how far it has been read.
    private struct Cursor {
        var source: CatalogSource
        /// The selected genre as this catalog spells it, sent with its requests.
        var genre: String?
        var received = 0
        var hasMore = true
        var seenIDs: Set<String> = []
    }

    private let services: AppServices
    private var cursors: [Cursor] = []
    private var generation = 0

    public init(services: AppServices) {
        self.services = services
    }

    /// The Genre menu's choices: the genres the catalogs offer, named as title pages name them, one of each, A to Z. A compound such as
    /// "Action & Adventure" is offered as the genres it groups. Orders and years an addon lists as genres are left out, since the Sort and
    /// Year menus cover them.
    public var genres: [String] { Self.genres(of: visibleSources.map(\.catalog)) }

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
    public var hasSources: Bool { !sources.isEmpty }

    /// Sort and filter the loaded titles using the same rules as a catalog's See All page.
    public var visibleItems: [MetaPreview] {
        CatalogListFiltering.apply(CatalogListFilter(sort: sort, minimumYear: minimumYear,
                                                    maximumYear: maximumYear, minimumRating: minimumRating), to: items)
    }

    /// Distinct content types of `sources`: by `ContentTypeName.sortRank`, then by first appearance.
    public var types: [String] {
        var order: [String] = []
        for source in sources where !order.contains(source.type) { order.append(source.type) }
        return order.enumerated().sorted { lhs, rhs in
            let (left, right) = (ContentTypeName.sortRank(lhs.element), ContentTypeName.sortRank(rhs.element))
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Every catalog of the selected type, or every installed catalog on All.
    public var visibleSources: [CatalogSource] {
        guard let selectedType else { return sources }
        return sources.filter { $0.type == selectedType }
    }

    public func loadSources() async {
        let refreshed = await services.browse.catalogSources()
        guard !Task.isCancelled else { return }
        let changed = refreshed != sources
        sources = refreshed
        if let selectedType, !types.contains(selectedType) { self.selectedType = nil }
        if let genre = selectedGenre, !genres.contains(genre) { selectedGenre = nil }
        if changed || state == .idle || state == .loadingFirstPage { await reload() }
    }

    /// Type choices narrow the catalogs being combined; they never select an individual catalog.
    public func select(type: String) async {
        guard types.contains(type) else { return }
        selectedType = type
        if let genre = selectedGenre, !genres.contains(genre) { selectedGenre = nil }
        await reload()
    }

    public func selectAllTypes() async {
        selectedType = nil
        await reload()
    }

    /// `nil` clears the filter.
    public func select(genre: String?) async {
        selectedGenre = genre
        await reload()
    }

    public func reload() async {
        guard !Task.isCancelled else { return }
        generation += 1
        let current = generation
        items = []
        canLoadMore = false
        cursors = visibleSources.map { source in
            guard let genre = selectedGenre else { return Cursor(source: source) }
            let options = MediaGenres.options(of: source.catalog)
            let match = MediaGenres.option(genre, in: source.catalog)
            let parameter = match ?? (source.catalog.genreOptions.isEmpty ? genre : nil)
            return Cursor(source: source, genre: parameter, hasMore: options.isEmpty || match != nil)
        }
        guard !sources.isEmpty else {
            state = .idle
            return
        }
        state = .loadingFirstPage
        await loadMixedPage(generation: current)
    }

    /// Each catalog keeps its own raw skip count, independently of duplicate or filtered titles.
    public func loadMore() async {
        guard canLoadMore, state == .loaded else { return }
        let current = generation
        state = .loadingMore
        await loadMixedPage(generation: current)
    }

    /// Empty rounds a genre may read in a row before the page stops asking: catalogs without the genre are checked title by title.
    private static let emptyRoundLimit = 6

    /// Reads a page from every catalog and interleaves their titles, removing duplicates across sources. A catalog that fails is skipped; the
    /// mix only fails when none answers. Under a genre, each title is kept only when its own page lists that genre, and each catalog's
    /// titles show as soon as they are checked.
    private func loadMixedPage(generation current: Int, emptyRounds: Int = 0) async {
        let browse = services.browse
        let genre = selectedGenre
        let pending = cursors.enumerated().filter(\.element.hasMore)
        let previousCount = items.count
        var known = Set(items.map(\.identity))
        var pages: [Int: [MetaPreview]] = [:]
        var failure: Error?
        await withTaskGroup(of: (Int, [MetaPreview]?, Error?).self) { group in
            for (index, cursor) in pending {
                group.addTask {
                    do {
                        let raw = try await browse.page(cursor.source, genre: cursor.genre, skip: cursor.received)
                        let page = genre == nil ? raw : await browse.resolvingGenres(in: raw)
                        return (index, page, nil)
                    } catch { return (index, nil, error) }
                }
            }
            for await (index, page, error) in group {
                guard let page else {
                    failure = error
                    continue
                }
                pages[index] = page
                guard let genre, current == generation, !Task.isCancelled else { continue }
                for var item in page where MediaGenres.contains(genre, in: item.genres) && known.insert(item.identity).inserted {
                    // The card and the page it opens lead with the genre the title is shown for.
                    item.genres = MediaGenres.leading([genre], in: item.genres)
                    items.append(item)
                }
            }
        }
        guard current == generation else { return }
        guard !Task.isCancelled else {
            state = items.isEmpty ? .idle : .loaded
            return
        }
        if pages.isEmpty, let failure, !pending.isEmpty {
            let error = AddonError.from(failure)
            if Task.isCancelled || error == .cancelled {
                state = items.isEmpty ? .idle : .loaded
            } else {
                state = items.isEmpty ? .failed(error) : .loaded
            }
            return
        }
        // Skip counts the complete raw page, whatever the genre kept of it.
        for (index, page) in pages {
            let identities = page.map(\.identity)
            cursors[index].received += page.count
            cursors[index].hasMore = identities.contains { !cursors[index].seenIDs.contains($0) } && cursors[index].source.catalog.supportsSkip
            cursors[index].seenIDs.formUnion(identities)
        }
        if genre == nil {
            let ordered = pages.keys.sorted().map { pages[$0] ?? [] }
            for position in 0..<(ordered.map(\.count).max() ?? 0) {
                for page in ordered where position < page.count && known.insert(page[position].identity).inserted { items.append(page[position]) }
            }
        }
        canLoadMore = cursors.contains(where: \.hasMore)
        // A round can add no cards. Keep paging until the screen can trigger the next load itself.
        if items.count == previousCount, canLoadMore {
            guard emptyRounds + 1 < Self.emptyRoundLimit else {
                canLoadMore = false
                state = .loaded
                return
            }
            await loadMixedPage(generation: current, emptyRounds: emptyRounds + 1)
            return
        }
        state = .loaded
    }

}
