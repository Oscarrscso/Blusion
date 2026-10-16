import Foundation

/// What a search typed as a description asks for ("a dark, atmospheric sci-fi film from before 2010 with great reviews"), as the
/// on-device model or the keyword reader understands it. It becomes a TMDb discover query, so every title it finds is a real one.
public struct DescribedSearch: Sendable, Equatable {
    /// Films, series, or nil for either.
    public var kind: TMDbDiscoverQuery.Kind?
    /// Genre names such as "Science Fiction" or "thriller", read with the widgets' genre table.
    public var genres: [String]
    public var excludedGenres: [String]
    public var earliestYear: Int?
    public var latestYear: Int?
    /// Moods and themes, such as "dark" or "time travel": looked up as TMDb keywords, any of which may match.
    public var moods: [String]
    /// TMDb's community score, 0 to 10.
    public var minimumScore: Double?
    public var minimumRuntime: Int?
    public var maximumRuntime: Int?

    public init(kind: TMDbDiscoverQuery.Kind? = nil, genres: [String] = [], excludedGenres: [String] = [], earliestYear: Int? = nil,
                latestYear: Int? = nil, moods: [String] = [], minimumScore: Double? = nil, minimumRuntime: Int? = nil,
                maximumRuntime: Int? = nil) {
        self.kind = kind
        self.genres = genres
        self.excludedGenres = excludedGenres
        self.earliestYear = earliestYear
        self.latestYear = latestYear
        self.moods = moods
        self.minimumScore = minimumScore
        self.minimumRuntime = minimumRuntime
        self.maximumRuntime = maximumRuntime
    }

    /// The most moods looked up as keywords: each is one TMDb request.
    public static let maxMoods = 3

    /// Whether nothing was understood: such a description finds nothing better than the title search beside it.
    public var isEmpty: Bool {
        genres.isEmpty && excludedGenres.isEmpty && earliestYear == nil && latestYear == nil && moods.isEmpty && minimumScore == nil
            && minimumRuntime == nil && maximumRuntime == nil
    }

    /// The TMDb query, with the moods given as the keywords TMDb found for them. Genres TMDb does not have for the kind are dropped; a
    /// score asks for enough votes that the score means something. Pure: nothing is requested.
    public func query(keywords: [TMDbDiscoverQuery.Named]) -> TMDbDiscoverQuery {
        let kind = kind ?? .movie
        func named(_ names: [String]) -> [TMDbDiscoverQuery.Named] {
            var found: [TMDbDiscoverQuery.Named] = []
            for name in names {
                guard let genre = TMDbDiscoverQuery.genre(named: name, kind: kind), !found.contains(genre) else { continue }
                found.append(genre)
            }
            return found
        }
        var earliest = earliestYear
        var latest = latestYear
        if let from = earliest, let to = latest, from > to { (earliest, latest) = (to, from) }
        // Both kinds are asked for only when every genre is the same one for films and TV: discover asks TV with the films' genre ids,
        // and TV has none for science fiction, thriller, horror and others.
        let sameForBoth = (genres + excludedGenres).allSatisfy {
            TMDbDiscoverQuery.genre(named: $0, kind: .movie)?.id == TMDbDiscoverQuery.genre(named: $0, kind: .series)?.id
        }
        // A score given out of 100 is read out of 10.
        let score = minimumScore.map { $0 > 10 ? $0 / 10 : $0 }
        return TMDbDiscoverQuery(kind: kind, ordering: .popular, genres: named(genres), keywords: Array(keywords.prefix(Self.maxMoods)),
                                 minimumScore: score.map { min(max($0, 0), 10) },
                                 minimumVotes: minimumScore == nil ? 50 : 300,
                                 minimumRuntime: minimumRuntime, maximumRuntime: maximumRuntime,
                                 releasedFrom: earliest.map { "\($0)-01-01" }, releasedTo: latest.map { "\($0)-12-31" },
                                 excludedGenres: named(excludedGenres), spansBothKinds: self.kind == nil && sameForBoth)
    }
}

// MARK: - Reading a description without the model

extension DescribedSearch {
    /// Whether the text reads like a description rather than a title: four words or more, with at least two words a description uses
    /// ("film", "from", "before", "with", a genre, a mood, a decade). One alone is not enough, so titles such as "The Dark Knight Rises"
    /// or "War of the Worlds" stay title searches.
    public static func readsLikeDescription(_ text: String) -> Bool {
        let words = words(text)
        guard words.count >= 4 else { return false }
        let joined = " " + words.joined(separator: " ") + " "
        let cues = words.filter { descriptionWords.contains($0) || moodWords.contains($0) || decade($0) != nil }.count
            + TMDbDiscoverQuery.genreNames(in: joined).count
        return cues >= 2
    }

