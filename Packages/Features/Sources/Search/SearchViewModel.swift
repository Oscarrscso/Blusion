import Foundation
import Observation
import StremioKit

/// Search, as one pipeline for every appearance of the screen. A query is answered in stages, none waiting for the next: what is
/// already known gives suggestions at once; after a debounce every searchable addon and TMDb (titles and people) are asked
/// together; and a query that describes what to watch is read into a plan, on device where that needs language understanding, and
/// answered from real TMDb data. An addon failure never hides results from the other sources.
@MainActor
@Observable
final class SearchViewModel {
    struct Section: Identifiable, Equatable {
        let addon: AddonSummary
        var items: [MetaPreview]
        var id: UUID { addon.id }
    }

    /// The results of one content type across every addon: one row on the Search screen.
    struct Group: Identifiable, Equatable {
        let type: String
        let title: String
        var items: [MetaPreview]
        var id: String { type }
    }

    struct Failure: Identifiable, Equatable {
        let addon: AddonSummary
        let error: AddonError
        var id: UUID { addon.id }
        var text: String { "\(addon.name): \(error.shortDescription)" }
    }

    enum Phase: Equatable {
        case idle
        case searching
        case done
    }

    /// Independent of the addon and TMDb search: the described search keeps its spinner until its own work ends.
    var aiPhase: Phase = .idle
    var aiStage: AISearchUpdate.Stage = .interpreting
    var aiIssue: AISearchUpdate.Issue?
    var aiRequestID = UUID()

    /// A category on the idle Search page. `sources` are the movie and series catalogs filtered to the genre, merged when it opens.
    struct GenreShortcut: Identifiable, Hashable, Sendable {
        let name: String
        let sources: [WidgetSource]
        /// Movie/TV still for recognised genres; nil keeps the coloured tile for other addon genres.
        var imageURL: URL?
        var id: String { name.lowercased() }

        init(name: String, sources: [WidgetSource], imageURL: URL? = nil) {
            self.name = name
            self.sources = sources
            self.imageURL = imageURL
        }
    }

    var query = ""
    /// Which results show: everything, one kind of title, or people.
    var scope = SearchScope.all
    /// The words of the last Pick for me, and the plan they stand for.
    var pickQuery: String?
    var pickPlan: AISearchPlan?
    /// Draws the order the picks show in. Changed by each pick.
    var pickSeed = 0
    /// Whether the results are Pick for me's: the titles its choices allow, in an order drawn for each pick.
    var isPickSearch: Bool { pickQuery != nil && term == pickQuery }

