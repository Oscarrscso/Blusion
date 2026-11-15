import Foundation
import Observation
import StremioKit

extension WidgetBuilderModel {
    // MARK: Loading and lookups

    /// Reads whether a TMDb token is saved, which settles `needsTMDbToken`. Call it when the screen appears and after the source changes.
    func load() async {
        hasSavedToken = await lookups.hasToken()
        needsTMDbToken = query != nil && !hasSavedToken
    }

    /// Loads the genres of the query's kind, or the watch providers of its kind and region, unless they are already loaded for it.
    /// Says why when they cannot be loaded. Does nothing for other fields and sources.
    func loadOptions(for field: Field) async {
        guard let query else { return }
        switch field {
        case .genres:
            // The message is shared by the fields, so one already loaded clears another's.
            guard loadedOptions[field] != query.kind.rawValue else { optionsMessage = nil; return }
            genreOptions = []
            await perform {
                genreOptions = try await lookups.genres(query.kind)
                loadedOptions[field] = query.kind.rawValue
            }
        case .providers:
            let region = query.region ?? deviceRegion
            let key = "\(query.kind.rawValue)/\(region)"
            guard loadedOptions[field] != key else { optionsMessage = nil; return }
            providerOptions = []
            await perform {
                providerOptions = try await lookups.providers(query.kind, region)
                loadedOptions[field] = key
            }
        default:
            return
        }
    }

    /// Runs one option load with the progress flag set. Says why when there is no token or the request fails.
    private func perform(_ work: () async throws -> Void) async {
        optionsMessage = nil
        isLoadingOptions = true
        defer { isLoadingOptions = false }
        guard await lookups.hasToken() else {
            optionsMessage = Self.noTokenMessage
            return
        }
        do {
            try await work()
        } catch {
            // A panel closed while it loaded cancels the load; that isn't TMDB failing.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            optionsMessage = Self.unreachableMessage
        }
    }

    /// The matches for the text typed into a field's search: keywords for the keyword fields, people for cast and crew, companies for
    /// companies. Empty for blank text, for fields without a search and when the search fails.
    func suggestions(for field: Field, matching text: String) async -> [TMDbDiscoverQuery.Named] {
        guard let term = Self.trimmedOrNil(text) else { return [] }
        do {
            switch field {
            case .keywords, .excludedKeywords: return try await lookups.keywords(term)
            case .cast, .crew: return try await lookups.people(term)
            case .companies: return try await lookups.companies(term)
            default: return []
            }
        } catch {
            return []
        }
    }

    /// The languages whose name or code contains the text, by name. Blank text gives them all.
    static func languages(matching text: String, locale: Locale = .current) -> [(code: String, name: String)] {
        let codes = Locale.LanguageCode.isoLanguageCodes.map(\.identifier).filter { $0.count == 2 }
        let named = codes.compactMap { code -> (code: String, name: String)? in
            guard let name = locale.localizedString(forLanguageCode: code) else { return nil }
            return (code: code, name: name)
        }
        return matching(named, text)
    }

