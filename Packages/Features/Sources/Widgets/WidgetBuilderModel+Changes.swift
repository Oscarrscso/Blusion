import Foundation
import Observation
import StremioKit

extension WidgetBuilderModel {
    // MARK: Selecting

    /// Opens a setting's editor, or closes it when it is already open. A setting whose pill is disabled cannot be opened.
    func select(_ field: Field) {
        if selectedField == field {
            selectedField = nil
            return
        }
        guard isEnabled(field) else { return }
        selectedField = field
    }

    func isEnabled(_ field: Field) -> Bool {
        pills.first(where: { $0.field == field })?.isEnabled == true
    }

    // MARK: Changes

    /// Sets the movie-or-series choice of a TMDB list.
    func setKind(_ kind: TMDbDiscoverQuery.Kind) {
        updateQuery { query in
            // Genre ids differ between movies and series.
            query.genres = TMDbDiscoverQuery.convertingGenres(query.genres, from: query.kind, to: kind)
            query.excludedGenres = TMDbDiscoverQuery.convertingGenres(query.excludedGenres, from: query.kind, to: kind)
            query.kind = kind
        }
    }

    /// Sets the ordering of a TMDB list. A trending ordering drops the filters a trending list cannot use.
    func setOrdering(_ ordering: TMDbDiscoverQuery.Ordering) {
        updateQuery { $0.ordering = ordering }
    }

    /// Applies a change to a TMDB list's query. Filters the query cannot use are dropped afterwards. A period and explicit release dates
    /// replace each other: setting one clears the other. A blank language or region is stored as nil. Does nothing for other sources.
    func updateQuery(_ change: (inout TMDbDiscoverQuery) -> Void) {
        guard let current = query else { return }
        var edited = current
        change(&edited)
        if edited.minimumScore != current.minimumScore || edited.maximumScore != current.maximumScore
            || edited.minimumVotes != current.minimumVotes {
            // A vote count set here is IMDb's, as the editor says, even on a list a search made with TMDb's; so is a score without the app's rating.
            edited.usesTMDbScores = false
        }
        let periodChanged = edited.period != current.period
        let releaseChanged = edited.releasedFrom != current.releasedFrom || edited.releasedTo != current.releasedTo
        let releaseIsSet = edited.releasedFrom != nil || edited.releasedTo != nil
        if periodChanged, edited.period != nil {
            edited.releasedFrom = nil
            edited.releasedTo = nil
        } else if releaseChanged, releaseIsSet {
            edited.period = nil
        }
        edited.language = Self.trimmedOrNil(edited.language)
        edited.region = Self.trimmedOrNil(edited.region)?.uppercased()
        var configuration = row
        configuration.source = .tmdbDiscover(edited.removingUnsupportedFilters())
        writeRow(configuration)
    }

    /// Adds a genre, keyword, excluded keyword, provider, cast member, crew member or company to its list, or takes it off when it
    /// is there. A keyword added to the keywords is taken off the excluded keywords, and the other way round. Does nothing for other
    /// fields.
    func toggle(_ value: TMDbDiscoverQuery.Named, in field: Field) {
        updateQuery { query in
            switch field {
            case .genres: Self.toggle(value, in: &query.genres)
            case .keywords:
                if Self.toggle(value, in: &query.keywords) { query.excludedKeywords.removeAll { $0.id == value.id } }
            case .excludedKeywords:
                if Self.toggle(value, in: &query.excludedKeywords) { query.keywords.removeAll { $0.id == value.id } }
            case .providers: Self.toggle(value, in: &query.providers)
            case .cast: Self.toggle(value, in: &query.cast)
            case .crew: Self.toggle(value, in: &query.crew)
            case .companies: Self.toggle(value, in: &query.companies)
            default: break
            }
        }
    }

    /// Applies a change to the row's items, presentation or other row settings. The limit stays within 1...100.
    func updateRow(_ change: (inout RowConfiguration) -> Void) {
        var configuration = row
        change(&configuration)
        writeRow(configuration)
    }

    /// Makes the widget a TMDB list of popular movies when its source is something else. A TMDB list that is already set is kept.
    func useTMDbList() {
        guard query == nil else { return }
        replaceSource(.tmdbDiscover(TMDbDiscoverQuery()))
    }

    /// Puts a catalog or Trakt source, chosen in a picker, into the widget. A Trakt sort chosen before the list is applied to it.
    func setSource(_ source: WidgetSource) {
        guard case .traktList(var list) = source, let sort = pendingTraktSort else {
            replaceSource(source)
            return
        }
        list.sort = sort
        replaceSource(.traktList(list))
    }

    /// Filters a catalog to one of its genres. Nil or blank takes the filter away.
    func setCatalogGenre(_ genre: String?) {
        guard case .addonCatalog(var reference) = row.source else { return }
        reference.genre = Self.trimmedOrNil(genre)
        replaceSource(.addonCatalog(reference))
    }

    /// Sorts a Trakt list. Before a Trakt list is chosen, the sort is kept and applied when it is.
    func setTraktSort(_ sort: TraktListSort?) {
        pendingTraktSort = sort
        guard case .traktList(var list) = row.source else { return }
        list.sort = sort
        replaceSource(.traktList(list))
    }

    /// Takes one value away: a list entry, or the filter, sort, region, genre, title or item count the token shows. Tokens that cannot
    /// be removed do nothing.
    func remove(_ token: Token) {
        guard token.isRemovable else { return }
        switch token.field {
        case .genres, .keywords, .excludedKeywords, .providers, .cast, .crew, .companies:
            guard let id = token.valueID else { return }
            updateQuery { Self.removeNamed(id, from: token.field, in: &$0) }
        case .period: updateQuery { $0.clear(.period) }
        case .score: updateQuery { $0.clear(.score) }
        case .votes: updateQuery { $0.clear(.votes) }
        case .language: updateQuery { $0.clear(.language) }
        case .runtime: updateQuery { $0.clear(.runtime) }
        case .release: updateQuery { $0.clear(.release) }
        case .region: updateQuery { $0.clear(.region) }
        case .catalogGenre: setCatalogGenre(nil)
        case .traktSort: setTraktSort(nil)
        case .limit: updateRow { $0.limit = 20 }
        case .title: setCustomTitle("")
        default: break
        }
    }

    // MARK: Saving

    /// Adds a new widget or replaces the saved one. A blank title becomes the automatic one. Does nothing while `canCommit` is false.
    func commit() async {
        guard canCommit else { return }
        var saved = widget
        if Self.trimmedOrNil(saved.title) == nil { saved.title = autoTitle }
        switch mode {
        case .create: await manager.add(saved)
        case .edit: await manager.update(saved)
        }
    }

    /// Removes the widget from Home.
    func removeWidget() async {
        await manager.remove(id: widget.id)
    }
}