    /// Searches for what was chosen, as a plan: no words are read, so no model is asked and the search starts at once. Asked again
    /// for the choices already showing, it draws them in a new order.
    func pick(_ pick: SearchPick) {
        let text = pick.title
        if term == text, isPickSearch, aiPhase == .searching || !describedItems.isEmpty {
            shufflePick()
            return
        }
        stopWork()
        clearFilters()
        scope = .all
        pickSeed = Int.random(in: Int.min...Int.max)
        pickPlan = pick.plan
        pickQuery = text
        query = text
        begin(text)
        submittedTerm = text
        // Set now, so the field's change to these words does not start the search a second time.
        activeTerm = text
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(text)
        }
    }

    /// The picks showing, in a new order.
    func shufflePick() { pickSeed = Int.random(in: Int.min...Int.max) }

    var filter = SearchResultFilter() {
        didSet { if filter.genres != oldValue.genres { resolveGenreFilters() } }
    }
    var sections: [Section] = [] { didSet { resolveGenreFilters() } }
    var failures: [Failure] = []
    var phase: Phase = .idle
    /// False when no enabled addon offers a searchable catalog. TMDb can still answer. See `refreshAvailability()`.
    var hasSearchableAddons = true
    /// Whether TMDb can be searched: a token is set, or a search of it has answered.
    var hasTMDb = false
    /// The categories of the idle Search page: each genre once, open on its movies and series together. Filled by `refreshAvailability()`.
    var categories: [GenreShortcut] = []
    /// The last titles opened from Search, newest first, at most 4. Kept in the history store.
    var recentQueries: [String]

    static let maxRecents = 4

    let services: AppServices
    let debounce: Duration
    let history: any SearchHistoryStore
    var task: Task<Void, Never>?
    var activeTerm: String?
    var genreTask: Task<Void, Never>?
    var isResolvingGenres = false
    var resolvedGenres: [String: [String]] = [:]
    /// Search availability changes when returning from Settings, not on each new query.
    var availabilityLoaded = false

    /// TMDb's titles for the words as a name, with IMDb identities. Being on TMDb says nothing about whether a stream exists.
    var tmdbTitles: [MetaPreview] = [] { didSet { resolveGenreFilters() } }
    /// TMDb's original names for those titles, by identity: another name the words may match.
    var aliases: [String: String] = [:]
    /// TMDb's rating counts for those titles, by identity: how likely each is to be the one meant.
    var votes: [String: Int] = [:]
    var tmdbPeople: [TMDbTitlePerson] = []
    /// The people a described search names ("Tom Hanks films from the 90s"), as TMDb has them.
    var namedPeople: [TMDbTitlePerson] = []
    let universal: @Sendable (String) async throws -> TMDbSearchHits?
    var tmdbTask: Task<Void, Never>?
    var peopleTask: Task<Void, Never>?

    /// Titles found for what the words describe, or for the words as a title or topic. Real TMDb titles, in the order found.
    var describedItems: [MetaPreview] = [] { didSet { resolveGenreFilters() } }
    let describer: DescribedSearchService
    var aiTask: Task<Void, Never>?
    /// False limits the search to the addons: Blusion TV's show picker.
    let includesAISearch: Bool
    /// Whether the words describe what to watch ("funny 90s movies") rather than name a title or a person ("Dune", "Tom Hanks").
    var isDiscovery = false { didSet { resolveGenreFilters() } }
    /// What a described search was read as asking for: what the filter chips show and change.
    var discovery: AISearchPlan? { didSet { resolveGenreFilters() } }
    /// Set once a chip was changed: the plan a retry searches again, without reading the words again.
    var editedPlan: AISearchPlan?
    /// The words the full results were asked for, by Return, a recent search or a suggestion. While the field holds anything else
    /// the screen may show suggestions instead.
    var submittedTerm: String?

    /// Titles and people found earlier on this screen, newest first: what suggestions are made from before the network answers.
    @ObservationIgnored var knownTitles: [MetaPreview] = []
    @ObservationIgnored var knownPeople: [TMDbTitlePerson] = []
    @ObservationIgnored var memo: (inputs: RankInputs, lists: [SearchScope: [MetaPreview]])?

    /// Where the results come from. While typing, the last words' results stay on screen until each source answers the new ones.
    enum ResultSource { case addons, tmdb, described }
    @ObservationIgnored var stale: Set<ResultSource> = []

    /// Whether this device checks described searches with the on-device model.
    var aiAvailable: Bool { includesAISearch && describer.ranker != nil }

    var isUsingAI: Bool {
        aiAvailable && aiPhase == .searching && (aiStage == .ranking
            || (editedPlan == nil && !DescribedSearch.isFilterOnly(term) && !AISearchGrounding.mightBeTitle(term)))
    }

    /// `history` keeps the recent searches. Without one they live only as long as this model. `universal` answers TMDb's titles and
    /// people for a name, nil when TMDb cannot be asked.
    init(services: AppServices, debounce: Duration = .milliseconds(250), history: (any SearchHistoryStore)? = nil,
                describer: DescribedSearchService? = nil, includesAISearch: Bool = true,
                universal: (@Sendable (String) async throws -> TMDbSearchHits?)? = nil) {
        let store = history ?? InMemorySearchHistoryStore()
        self.services = services
        self.includesAISearch = includesAISearch
        self.describer = describer ?? .live(services)
        let tmdb = TMDbSearch(services)
        if !includesAISearch {
            self.universal = { _ in nil }
        } else if let universal {
            self.universal = universal
        } else {
            self.universal = { text in try await tmdb.hits(for: text) }
        }
        self.debounce = debounce
        self.history = store
        self.recentQueries = Self.normalised(store.load())
    }

    var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasResults: Bool {
        sections.contains { !$0.items.isEmpty } || !tmdbTitles.isEmpty || !describedItems.isEmpty || !people.isEmpty
    }
    /// Nothing came back and every addon failed because the device is offline.
    var isOffline: Bool { !hasResults && Connectivity.isOffline(failures.map(\.error)) }
    /// "No results" needs a source that could have answered; with none the screen says so instead.
    var showsNoResults: Bool {
        phase == .done && aiPhase == .done && !isResolvingGenres && !hasResults && failures.isEmpty && aiIssue == nil && (hasSearchableAddons || hasTMDb)
    }
    var showsNoSearchableAddons: Bool { !hasSearchableAddons && !hasTMDb }
}
