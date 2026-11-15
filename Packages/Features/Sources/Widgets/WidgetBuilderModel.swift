import Foundation
import Observation
import StremioKit

/// The widget builder screen's state: the row, spotlight or banner being made or changed, the sentence that describes it, the pills
/// that open its settings, and the changes each setting makes. It has no views, so the host tests cover it.
@MainActor
@Observable
final class WidgetBuilderModel {
    enum Mode: Sendable { case create, edit }

    /// One setting of a widget. Each is a pill in the strip; one that has a value is also a token in the sentence.
    enum Field: String, CaseIterable, Identifiable, Sendable {
        case source, ordering, period, genres, keywords, excludedKeywords, score, votes, language, runtime, release, providers, region,
             cast, crew, companies, catalogGenre, traktSort, title, limit, style, cards, posters, shuffle, randomSource
        var id: String { rawValue }
    }

    /// A setting in the strip: its name, its current value in a few words, and whether the list can use it right now.
    struct Pill: Identifiable, Equatable, Sendable {
        let field: Field
        /// "Genres".
        let title: String
        /// The current value in a few words: "Any", "Animation +1", "7+".
        let value: String
        let systemImage: String
        /// False for a filter the list cannot use right now; `value` then says why ("Not with Trending", "Movies only").
        let isEnabled: Bool
        var id: Field { field }
    }

    /// A tappable piece of the sentence. Tapping it opens its field; a removable one also has a cross that takes the value away.
    struct Token: Identifiable, Hashable, Sendable {
        /// Unique in the sentence: the field's raw value, plus `:<valueID>` for one of several values.
        let id: String
        let field: Field
        let text: String
        let isRemovable: Bool
        /// The genre, keyword, person, company or provider this token stands for, when the field holds several.
        let valueID: Int?
    }

    /// One piece of the sentence: plain words, the movie-or-series dropdown, or a token.
    enum Part: Hashable, Sendable {
        /// Plain words of the sentence. A piece may hold several words.
        case text(String)
        /// The movie-or-series choice, drawn as a dropdown.
        case kind(TMDbDiscoverQuery.Kind)
        case token(Token)
    }

    /// A part of the sentence with its position, which gives a view a stable identity for each part.
    struct SentenceItem: Identifiable, Hashable, Sendable {
        let id: Int
        let part: Part
    }

    /// Whether the screen makes a new widget or changes a saved one.
    let mode: Mode
    /// The widget as it would be saved. A widget that is not a row, spotlight or banner is shown as an empty row with no source.
    var widget: HomeWidget
    /// The setting whose editor is open, if any.
    var selectedField: Field?
    /// True when the source is a TMDB list and no TMDb token is saved, so the list cannot be read.
    var needsTMDbToken = false
    /// The genres of the query's kind, once loaded.
    var genreOptions: [TMDbDiscoverQuery.Named] = []
    /// The watch providers of the query's kind and region, once loaded.
    var providerOptions: [TMDbDiscoverQuery.Named] = []
    var isLoadingOptions = false
    /// One plain sentence when the options could not be loaded.
    var optionsMessage: String?
    /// The device's region, uppercased: the region a provider list uses when the query names none.
    let deviceRegion: String

    let manager: WidgetsManagerViewModel
    let lookups: WidgetBuilderLookups
    /// False while the title follows the source's name.
    var titleIsCustom: Bool
    /// A Trakt sort chosen before the list is: it is applied when a Trakt list is chosen.
    var pendingTraktSort: TraktListSort?
    /// Whether the saved settings had a TMDb token at the last `load()`. Assumed true until then, so nothing warns early.
    var hasSavedToken = true
    /// The key each option list was last loaded for, kept only after a load succeeds.
    var loadedOptions: [Field: String] = [:]

    static let noTokenMessage = "Add a TMDB Read Access Token in Settings to choose from TMDB's lists."
    static let unreachableMessage = "TMDB couldn't be reached."

    /// The builder for a new widget (a TMDB list of popular movies in `style` unless `widget` is given) or for a saved one. `region` is the
    /// device's region, which the region and provider pills use when the query names none.
    convenience init(mode: Mode, widget: HomeWidget? = nil, style: WidgetStyle = .row, manager: WidgetsManagerViewModel,
                            services: AppServices, region: String = Locale.current.region?.identifier ?? "US") {
        self.init(mode: mode, widget: widget, style: style, manager: manager, lookups: .live(services: services), region: region)
    }

