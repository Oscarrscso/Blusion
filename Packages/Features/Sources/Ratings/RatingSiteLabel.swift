import StremioKit

/// The uppercase name drawn in place of a rating pill's logo, in the site's brand colour.
struct RatingSiteName: Equatable, Sendable {
    /// Uppercase site name, such as "IMDB" or "TMDB".
    var text: String
    /// The site's brand colour as "rrggbb".
    var colourHex: String
}

/// How a title-details rating pill names its site. Exactly two sites use coloured text; any other count keeps the logo.
enum RatingSiteLabel {
    /// True when each pill draws `name(for:)` instead of the site's logo.
    static func usesName(siteCount: Int) -> Bool { siteCount == 2 }

    /// The coloured label for `site`. Brand names are fixed spellings, so case does not follow the locale.
    static func name(for site: ReviewSite) -> RatingSiteName {
        RatingSiteName(text: text(for: site), colourHex: colourHex(for: site))
    }

    /// The full site name in uppercase. Long names stay whole and scale down in the pill rather than being abbreviated.
    static func text(for site: ReviewSite) -> String {
        switch site {
        case .imdb: "IMDB"
        case .letterboxd: "LETTERBOXD"
        case .rottenTomatoes: "ROTTEN TOMATOES"
        case .metacritic: "METACRITIC"
        case .tmdb: "TMDB"
        case .myAnimeList: "MYANIMELIST"
        }
    }

    /// The colour of the site's mark. IMDb's yellow is the brand yellow (the icon is a shaded drawing of it); the others are
    /// sampled from the shipped logos: Letterboxd's green dot, the tomato, Metacritic's gold ring, and the bright end of the
    /// TMDB gradient. MyAnimeList's logo fill (`#2E51A2`) is a dark ground, so the name uses that same blue lifted enough to
    /// read on the pill.
    static func colourHex(for site: ReviewSite) -> String {
        switch site {
        case .imdb: "F5C518"
        case .letterboxd: "00E054"
        case .rottenTomatoes: "F8300C"
        case .metacritic: "FFCC00"
        case .tmdb: "00B3E5"
        case .myAnimeList: "5D8BF5"
        }
    }
}
