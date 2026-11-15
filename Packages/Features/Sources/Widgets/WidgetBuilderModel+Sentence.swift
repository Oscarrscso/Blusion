import Foundation
import Observation
import StremioKit

extension WidgetBuilderModel {
    // MARK: Sentence

    /// The sentence that describes the widget. It always ends with a full stop. The view draws the tokens and the kind dropdown.
    var sentence: [SentenceItem] {
        let shape = sentenceShape
        let parts = shape.head + Self.joined(shape.pieces) + [.text(".")]
        return parts.enumerated().map { SentenceItem(id: $0.offset, part: $0.element) }
    }

    /// The fixed words that lead the sentence, and the pieces that follow them, joined by `joined`.
    private var sentenceShape: (head: [Part], pieces: [[Part]]) {
        switch row.source {
        case .tmdbDiscover(let query):
            let head: [Part] = [.text("Make a"), .kind(query.kind), .text("list sorted by")]
            let ordering = Self.token(.ordering, Self.orderingPhrase(query.ordering), removable: false)
            return (head, [[ordering]] + filterClauses(query) + commonClauses)
        case .addonCatalog:
            // The genre and the sort read straight on from the source's name, with no "and" before them.
            var lead: [Part] = [.text("Show"), sourcePart]
            if let genre = catalogGenreName { lead += Self.clause("about", [Self.token(.catalogGenre, genre)]) }
            return ([], [lead] + commonClauses)
        case .traktList(let list):
            var lead: [Part] = [.text("Show the Trakt list"), sourcePart]
            if let sort = list.sort { lead += Self.clause("sorted by", [Self.token(.traktSort, sort.title)]) }
            return ([], [lead] + commonClauses)
        case .traktFeed:
            return ([], [[.text("Show"), sourcePart, .text("from Trakt")]] + commonClauses)
        case .unsupported:
            return ([.text("Choose what this widget shows:")], [[Self.token(.source, "Source", removable: false)]])
        }
    }

    /// The clauses that narrow a TMDB list: one for each filter that is set, in the order the sentence reads.
    private func filterClauses(_ saved: TMDbDiscoverQuery) -> [[Part]] {
        // A filter the list cannot use (one an imported file carried) is not part of what the widget shows, so it is not read out.
        let query = saved.removingUnsupportedFilters()
        var clauses: [[Part]] = []
        if query.isSet(.genres) {
            clauses.append(Self.clause("about", query.genres.map { Self.token(.genres, $0.name.lowercased(), valueID: $0.id) }))
        }
        if query.isSet(.keywords) {
            clauses.append(Self.clause("with", query.keywords.map { Self.token(.keywords, $0.name, valueID: $0.id) }))
        }
        if query.isSet(.excludedKeywords) {
            clauses.append(Self.clause("without", query.excludedKeywords.map { Self.token(.excludedKeywords, $0.name, valueID: $0.id) }))
        }
        if let period = query.period {
            clauses.append(Self.clause("from", [Self.token(.period, Self.periodPhrase(period))]))
        }
        if let text = Self.releaseText(query) { clauses.append(Self.clause("released", [Self.token(.release, text)])) }
        // A widget's score is each title's rating as the rating filters judge it, and its votes IMDb's: the sentence says so.
        if let text = Self.scoreText(query) { clauses.append(Self.clause("rated", [Self.token(.score, text)])) }
        if query.isSet(.votes), let votes = query.minimumVotes {
            clauses.append(Self.clause("with", [Self.token(.votes, "\(votes)+ IMDb votes")]))
        }
        if let code = query.language { clauses.append(Self.clause("in", [Self.token(.language, Self.languageName(code))])) }
        if let text = Self.runtimeText(query) { clauses.append(Self.clause("running", [Self.token(.runtime, text)])) }
        if query.isSet(.providers) {
            clauses.append(Self.clause("on", query.providers.map { Self.token(.providers, $0.name, valueID: $0.id) }))
            let region = query.region ?? deviceRegion
            clauses.append(Self.clause("in", [Self.token(.region, Self.regionName(region), removable: query.region != nil)]))
        }
        if query.isSet(.cast) {
            clauses.append(Self.clause("starring", query.cast.map { Self.token(.cast, $0.name, valueID: $0.id) }))
        }
        if query.isSet(.crew) {
            clauses.append(Self.clause("made by", query.crew.map { Self.token(.crew, $0.name, valueID: $0.id) }))
        }
        if query.isSet(.companies) {
            clauses.append(Self.clause("from", query.companies.map { Self.token(.companies, $0.name, valueID: $0.id) }))
        }
        return clauses
    }

