import Foundation
import PlayerKit
import StremioKit

/// What a saved or watched title is, for the Library's type filter. Anything that is not a movie, series or anime is `other`.
enum LibraryKind: String, CaseIterable, Sendable, Identifiable {
    case movie, series, anime, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: "Movies"
        case .series: "Series"
        case .anime: "Anime"
        case .other: "Other"
        }
    }

    init(type: String) {
        switch type.lowercased() {
        case "movie": self = .movie
        case "series": self = .series
        case "anime": self = .anime
        default: self = .other
        }
    }
}

/// Where a title stands: not started, part way through, or finished.
enum WatchStatus: String, CaseIterable, Sendable, Identifiable {
    case unwatched, inProgress, watched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unwatched: "Unwatched"
        case .inProgress: "In progress"
        case .watched: "Watched"
        }
    }
}

enum LibrarySort: String, CaseIterable, Sendable, Identifiable {
    case recentlyAdded, recentlyWatched, title, year, rating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently added"
        case .recentlyWatched: "Recently watched"
        // Named like Discover's orders, so none reads like the Year or Rating filter beside it.
        case .title: "A–Z"
        case .year: "Newest"
        case .rating: "Top Rated"
        }
    }
}

/// How recently a title must have been added to the Library.
enum AddedWithin: String, CaseIterable, Sendable, Identifiable {
    case anyTime, lastWeek, lastMonth, lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyTime: "Any time"
        case .lastWeek: "Last 7 days"
        case .lastMonth: "Last 30 days"
        case .lastYear: "Last year"
        }
    }

    /// The window in days; nil for any time.
    var days: Int? {
        switch self {
        case .anyTime: nil
        case .lastWeek: 7
        case .lastMonth: 30
        case .lastYear: 365
        }
    }
}

/// A rating site that every rating filter and Rating sort judges a title by. A title is rated by the first site in `order(isAnime:)` that
/// has scored it. Each score stays on its own site's scale until it is put out of 10, and it is never averaged with another site's.
enum RatingSource: String, CaseIterable, Sendable, Identifiable {
    case letterboxd, imdb, myAnimeList, tmdb

    var id: String { rawValue }

    /// Letterboxd, then IMDb; anime by MyAnimeList, then IMDb and Letterboxd. TMDb scores posters and reviews, not the rating filter.
    static func order(isAnime: Bool) -> [RatingSource] {
        isAnime ? [.myAnimeList, .imdb, .letterboxd] : [.letterboxd, .imdb]
    }

    /// The top of the site's own scale.
    var scaleMaximum: Double {
        switch self {
        case .letterboxd: 5
        case .imdb, .myAnimeList, .tmdb: 10
        }
    }

    /// A score put out of 10: 3.5 of 5 is 7.
    func outOfTen(_ score: Double) -> Double { score * 10 / scaleMaximum }

    /// The title's rating from its sites' scores, each on its own scale; nil when none has scored it.
    static func judge(isAnime: Bool, score: (RatingSource) -> Double?) -> JudgedRating? {
        for source in order(isAnime: isAnime) {
            if let value = score(source) { return JudgedRating(score: source.outOfTen(value), hasIMDb: score(.imdb) != nil) }
        }
        return nil
    }
}

/// A title's rating as the rating filters and the Rating sorts judge it (see `RatingSource.order(isAnime:)`).
struct JudgedRating: Equatable, Sendable {
    /// Out of 10.
    var score: Double
    /// IMDb has scored the title. IMDb's score is on the device, so such a title is judged as soon as it loads; one only another site has
    /// scored waits for that site's lookup.
    var hasIMDb: Bool

    init(score: Double, hasIMDb: Bool) {
        self.score = score
        self.hasIMDb = hasIMDb
    }

    /// The catalog's IMDb rating, and nothing else: the rating where no lookups are supplied.
    static func catalogue(_ item: MetaPreview) -> JudgedRating? {
        item.imdbRating.map { JudgedRating(score: $0, hasIMDb: true) }
    }
}

