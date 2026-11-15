import Foundation
import StremioKit

/// How the grid behind "See All" orders what it has loaded. `original` keeps the source's own order.
enum CatalogListSort: String, CaseIterable, Identifiable, Sendable, Codable {
    case original
    case rating
    case newest
    case oldest
    case title
    case shuffle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Default"
        case .rating: "Top Rated"
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .title: "A–Z"
        case .shuffle: "Shuffle"
        }
    }

    var systemImage: String {
        switch self {
        case .original: "list.bullet"
        case .rating: "star"
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .title: "textformat"
        case .shuffle: "shuffle"
        }
    }
}

/// A release window offered above the decades: the last few years, counted back from this one.
enum CatalogListRecent: Int, CaseIterable, Identifiable, Sendable {
    case thisYear = 0
    case lastFive = 4
    case lastTen = 9

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thisYear: "This Year"
        case .lastFive: "Last 5 Years"
        case .lastTen: "Last 10 Years"
        }
    }

    func years(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Int> {
        let year = calendar.component(.year, from: now)
        return (year - rawValue)...year
    }
}

/// What the grid behind "See All" shows of what it has loaded: its order, and the type, genre, release years and rating it is narrowed to. Every
/// choice works on the loaded titles, so it applies to any source, addon, TMDB or Trakt alike.
struct CatalogListFilter: Equatable, Sendable {
    var sort: CatalogListSort = .original
    /// "movie" or "series"; nil shows both.
    var type: String?
    /// A genre the titles list, matched whatever its case; nil shows every genre.
    var genre: String?
    var minimumYear: Int?
    var maximumYear: Int?
    /// Out of 10, against the title's rating (see `RatingSource.order(isAnime:)`).
    var minimumRating: Double?

    init(sort: CatalogListSort = .original, type: String? = nil, genre: String? = nil, minimumYear: Int? = nil,
                maximumYear: Int? = nil, minimumRating: Double? = nil) {
        self.sort = sort
        self.type = type
        self.genre = genre
        self.minimumYear = minimumYear
        self.maximumYear = maximumYear
        self.minimumRating = minimumRating
    }

    /// A narrowing choice is on. The order is not a filter: it never hides a title.
    var isFiltering: Bool { type != nil || genre != nil || minimumYear != nil || maximumYear != nil || minimumRating != nil }

    mutating func clearFilters() {
        type = nil
        genre = nil
        minimumYear = nil
        maximumYear = nil
        minimumRating = nil
    }

    /// The release window's label for its menu, or nil when any year shows.
    func yearLabel(now: Date = Date(), calendar: Calendar = .current) -> String? {
        for recent in CatalogListRecent.allCases {
            let range = recent.years(now: now, calendar: calendar)
            if minimumYear == range.lowerBound, maximumYear == range.upperBound { return recent.title }
        }
        switch (minimumYear, maximumYear) {
        case let (low?, high?) where high == low + 9 && low % 10 == 0: return "\(low)s"
        case let (low?, high?): return low == high ? "\(low)" : "\(low)–\(high)"
        case let (low?, nil): return "From \(low)"
        case let (nil, high?): return "Until \(high)"
        case (nil, nil): return nil
        }
    }
}

/// Pure functions behind the grid's filter, so they can be tested without a view or a source.
enum CatalogListFiltering {
    /// How the rating filter and the Top Rated order rate a title (see `RatingSource.order(isAnime:)`). Without the rating store, the
    /// catalog's IMDb rating.
    typealias RatingLookup = (MetaPreview) -> JudgedRating?
    private typealias Kept = (offset: Int, element: MetaPreview, rating: JudgedRating?)

    /// How many places ahead of its own a title that only a looked-up site has scored may land in the source's own order.
    static let dispersal = 40

    static func matches(_ item: MetaPreview, _ filter: CatalogListFilter, rating: RatingLookup = JudgedRating.catalogue) -> Bool {
        if let type = filter.type, item.type.lowercased() != type { return false }
        if let genre = filter.genre, !MediaGenres.contains(genre, in: item.genres) { return false }
        if filter.minimumYear != nil || filter.maximumYear != nil {
            guard let year = LibraryFiltering.year(from: item.releaseInfo) else { return false }
            if let low = filter.minimumYear, year < low { return false }
            if let high = filter.maximumYear, year > high { return false }
        }
        if let minimum = filter.minimumRating {
            guard let judged = rating(item)?.score, judged >= minimum else { return false }
        }
        return true
    }