    /// The regions whose name or code contains the text, by name. Blank text gives them all.
    static func regions(matching text: String, locale: Locale = .current) -> [(code: String, name: String)] {
        let codes = Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }
        let named = codes.compactMap { code -> (code: String, name: String)? in
            guard let name = locale.localizedString(forRegionCode: code) else { return nil }
            return (code: code, name: name)
        }
        return matching(named, text)
    }

    // MARK: Helpers

    /// Writes the row back and keeps the rest in step: the title follows the source unless it is custom, a selection that no longer
    /// applies is dropped, and `needsTMDbToken` is refreshed.
    func writeRow(_ configuration: RowConfiguration) {
        var configuration = configuration
        configuration.limit = min(max(configuration.limit, 1), 100)
        widget.content = (WidgetStyle(widget.content) ?? .row).content(configuration)
        if !titleIsCustom { widget.title = autoTitle }
        if let field = selectedField, !isEnabled(field) { selectedField = nil }
        needsTMDbToken = query != nil && !hasSavedToken
    }

    /// Puts a source into the row, keeping its items and presentation.
    func replaceSource(_ source: WidgetSource) {
        var configuration = row
        configuration.source = source
        writeRow(configuration)
    }

    /// The row, spotlight or banner a widget holds; nil for the other kinds.
    static func rowOf(_ content: HomeWidget.Content) -> RowConfiguration? {
        switch content {
        case .row(let row), .hero(let row), .banner(let row): return row
        case .collection, .continueWatching, .blusionTV, .unsupported: return nil
        }
    }

    /// The text trimmed of spaces and new lines, or nil when nothing is left.
    static func trimmedOrNil(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// A token of the sentence. Its id is the field's name, with the value's id when the field holds several values.
    static func token(_ field: Field, _ text: String, valueID: Int? = nil, removable: Bool = true) -> Part {
        let id = valueID.map { "\(field.rawValue):\($0)" } ?? field.rawValue
        return .token(Token(id: id, field: field, text: text, isRemovable: removable, valueID: valueID))
    }

    /// A clause of the sentence: its lead word, then its tokens.
    static func clause(_ lead: String, _ tokens: [Part]) -> [Part] {
        [.text(lead)] + tokens
    }

    /// The pieces with a comma between neighbours, and "and" before the last one.
    static func joined(_ pieces: [[Part]]) -> [Part] {
        var parts: [Part] = []
        for (index, piece) in pieces.enumerated() {
            if index > 0 { parts.append(.text(index == pieces.count - 1 ? "and" : ",")) }
            parts += piece
        }
        return parts
    }

    /// Removes the entry with the id from the query's list for `field`.
    static func removeNamed(_ id: Int, from field: Field, in query: inout TMDbDiscoverQuery) {
        switch field {
        case .genres: query.genres.removeAll { $0.id == id }
        case .keywords: query.keywords.removeAll { $0.id == id }
        case .excludedKeywords: query.excludedKeywords.removeAll { $0.id == id }
        case .providers: query.providers.removeAll { $0.id == id }
        case .cast: query.cast.removeAll { $0.id == id }
        case .crew: query.crew.removeAll { $0.id == id }
        case .companies: query.companies.removeAll { $0.id == id }
        default: break
        }
    }

    /// Adds the value to the list when it is missing, removes it when it is there. True when it was added.
    @discardableResult
    static func toggle(_ value: TMDbDiscoverQuery.Named, in list: inout [TMDbDiscoverQuery.Named]) -> Bool {
        if list.contains(where: { $0.id == value.id }) {
            list.removeAll { $0.id == value.id }
            return false
        }
        list.append(value)
        return true
    }

    /// The entries whose name or code contains the text, sorted by name. Blank text keeps them all.
    private static func matching(_ entries: [(code: String, name: String)], _ text: String) -> [(code: String, name: String)] {
        let term = (trimmedOrNil(text) ?? "").lowercased()
        return entries
            .filter { term.isEmpty || $0.name.lowercased().contains(term) || $0.code.lowercased().contains(term) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The value of a list filter in a pill: the first name, with "+n" for the others.
    static func listValue(_ names: [TMDbDiscoverQuery.Named], none: String) -> String {
        guard let first = names.first else { return none }
        return names.count == 1 ? first.name : "\(first.name) +\(names.count - 1)"
    }

    /// The ordering in a sentence, such as "Trending this week".
    static func orderingPhrase(_ ordering: TMDbDiscoverQuery.Ordering) -> String {
        switch ordering {
        case .popular: return "Popular"
        case .trendingToday: return "Trending today"
        case .trendingThisWeek: return "Trending this week"
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        }
    }

    /// The period in a sentence, such as "the last 3 months".
    static func periodPhrase(_ period: TMDbDiscoverQuery.Period) -> String {
        switch period {
        case .lastMonth: return "the last month"
        case .last3Months: return "the last 3 months"
        case .thisYear: return "this year"
        case .lastYear: return "last year"
        case .last5Years: return "the last 5 years"
        case .last10Years: return "the last 10 years"
        }
    }

    /// The score bounds as read in a sentence: "7+", "up to 6" or "7 to 9". Nil when no bound is set.
    static func scoreText(_ query: TMDbDiscoverQuery) -> String? {
        switch (query.minimumScore, query.maximumScore) {
        case let (low?, high?): return "\(number(low)) to \(number(high))"
        case let (low?, nil): return "\(number(low))+"
        case let (nil, high?): return "up to \(number(high))"
        case (nil, nil): return nil
        }
    }

    /// The runtime bounds in minutes: "90+ min", "under 120 min" or "90 to 120 min". Nil when no bound is set.
    static func runtimeText(_ query: TMDbDiscoverQuery) -> String? {
        switch (query.minimumRuntime, query.maximumRuntime) {
        case let (low?, high?): return "\(low) to \(high) min"
        case let (low?, nil): return "\(low)+ min"
        case let (nil, high?): return "under \(high) min"
        case (nil, nil): return nil
        }
    }

    /// The release years: "2010 to 2020", "in 2015", "from 2010" or "up to 2020". Nil when no year is set.
    static func releaseText(_ query: TMDbDiscoverQuery) -> String? {
        ReleaseYears.text(from: query.releasedFrom, to: query.releasedTo)
    }

    /// A score or minute without a trailing ".0": 7 for 7.0, 7.5 for 7.5.
    private static func number(_ value: Double) -> String {
        if let whole = Int(exactly: value) { return String(whole) }
        return String(value)
    }

    /// The language's name in the current locale, or its code in capitals when the locale has no name for it.
    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    /// The region's name in the current locale, or its code in capitals when the locale has no name for it.
    static func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code.uppercased()
    }
}