/// One active filter, as a chip above the Library. `target` is what removing the chip clears.
struct FilterChip: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case kind(LibraryKind)
        case status(WatchStatus)
        case years
        case genre(String)
        case rating
        case addedWithin
    }

    let target: Target
    let label: String

    var id: String {
        switch target {
        case .kind(let kind): "kind.\(kind.rawValue)"
        case .status(let status): "status.\(status.rawValue)"
        case .years: "years"
        case .genre(let genre): "genre.\(genre)"
        case .rating: "rating"
        case .addedWithin: "addedWithin"
        }
    }
}

/// Every filter and the sort the Library applies. Empty sets and nil bounds mean "no restriction". Sort is not a filter, so
/// `clearFilters()` leaves it alone.
struct LibraryFilter: Equatable, Sendable {
    /// Match any of these types. Empty matches every type.
    var kinds: Set<LibraryKind> = []
    /// Match any of these states. Empty matches every state.
    var statuses: Set<WatchStatus> = []
    /// Inclusive bounds on the release year. A title with no known year is excluded while either bound is set.
    var minimumYear: Int?
    var maximumYear: Int?
    /// Match any of these genres.
    var genres: Set<String> = []
    /// The lowest rating to show, out of 10. A title no site has scored is excluded while this is set.
    var minimumRating: Double?
    var addedWithin: AddedWithin = .anyTime
    var sort: LibrarySort = .recentlyAdded

    init() {}

    /// True when any filter restricts the list (the sort does not count).
    var isNarrowing: Bool {
        !kinds.isEmpty || !statuses.isEmpty || minimumYear != nil || maximumYear != nil || !genres.isEmpty || minimumRating != nil
            || addedWithin != .anyTime
    }

    /// Removes every filter and keeps the sort.
    mutating func clearFilters() {
        kinds = []
        statuses = []
        minimumYear = nil
        maximumYear = nil
        genres = []
        minimumRating = nil
        addedWithin = .anyTime
    }

    /// Clears the one filter a chip stands for.
    mutating func remove(_ target: FilterChip.Target) {
        switch target {
        case .kind(let kind): kinds.remove(kind)
        case .status(let status): statuses.remove(status)
        case .years:
            minimumYear = nil
            maximumYear = nil
        case .genre(let genre): genres.remove(genre)
        case .rating: minimumRating = nil
        case .addedWithin: addedWithin = .anyTime
        }
    }

    /// One chip per active filter, in a fixed order: type, state, years, genres, rating, added date.
    var chips: [FilterChip] {
        var chips: [FilterChip] = []
        chips += LibraryKind.allCases.filter { kinds.contains($0) }.map { FilterChip(target: .kind($0), label: $0.title) }
        chips += WatchStatus.allCases.filter { statuses.contains($0) }.map { FilterChip(target: .status($0), label: $0.title) }
        if minimumYear != nil || maximumYear != nil {
            chips.append(FilterChip(target: .years, label: yearLabel))
        }
        chips += genres.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { FilterChip(target: .genre($0), label: $0) }
        if let minimumRating {
            chips.append(FilterChip(target: .rating, label: "Rating \(LibraryFiltering.minimumRatingText(minimumRating))"))
        }
        if addedWithin != .anyTime {
            chips.append(FilterChip(target: .addedWithin, label: addedWithin.title))
        }
        return chips
    }

    private var yearLabel: String { LibraryFiltering.yearSpanLabel(from: minimumYear, to: maximumYear) }
}