    /// The clauses every source has: the item count when it is not 20, and the title when the user named the widget.
    private var commonClauses: [[Part]] {
        var clauses: [[Part]] = []
        if row.limit != 20 { clauses.append(Self.clause("showing", [Self.token(.limit, "\(row.limit) titles")])) }
        if titleIsCustom, let title = Self.trimmedOrNil(widget.title) {
            clauses.append(Self.clause("called", [Self.token(.title, "\u{201C}\(title)\u{201D}")]))
        }
        return clauses
    }

    /// The source as the sentence names it.
    private var sourcePart: Part {
        let text: String
        switch row.source {
        case .addonCatalog(var reference):
            // The genre has its own token, so the catalog is named without it.
            reference.genre = nil
            text = manager.describe(.addonCatalog(reference))
        case .traktList(let list): text = list.listName
        case .traktFeed(let feed): text = feed.title
        case .tmdbDiscover, .unsupported: text = "Source"
        }
        return Self.token(.source, text, removable: false)
    }

    /// The genre a catalog is filtered to, or nil when it is not.
    private var catalogGenreName: String? {
        guard case .addonCatalog(let reference) = row.source else { return nil }
        return Self.trimmedOrNil(reference.genre)
    }

    // MARK: Pills

    /// The settings strip: the source first, then the settings of the source, then the title, items, style and card options.
    var pills: [Pill] {
        var list = [sourcePill]
        switch row.source {
        case .tmdbDiscover(let query):
            list += tmdbPills(query)
        case .addonCatalog:
            if !catalogGenres.isEmpty {
                list.append(Pill(field: .catalogGenre, title: "Genre", value: catalogGenreName ?? "All", systemImage: "theatermasks",
                                 isEnabled: true))
            }
        case .traktList:
            list.append(Pill(field: .traktSort, title: "Sort", value: traktSort?.title ?? "List Default",
                             systemImage: "arrow.up.arrow.down", isEnabled: true))
        case .traktFeed, .unsupported:
            break
        }
        return list + commonPills
    }

    private var sourcePill: Pill {
        let value: String
        switch row.source {
        case .tmdbDiscover: value = "TMDB"
        case .addonCatalog: value = manager.describe(row.source).components(separatedBy: " · ").last ?? ""
        case .traktList, .traktFeed: value = "Trakt"
        case .unsupported: value = "Choose"
        }
        return Pill(field: .source, title: "Source", value: value, systemImage: "square.stack.3d.up", isEnabled: true)
    }

    /// The pills of a TMDB list. A filter the query cannot use is listed but disabled, with the reason as its value.
    private func tmdbPills(_ query: TMDbDiscoverQuery) -> [Pill] {
        let unavailable = query.isTrending ? "Not with Trending" : "Movies only"
        func filterPill(_ field: Field, _ title: String, _ image: String, _ filter: TMDbDiscoverQuery.Filter, _ value: String) -> Pill {
            let enabled = query.supports(filter)
            return Pill(field: field, title: title, value: enabled ? value : unavailable, systemImage: image, isEnabled: enabled)
        }
        return [
            Pill(field: .ordering, title: "Order", value: query.ordering.title, systemImage: "arrow.up.arrow.down", isEnabled: true),
            filterPill(.period, "Period", "calendar", .period, query.period?.title ?? "Any time"),
            filterPill(.genres, "Genres", "theatermasks", .genres, Self.listValue(query.genres, none: "Any")),
            filterPill(.keywords, "Keywords", "tag", .keywords, Self.listValue(query.keywords, none: "Any")),
            filterPill(.excludedKeywords, "Exclude", "tag.slash", .excludedKeywords, Self.listValue(query.excludedKeywords, none: "None")),
            filterPill(.score, "Rating", "star", .score, Self.scoreText(query) ?? "Any"),
            filterPill(.votes, "IMDb Votes", "person.3", .votes, query.minimumVotes.map { "\($0)+" } ?? "Any"),
            filterPill(.language, "Language", "globe", .language, query.language.map(Self.languageName) ?? "Any"),
            filterPill(.runtime, "Runtime", "clock", .runtime, Self.runtimeText(query) ?? "Any"),
            filterPill(.release, "Release", "calendar.badge.clock", .release, Self.releaseText(query) ?? "Any"),
            filterPill(.providers, "Providers", "play.tv", .providers, Self.listValue(query.providers, none: "Any")),
            filterPill(.region, "Region", "mappin.and.ellipse", .region, Self.regionName(query.region ?? deviceRegion)),
            filterPill(.cast, "Cast", "person.2", .cast, Self.listValue(query.cast, none: "Any")),
            filterPill(.crew, "Crew", "megaphone", .crew, Self.listValue(query.crew, none: "Any")),
            filterPill(.companies, "Companies", "building.2", .companies, Self.listValue(query.companies, none: "Any")),
        ]
    }

