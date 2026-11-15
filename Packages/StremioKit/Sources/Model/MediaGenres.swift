import Foundation

/// Shared genre names and comparisons. A title's genres are the ones its page lists; every Genre menu and filter reads them through here.
public enum MediaGenres {
    private static let names: [String: String] = [
        "action": "Action", "adventure": "Adventure", "animation": "Animation", "anime": "Anime",
        "biography": "Biography", "comedy": "Comedy", "crime": "Crime", "documentary": "Documentary",
        "drama": "Drama", "family": "Family", "fantasy": "Fantasy", "filmnoir": "Film-Noir",
        "gameshow": "Game Show", "history": "History", "horror": "Horror", "kids": "Kids",
        "music": "Music", "musical": "Musical", "mystery": "Mystery", "news": "News", "politics": "Politics",
        "reality": "Reality", "romance": "Romance", "sciencefiction": "Science Fiction",
        "short": "Short", "sport": "Sport", "talk": "Talk", "thriller": "Thriller",
        "tvmovie": "TV Movie", "war": "War", "western": "Western",
        "actionadventure": "Action & Adventure", "sciencefictionfantasy": "Sci-Fi & Fantasy",
        "warpolitics": "War & Politics"
    ]

    /// A compound genre and the single genres it groups.
    private static let compounds: [String: [String]] = [
        "actionadventure": ["action", "adventure"],
        "sciencefictionfantasy": ["sciencefiction", "fantasy"],
        "warpolitics": ["war", "politics"]
    ]

    public static func key(_ name: String) -> String {
        let text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
        switch text {
        case "scifi", "sciencefiction": return "sciencefiction"
        case "scififantasy", "scifiandfantasy", "sciencefictionfantasy", "sciencefictionandfantasy": return "sciencefictionfantasy"
        case "actionandadventure": return "actionadventure"
        case "warandpolitics": return "warpolitics"
        case "realitytv": return "reality"
        case "talkshow": return "talk"
        case "sports": return "sport"
        default: return text
        }
    }

    public static func isKnown(_ value: String) -> Bool { names[key(value)] != nil }

    public static func name(_ value: String) -> String {
        names[key(value)] ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalised(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let genreKey = key(value)
            guard !genreKey.isEmpty, seen.insert(genreKey).inserted else { return nil }
            return name(value)
        }
    }

    /// The keys of the single genres a name stands for: itself, or the genres a compound groups.
    public static func parts(_ name: String) -> [String] {
        let genreKey = key(name)
        return compounds[genreKey] ?? (genreKey.isEmpty ? [] : [genreKey])
    }

    /// Whether any of `genres` is the selected genre or shares a single genre with it, so "Action" finds a title listed under
    /// "Action & Adventure" and the other way round.
    public static func contains(_ selected: String, in genres: [String]) -> Bool {
        let wanted = Set(parts(selected))
        guard !wanted.isEmpty else { return false }
        return genres.contains { !wanted.isDisjoint(with: parts($0)) }
    }

    /// `genres` with the ones `selected` finds first, each group in its own order: a title shown for a genre leads with that genre
    /// on its card and on its page, both of which show only the first of its genres.
    public static func leading(_ selected: [String], in genres: [String]) -> [String] {
        let wanted = Set(selected.flatMap { parts($0) })
        guard !wanted.isEmpty else { return genres }
        return genres.filter { !wanted.isDisjoint(with: parts($0)) } + genres.filter { wanted.isDisjoint(with: parts($0)) }
    }

    /// A Genre menu's choices for these genres: each single genre once, compounds as the genres they group, A to Z.
    public static func choices(in genres: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for genre in genres {
            for part in parts(genre) where seen.insert(part).inserted {
                result.append(names[part] ?? genre.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Genre menus exclude catalog orderings, years and curated topics.
    public static func options(of catalog: CatalogDescriptor) -> [String] {
        normalised(catalog.genreOptions.filter { names[key($0)] != nil })
    }

    /// Keep the provider's spelling on the wire. Without the same genre, a catalog's genre that shares a single genre with the selection is its candidate pool.
    public static func option(_ selected: String, in catalog: CatalogDescriptor) -> String? {
        catalog.genreOptions.first { key($0) == key(selected) }
            ?? catalog.genreOptions.first { names[key($0)] != nil && contains(selected, in: [$0]) }
    }
}