    /// The same builder with its TMDb calls supplied, so the tests can answer them without the network.
    init(mode: Mode, widget: HomeWidget?, style: WidgetStyle = .row, manager: WidgetsManagerViewModel, lookups: WidgetBuilderLookups,
         region: String) {
        self.mode = mode
        self.manager = manager
        self.lookups = lookups
        self.deviceRegion = region.uppercased()
        let fallback = HomeWidget(title: "Popular Movies", content: .row(RowConfiguration(source: .tmdbDiscover(TMDbDiscoverQuery()))))
        var shown = widget ?? WidgetStyle.restyled(fallback, as: style)
        if Self.rowOf(shown.content) == nil { shown.content = .row(RowConfiguration(source: .unsupported(kind: ""))) }
        self.widget = shown
        let source = Self.rowOf(shown.content)?.source ?? .unsupported(kind: "")
        // A title is custom when the user named the widget: a blank one, or the source's own name, is not.
        self.titleIsCustom = Self.trimmedOrNil(shown.title) != nil && shown.title != manager.autoTitle(for: source)
    }

    // MARK: Derived values

    /// The row, spotlight or banner being made or changed.
    var row: RowConfiguration { Self.rowOf(widget.content) ?? RowConfiguration(source: .unsupported(kind: "")) }

    /// The query of a TMDB list; nil for any other source.
    var query: TMDbDiscoverQuery? {
        guard case .tmdbDiscover(let query) = row.source else { return nil }
        return query
    }

    /// The widget's style: a row, a spotlight or a banner.
    var style: WidgetStyle { WidgetStyle(widget.content) ?? .row }

    /// Shows the widget in another style, keeping its items and title (see `WidgetStyle.restyled`).
    func setStyle(_ style: WidgetStyle) {
        widget = WidgetStyle.restyled(widget, as: style)
    }

    /// The name the source gives the widget.
    var autoTitle: String { manager.autoTitle(for: row.source) }

    /// The source as the source picker names it: an addon's catalog, or a Trakt list or feed.
    var sourceDescription: String { manager.describe(row.source) }

    /// The title the user typed, or "" while the title follows the source.
    var customTitle: String { titleIsCustom ? widget.title : "" }

    /// Names the widget. Blank text goes back to the automatic title.
    func setCustomTitle(_ text: String) {
        if Self.trimmedOrNil(text) == nil {
            titleIsCustom = false
            widget.title = autoTitle
        } else {
            titleIsCustom = true
            widget.title = text
        }
    }

    var hidesTitle: Bool { widget.hideTitle }

    func setHideTitle(_ hidden: Bool) {
        widget.hideTitle = hidden
    }

    /// False only while the source is unsupported, so there is no source to save.
    var canCommit: Bool {
        if case .unsupported = row.source { return false }
        return true
    }

    /// The item counts on offer, with the widget's own count when it is not one of them.
    var limitChoices: [Int] { Array(Set([5, 10, 15, 20, 30, 40, 50, 75, 100, row.limit])).sorted() }

    /// The genres the widget's catalog offers; empty for any other source.
    var catalogGenres: [String] { manager.genres(for: row.source) }

    /// The Trakt sort of the widget's list, or the sort chosen before a list was.
    var traktSort: TraktListSort? {
        if case .traktList(let list) = row.source { return list.sort }
        return pendingTraktSort
    }
}

/// The TMDb calls the builder makes, as closures so the tests can answer them without the network. `live` makes them with the token
/// saved in Settings.
struct WidgetBuilderLookups: Sendable {
    /// True when a TMDb Read Access Token is saved. The lookups below answer with empty lists when none is.
    var hasToken: @Sendable () async -> Bool
    var genres: @Sendable (TMDbDiscoverQuery.Kind) async throws -> [TMDbDiscoverQuery.Named]
    var keywords: @Sendable (String) async throws -> [TMDbDiscoverQuery.Named]
    var people: @Sendable (String) async throws -> [TMDbDiscoverQuery.Named]
    var companies: @Sendable (String) async throws -> [TMDbDiscoverQuery.Named]
    var providers: @Sendable (TMDbDiscoverQuery.Kind, String) async throws -> [TMDbDiscoverQuery.Named]

    /// The calls made with the token saved in Settings, read again for each call. Without a token `TMDbRatings` sends no request.
    static func live(services: AppServices) -> WidgetBuilderLookups {
        let client = services.client
        let settings = services.settings
        let token: @Sendable () async -> String = {
            let saved = await settings.load()
            return (saved.tmdbReadToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return WidgetBuilderLookups(
            hasToken: { !(await token()).isEmpty },
            genres: { kind in try await TMDbRatings(client: client, readAccessToken: await token()).genres(kind: kind) },
            keywords: { text in try await TMDbRatings(client: client, readAccessToken: await token()).searchKeywords(text) },
            people: { text in try await TMDbRatings(client: client, readAccessToken: await token()).searchPeople(text) },
            companies: { text in try await TMDbRatings(client: client, readAccessToken: await token()).searchCompanies(text) },
            providers: { kind, region in
                try await TMDbRatings(client: client, readAccessToken: await token()).watchProviders(kind: kind, region: region)
            })
    }
}