/// One title in the Library, with what is known about it. A saved title carries its saved record and any progress made on it. A watch
/// record that was never saved carries only its progress, so it has no year, genres, rating or added date.
struct LibraryEntry: Identifiable, Equatable, Sendable {
    let id: String
    let kind: LibraryKind
    let title: String
    let year: Int?
    let rating: Double?
    /// As saved, until the Library replaces them with the genres the title's own page lists.
    var genres: [String]
    let addedAt: Date?
    /// The title as the rating lookups know it, by its id.
    let preview: MetaPreview
    /// When the title was last watched or progressed, if ever.
    let activityAt: Date?
    let status: WatchStatus
    /// The saved title, when there is one.
    var item: LibraryItem?
    /// The progress record shown for this title: the one a Continue Watching or Watched card opens. For a saved title, the most recent
    /// record, when it has any.
    let progress: WatchProgress?

    /// A saved title. Its status is the most advanced one among its progress records: in progress if any episode is part way, else
    /// watched if any record is watched, else unwatched.
    init(item: LibraryItem, records: [WatchProgress]) {
        id = item.id
        kind = LibraryKind(type: item.type)
        title = item.name
        year = LibraryFiltering.year(from: item.releaseInfo)
        rating = item.imdbRating
        genres = item.genres
        addedAt = item.addedAt
        preview = item.preview
        activityAt = records.map(\.updatedAt).max()
        status = LibraryFiltering.status(of: records)
        self.item = item
        progress = records.max { $0.updatedAt < $1.updatedAt }
    }

    /// A progress record. Its metadata comes from the saved title it belongs to, when there is one.
    init(record: WatchProgress, saved: LibraryItem?) {
        let name = WatchedCards.name(of: record)
        id = record.id
        kind = LibraryKind(type: record.type)
        title = saved?.name ?? name
        year = LibraryFiltering.year(from: saved?.releaseInfo)
        rating = saved?.imdbRating
        genres = saved?.genres ?? []
        addedAt = saved?.addedAt
        preview = saved?.preview ?? MetaPreview(id: record.seriesID ?? record.contentID, type: record.type, name: name, poster: record.poster)
        activityAt = record.updatedAt
        status = LibraryFiltering.status(of: [record])
        item = saved
        progress = record
    }
}

/// Pure functions behind the Library's filters and sorting, so they can be tested without a view or a store.
enum LibraryFiltering {
    /// The first four-digit year in a release string: "1999", "2019-2023" and "2020-" all give their first year.
    static func year(from releaseInfo: String?) -> Int? {
        guard let releaseInfo else { return nil }
        var digits = ""
        for character in releaseInfo {
            if character.isASCII, character.isNumber {
                digits.append(character)
                if digits.count == 4 { return Int(digits) }
            } else {
                digits = ""
            }
        }
        return nil
    }

    /// The status a set of progress records gives one title.
    static func status(of records: [WatchProgress]) -> WatchStatus {
        if records.contains(where: { !$0.isWatched && ProgressRecorder.resumePosition(for: $0) > 0 }) { return .inProgress }
        if records.contains(where: \.isWatched) { return .watched }
        return .unwatched
    }

    /// The rating an entry is judged by for the rating filter and the Rating sort (see `RatingSource.order(isAnime:)`); nil when no site
    /// has scored it. The view model supplies the rating lookups.
    typealias ScoreLookup = (LibraryEntry) -> JudgedRating?

    /// The catalogue's IMDb rating, and nothing else. Used when no lookup is supplied.
    static func catalogueScores(_ entry: LibraryEntry) -> JudgedRating? {
        entry.rating.map { JudgedRating(score: $0, hasIMDb: true) }
    }

    /// Whether an entry passes every active filter. `now` anchors the added-date window.
    static func matches(_ entry: LibraryEntry, _ filter: LibraryFilter, now: Date, score: ScoreLookup = catalogueScores) -> Bool {
        if !filter.kinds.isEmpty, !filter.kinds.contains(entry.kind) { return false }
        if !filter.statuses.isEmpty, !filter.statuses.contains(entry.status) { return false }
        if filter.minimumYear != nil || filter.maximumYear != nil {
            guard let year = entry.year else { return false }
            if let low = filter.minimumYear, year < low { return false }
            if let high = filter.maximumYear, year > high { return false }
        }
        if !filter.genres.isEmpty, !filter.genres.contains(where: { MediaGenres.contains($0, in: entry.genres) }) { return false }
        if let minimum = filter.minimumRating {
            guard let rating = score(entry)?.score, rating >= minimum else { return false }
        }
        if let days = filter.addedWithin.days {
            guard let added = entry.addedAt, added >= now.addingTimeInterval(-Double(days) * 86_400) else { return false }
        }
        return true
    }