    /// The filters a description names, read word by word: films or series, genres, a decade or "before/after/since" a year, "great
    /// reviews", "under two hours", and mood words. Used where the on-device model is not available.
    public static func reading(_ text: String) -> DescribedSearch {
        let words = words(text)
        let joined = " " + words.joined(separator: " ") + " "
        var search = DescribedSearch()
        let namesTV = words.contains(where: { ["tv", "series", "show", "shows", "television"].contains($0) })
        let namesFilms = words.contains(where: { ["movie", "movies", "film", "films"].contains($0) })
        search.kind = namesTV == namesFilms ? (namesTV ? nil : .movie) : (namesTV ? .series : .movie)
        search.genres = TMDbDiscoverQuery.genreNames(in: joined)
        for (index, word) in words.enumerated() {
            if let start = decade(word) {
                search.earliestYear = start
                search.latestYear = start + 9
            } else if let year = Int(word), (1900...2100).contains(year), index > 0 {
                switch words[index - 1] {
                case "before", "pre": search.latestYear = year - 1
                case "after", "since", "post": search.earliestYear = year + (words[index - 1] == "after" ? 1 : 0)
                case "from", "in": search.earliestYear = year; search.latestYear = year
                default: break
                }
            }
        }
        if joined.contains(" great reviews ") || joined.contains(" good reviews ") || joined.contains(" highly rated ")
            || words.contains(where: { ["acclaimed", "masterpiece", "best"].contains($0) }) {
            search.minimumScore = 7.5
        }
        if joined.contains(" under two hours ") || joined.contains(" under 2 hours ") || joined.contains(" short ") {
            search.maximumRuntime = 120
        } else if let index = words.firstIndex(of: "under"), index + 2 < words.count, let minutes = Int(words[index + 1]),
                  ["minutes", "mins", "min"].contains(words[index + 2]) {
            search.maximumRuntime = minutes
        }
        search.moods = Array(words.filter { moodWords.contains($0) }.prefix(maxMoods))
        return search
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().filter { $0 != "'" && $0 != "\u{2019}" }.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The first year of "1990s" or "90s", else nil.
    private static func decade(_ word: String) -> Int? {
        guard word.hasSuffix("s"), let value = Int(word.dropLast()), value % 10 == 0 else { return nil }
        switch word.count {
        case 3: return value >= 30 ? 1900 + value : 2000 + value
        case 5 where value >= 1900: return value
        default: return nil
        }
    }

    private static let descriptionWords: Set<String> = [
        "film", "films", "movie", "movies", "show", "shows", "series", "something", "anything", "before", "after", "since", "with",
        "about", "where", "set", "reviews", "rated", "featuring", "starring", "under", "less", "more", "vibe", "vibes", "feel",
    ]

    /// Mood words the keyword reader passes on as TMDb keywords.
    private static let moodWords: Set<String> = [
        "dark", "atmospheric", "gritty", "bleak", "uplifting", "heartwarming", "funny", "scary", "creepy", "tense", "violent", "slow",
        "cerebral", "twisty", "surreal", "nostalgic", "melancholic", "melancholy", "cozy", "quirky", "epic", "dystopian", "psychological",
    ]
}

// MARK: - Genres by name

extension TMDbDiscoverQuery {
    /// The genre a name means for a kind, read with the widgets' table ("sci-fi", "Science Fiction" and "scifi" are all one), or TMDb's
    /// genre of that exact name. Nil when the kind has no such genre.
    public static func genre(named name: String, kind: Kind) -> Named? {
        let phrase = " " + phraseWords(name).joined(separator: " ") + " "
        for clue in genreClues where clue.phrases.contains(where: { phrase.contains(" \($0) ") }) {
            return kind == .movie ? clue.movie : clue.series
        }
        let wanted = name.lowercased()
        return genreClues.lazy.compactMap { kind == .movie ? $0.movie : $0.series }.first { $0.name.lowercased() == wanted }
    }

    /// The genre names a text uses, in the table's order, as films name them.
    static func genreNames(in text: String) -> [String] {
        genreClues.filter { clue in clue.phrases.contains { text.contains(" \($0) ") } }.compactMap { $0.movie?.name }
    }

    /// Whether a text names any genre.
    static func namesGenre(in text: String) -> Bool { !genreNames(in: text).isEmpty }

    private static func phraseWords(_ text: String) -> [String] {
        text.lowercased().filter { $0 != "'" && $0 != "\u{2019}" }.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