    /// The items that pass the filter, in its order. `shuffleRank` places each item when the order is Shuffle; an item it has no rank for
    /// goes after the ranked ones, in loaded order. Titles missing what an order needs (a rating, a year) go last, in loaded order.
    static func apply(_ filter: CatalogListFilter, to items: [MetaPreview], shuffleRank: [String: Int] = [:],
                             rating: RatingLookup = JudgedRating.catalogue) -> [MetaPreview] {
        let needsRatings = filter.minimumRating != nil || filter.sort == .rating
        var kept: [Kept] = []
        for (offset, item) in items.enumerated() {
            let judged = needsRatings ? rating(item) : nil
            guard matches(item, filter, rating: { _ in judged }) else { continue }
            kept.append((offset: offset, element: item, rating: judged))
        }
        let ordered: [Kept]
        switch filter.sort {
        case .original:
            ordered = filter.minimumRating == nil ? kept : dispersed(kept)
        case .rating:
            ordered = kept.sorted { compare($0.rating?.score, $1.rating?.score, descending: true) ?? ($0.offset < $1.offset) }
        case .newest:
            ordered = kept.sorted { compare(year($0.element), year($1.element), descending: true) ?? ($0.offset < $1.offset) }
        case .oldest:
            ordered = kept.sorted { compare(year($0.element), year($1.element), descending: false) ?? ($0.offset < $1.offset) }
        case .title:
            ordered = kept.sorted {
                let order = $0.element.name.localizedStandardCompare($1.element.name)
                return order == .orderedSame ? $0.offset < $1.offset : order == .orderedAscending
            }
        case .shuffle:
            ordered = kept.sorted {
                let left = shuffleRank[$0.element.identity] ?? Int.max, right = shuffleRank[$1.element.identity] ?? Int.max
                return left == right ? $0.offset < $1.offset : left < right
            }
        }
        guard let genre = filter.genre else { return ordered.map(\.element) }
        // A title shown for a genre leads with it on its card and its page.
        return ordered.map { entry -> MetaPreview in
            var item = entry.element
            item.genres = MediaGenres.leading([genre], in: item.genres)
            return item
        }
    }

    /// Under a rating filter in the source's own order, titles IMDb has scored keep their places, as they show first. A title only
    /// MyAnimeList, Letterboxd or TMDb has scored arrives later, and lands at a random place up to `dispersal` ahead of its own, the same
    /// each time it is drawn, so the late titles spread through the grid.
    private static func dispersed(_ kept: [Kept]) -> [Kept] {
        var placed: [(entry: Kept, place: Double)] = []
        placed.reserveCapacity(kept.count)
        for entry in kept { placed.append((entry, place(of: entry))) }
        placed.sort(by: placedBefore)
        return placed.map(\.entry)
    }

    private static func place(of entry: Kept) -> Double {
        let offset = Double(entry.offset)
        guard entry.rating?.hasIMDb == false else { return offset }
        var hasher = Hasher()
        hasher.combine(entry.element.identity)
        let bucket: UInt = UInt(bitPattern: hasher.finalize()) % 1_000
        let fraction: Double = Double(bucket) / 1_000
        let reach: Double = Double(min(entry.offset, dispersal))
        let shift: Double = fraction * reach
        return offset - 0.5 - shift
    }

    private static func placedBefore(_ left: (entry: Kept, place: Double), _ right: (entry: Kept, place: Double)) -> Bool {
        if left.place == right.place { return left.entry.offset < right.entry.offset }
        return left.place < right.place
    }

    /// Fresh shuffle ranks for `items`, numbered from `start`.
    static func shuffleRanks<G: RandomNumberGenerator>(for items: [MetaPreview], from start: Int = 0,
                                                              using generator: inout G) -> [String: Int] {
        var ranks: [String: Int] = [:]
        for (index, item) in items.shuffled(using: &generator).enumerated() { ranks[item.identity] = start + index }
        return ranks
    }

    private static func year(_ item: MetaPreview) -> Int? { LibraryFiltering.year(from: item.releaseInfo) }

    /// Nil when the two tie, so the caller keeps loaded order. A missing value sorts after any present one.
    private static func compare<T: Comparable>(_ left: T?, _ right: T?, descending: Bool) -> Bool? {
        switch (left, right) {
        case let (l?, r?): return l == r ? nil : (descending ? l > r : l < r)
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return nil
        }
    }
}