    /// The entries that pass the filter, in the filter's sort order.
    static func apply(_ filter: LibraryFilter, to entries: [LibraryEntry], now: Date = Date(),
                             score: ScoreLookup = catalogueScores) -> [LibraryEntry] {
        sorted(entries.filter { matches($0, filter, now: now, score: score) }, by: filter.sort, score: score)
    }

    /// Sorts by one key, with the title (then id) as the tie-break so the order is always the same. Missing values sort last. The Rating
    /// sort rates each entry with `score`, as the rating filter does.
    static func sorted(_ entries: [LibraryEntry], by sort: LibrarySort, score: ScoreLookup = catalogueScores) -> [LibraryEntry] {
        let ratings = sort == .rating ? entries.map { score($0)?.score } : []
        return entries.indices.sorted { left, right in
            let (lhs, rhs) = (entries[left], entries[right])
            switch sort {
            case .title:
                break
            case .year:
                if let order = descending(lhs.year.map(Double.init), rhs.year.map(Double.init)) { return order }
            case .rating:
                if let order = descending(ratings[left], ratings[right]) { return order }
            case .recentlyAdded:
                if let order = descending(lhs.addedAt ?? lhs.activityAt, rhs.addedAt ?? rhs.activityAt) { return order }
            case .recentlyWatched:
                if let order = descending(lhs.activityAt ?? lhs.addedAt, rhs.activityAt ?? rhs.addedAt) { return order }
            }
            let byTitle = lhs.title.localizedStandardCompare(rhs.title)
            if byTitle != .orderedSame { return byTitle == .orderedAscending }
            return lhs.id < rhs.id
        }.map { entries[$0] }
    }

    /// Newest or highest first. nil when the keys are equal, so the caller moves on to the next key. A missing value sorts after a
    /// present one, and two missing values are equal.
    private static func descending<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool? {
        switch (lhs, rhs) {
        case let (left?, right?): return left == right ? nil : left > right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return nil
        }
    }

    /// Every genre any entry has, sorted, for the genre picker.
    static func genres(in entries: [LibraryEntry]) -> [String] {
        MediaGenres.choices(in: entries.flatMap(\.genres))
    }

    /// A release span as the chips name it: "1990", "1990–1999", "From 1990" or "Until 1999". Empty when neither end is set. Shared with
    /// the Downloads page's year filter.
    static func yearSpanLabel(from low: Int?, to high: Int?) -> String {
        switch (low, high) {
        case let (low?, high?): low == high ? "\(low)" : "\(low)–\(high)"
        case let (low?, nil): "From \(low)"
        case let (nil, high?): "Until \(high)"
        case (nil, nil): ""
        }
    }

    /// The earliest and latest years any entry has; nil when none has a year.
    static func yearRange(in entries: [LibraryEntry]) -> ClosedRange<Int>? {
        let years = entries.compactMap(\.year)
        guard let low = years.min(), let high = years.max() else { return nil }
        return low...high
    }

    /// "80" for 8.0 and "75" for 7.5: the threshold as a whole score out of 100, the way the rating picker and chips show it.
    static func ratingText(_ value: Double) -> String {
        ScoreText.wholeScore(value)
    }

    /// A lower-bound rating label. The maximum possible score is exact, so it has no misleading trailing plus.
    static func minimumRatingText(_ value: Double) -> String {
        ratingText(value) + (value >= 10 ? "" : "+")
    }
}