    /// The title, items, style and card options, which every source has, in this order.
    private var commonPills: [Pill] {
        let cards = "\(row.presentation.aspectRatio.rawValue.capitalized) · \(row.presentation.cardStyle.rawValue.capitalized)"
        return [
            Pill(field: .title, title: "Title", value: customTitle.isEmpty ? "Automatic" : customTitle, systemImage: "textformat",
                 isEnabled: true),
            Pill(field: .limit, title: "Items", value: "\(row.limit)", systemImage: "number", isEnabled: true),
            Pill(field: .style, title: "Style", value: style.rawValue, systemImage: "rectangle.3.group", isEnabled: true),
            Pill(field: .cards, title: "Cards", value: cards, systemImage: "rectangle.portrait", isEnabled: true),
            Pill(field: .posters, title: "Posters", value: row.presentation.usesHeroPosters == true ? "Hero artwork"
                 : row.presentation.usesBetterPosters ? "Better Posters" : row.presentation.usesHeroPosters == false ? "Standard" : "Default",
                 systemImage: "photo.artframe", isEnabled: true),
            Pill(field: .shuffle, title: "Shuffle", value: Self.shuffleText(row.shuffle), systemImage: "shuffle", isEnabled: true),
            Pill(field: .randomSource, title: "Random Source", value: Self.randomSourceText(row.randomSource), systemImage: "dice",
                 isEnabled: true),
        ]
    }

    /// A random source in a few words: "Off", "All Sources", "All except 2", "3 Sources".
    static func randomSourceText(_ random: RandomSource?) -> String {
        guard let random else { return "Off" }
        if random.usesAllSources { return random.excluded.isEmpty ? "All Sources" : "All except \(random.excluded.count)" }
        return random.sources.count == 1 ? "1 Source" : "\(random.sources.count) Sources"
    }

    /// A source a random source can pick, with the name and the line under it that the list shows.
    struct RandomSourceOption: Identifiable, Hashable, Sendable {
        let source: WidgetSource
        let title: String
        let subtitle: String

        var id: WidgetSource { source }
    }

    /// Every source a random source can pick from: the browsable catalogs of the installed addons, then Trakt's feeds once Trakt has a
    /// client ID.
    var randomSourceOptions: [RandomSourceOption] {
        manager.catalogChoices.map { RandomSourceOption(source: .addonCatalog($0.reference), title: $0.title, subtitle: $0.addonName) }
            + manager.randomTraktFeeds.map { RandomSourceOption(source: .traktFeed($0), title: $0.title, subtitle: "Trakt") }
    }

    /// Turns the random source on (picking from every source, or keeping its sources) or off.
    func setRandomSource(_ random: RandomSource?) {
        updateRow { $0.randomSource = random }
    }

    /// Puts a source in the random source's pick or takes it out. From Off, the source becomes the only one picked. See
    /// `RandomSource.toggle` for picking from every source.
    func toggleRandomSource(_ source: WidgetSource) {
        let all = randomSourceOptions.map(\.source)
        updateRow { row in
            guard var random = row.randomSource else {
                row.randomSource = RandomSource(sources: [source])
                return
            }
            random.toggle(source, among: all)
            row.randomSource = random
        }
    }

    /// When the random source picks again.
    func setRandomSourceSchedule(_ schedule: WidgetShuffle) {
        updateRow { row in
            guard var random = row.randomSource else { return }
            random.schedule = schedule
            row.randomSource = random
        }
    }

    /// A shuffle schedule in a few words: "Daily", "Every 1 to 6 hours". Nil is the widgets page's setting. `compact` is the shorter
    /// wording a menu beside a row's title has room for on one line.
    static func shuffleText(_ shuffle: WidgetShuffle?, compact: Bool = false) -> String {
        switch shuffle {
        case nil: "Like Other Widgets"
        case .off?: "Off"
        case .everyOpen?: compact ? "Every Visit" : "Every Time Home Opens"
        case .hourly?: "Hourly"
        case .daily?: "Daily"
        case .randomTimes(let low, let high)?: compact ? "Every \(low)–\(high) Hours" : "At Random, Every \(low) to \(high) Hours"
        }
    }
}
