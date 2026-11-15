import Foundation
import StremioKit

/// A bounded set of database searches, not titles invented by the language model.
struct AISearchPlan: Sendable, Equatable {
    struct Person: Sendable, Equatable {
        enum Role: String, Sendable { case cast, director, writer, creator }
        var name: String
        var role: Role
        /// The part they must play ("Forrest Gump"), checked against the credit's own character. Nil for any part.
        var character: String?
        init(name: String, role: Role, character: String? = nil) { self.name = name; self.role = role; self.character = character }
    }

    var filters: DescribedSearch
    var titleQueries: [String]
    var referenceTitles: [String]
    var people: [Person]
    var companies: [String]
    var language: String?
    var excludedTopics: [String]
    var requiresSemanticRanking: Bool
    var unwatchedOnly: Bool
    /// Only titles the viewing history holds ("comedies I've seen").
    var watchedOnly = false
    /// Streaming services the titles must be on, as TMDb lists them in the device's region. Only discover searches can check this.
    var providers: [StreamProvider] = []
    /// The lexical fallback can still find factual matches, but an inference failure must remain retryable.
    var interpretationFailed = false
    /// Set when the words ask for nothing beyond facts and topics: titles TMDb has tagged with every requested topic then need no
    /// synopsis check by the model, which is slow and was rejecting real heist comedies for "funny heist movies".
    var trustsTopicMatches = false
    /// What a synopsis must show beyond the database's facts, in the search's own words ("dark gritty", "less depressing"). The model
    /// checking candidates is told this outright, since it otherwise took any title whose genre and years fit.
    var judgement = ""
    /// Set when the search's own words stand in as its title because the model named none, so only an exact match ends the search.
    var titlesFromWords = false
    /// Set when the model gave back words that do not read as a title as one: only a title of that name or its sequels counts.
    var titleSequelsOnly = false

    init(filters: DescribedSearch, titleQueries: [String] = [], referenceTitles: [String] = [], people: [Person] = [],
                companies: [String] = [], language: String? = nil, excludedTopics: [String] = [], unwatchedOnly: Bool = false,
                requiresSemanticRanking: Bool = true) {
        self.filters = filters
        self.titleQueries = Array(titleQueries.prefix(2))
        self.referenceTitles = Array(referenceTitles.prefix(2))
        self.people = Array(people.prefix(3))
        self.companies = Array(companies.prefix(2))
        let code = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.language = code?.count == 2 && code?.allSatisfy(\.isLetter) == true ? code : nil
        self.excludedTopics = Array(excludedTopics.prefix(2))
        self.requiresSemanticRanking = requiresSemanticRanking
        self.unwatchedOnly = unwatchedOnly
    }

    /// Separate movie and TV queries map genres to each medium's IDs (878 versus 10765, for example). When the search names no kind,
    /// a kind without one of the requested genres is not asked: TMDb has no TV horror, thriller, romance or history, and the TV query
    /// dropped the genre and returned any popular series (The Mentalist for "slow burn psychological horror"). Series queries leave
    /// out talk, news and reality TV, which no description here asks for ("80s dark gritty" listed Wheel of Fortune). When the words
    /// name no kind, they also leave out cartoons from TV's merged genres, unless animation is asked for: "Sci-Fi & Fantasy" put
    /// Pokémon and Ranma ½ in "dark atmospheric sci-fi". "Sci-fi series" keeps them.
    func queries(keywords: [TMDbDiscoverQuery.Named], excluded: [TMDbDiscoverQuery.Named] = [],
                 companies: [TMDbDiscoverQuery.Named] = []) -> [TMDbDiscoverQuery] {
        var kinds = filters.kind.map { [$0] } ?? [.movie, .series]
        if filters.kind == nil {
            let covered = kinds.filter { kind in filters.genres.allSatisfy { TMDbDiscoverQuery.genre(named: $0, kind: kind) != nil } }
            kinds = covered.isEmpty ? [.movie] : covered
        }
        return kinds.map { kind in
            var search = filters
            search.kind = kind
            var query = search.query(keywords: keywords)
            query.language = language
            query.excludedKeywords = excluded
            query.companies = companies
            query.providers = providers.flatMap { provider in
                provider.tmdbProviderIDs.map { TMDbDiscoverQuery.Named(id: $0, name: provider.name) }
            }
            if kind == .series {
                var left = Self.nonFictionTV
                if filters.kind == nil, query.genres.contains(where: { Self.mergedTVGenres.contains($0.id) }),
                   !query.genres.contains(where: { $0.id == 16 }) {
                    left.append(TMDbDiscoverQuery.Named(id: 16, name: "Animation"))
                }
                query.excludedGenres += left.filter { genre in !query.excludedGenres.contains(genre) }
            }
            return query
        }
    }

    static let nonFictionTV = [TMDbDiscoverQuery.Named(id: 10763, name: "News"), TMDbDiscoverQuery.Named(id: 10764, name: "Reality"),
                               TMDbDiscoverQuery.Named(id: 10767, name: "Talk")]
    /// TV genres that stand for two film genres: Action & Adventure, Sci-Fi & Fantasy.
    static let mergedTVGenres: Set<Int> = [10759, 10765]
}

// MARK: - Filter chips

/// One requirement a discovery search was read as asking for, shown as a chip that can be changed or removed.
struct SearchChip: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case kind, years, runtime, score, language, unwatched, watched
        case genre(String), excludedGenre(String), theme(String), excludedTheme(String)
        case person(String), similar(String), studio(String), provider(StreamProvider)
    }

    let kind: Kind
    let title: String
    var id: Kind { kind }
}

/// A value a chip can be changed to, as the plan the search then runs. No model reads anything again.
struct SearchChipOption: Identifiable, Sendable {
    let title: String
    let plan: AISearchPlan
    var id: String { title }
}

extension AISearchPlan {
    var chips: [SearchChip] {
        var chips: [SearchChip] = []
        func add(_ kind: SearchChip.Kind, _ title: String) { chips.append(SearchChip(kind: kind, title: title)) }
        if let kind = filters.kind { add(.kind, kind == .movie ? "Movies" : "Series") }
        for person in people { add(.person(person.name), person.name) }
        for title in referenceTitles { add(.similar(title), "Like \(title)") }
        for genre in filters.genres { add(.genre(genre), genre) }
        for genre in filters.excludedGenres { add(.excludedGenre(genre), "No \(genre)") }
        if let years = Self.yearsTitle(filters.earliestYear, filters.latestYear) { add(.years, years) }
        if let longest = filters.maximumRuntime {
            add(.runtime, "Under \(longest) min")
        } else if let shortest = filters.minimumRuntime {
            add(.runtime, "Over \(shortest) min")
        }
        if let score = filters.minimumScore { add(.score, Self.scoreTitle(score)) }
        for mood in filters.moods { add(.theme(mood), mood.capitalized) }
        for topic in excludedTopics { add(.excludedTheme(topic), "No \(topic)") }
        if let language { add(.language, Locale.current.localizedString(forLanguageCode: language) ?? language.uppercased()) }
        for company in companies { add(.studio(company), company) }
        for provider in providers { add(.provider(provider), provider.name) }
        if unwatchedOnly { add(.unwatched, "Unwatched") }
        if watchedOnly { add(.watched, "Watched") }
        return chips
    }

    /// The plan without one requirement. With no theme or reference left, nothing is left for a synopsis to show.
    func removing(_ chip: SearchChip.Kind) -> AISearchPlan {
        var plan = self
        switch chip {
        case .kind: plan.filters.kind = nil
        case .years: (plan.filters.earliestYear, plan.filters.latestYear) = (nil, nil)
        case .runtime: (plan.filters.minimumRuntime, plan.filters.maximumRuntime) = (nil, nil)
        case .score: plan.filters.minimumScore = nil
        case .language: plan.language = nil
        case .unwatched: plan.unwatchedOnly = false
        case .watched: plan.watchedOnly = false
        case .genre(let name): plan.filters.genres.removeAll { $0 == name }
        case .excludedGenre(let name): plan.filters.excludedGenres.removeAll { $0 == name }
        case .theme(let name): plan.filters.moods.removeAll { $0 == name }
        case .excludedTheme(let name): plan.excludedTopics.removeAll { $0 == name }
        case .person(let name): plan.people.removeAll { $0.name == name }
        case .similar(let title): plan.referenceTitles.removeAll { $0 == title }
        case .studio(let name): plan.companies.removeAll { $0 == name }
        case .provider(let provider): plan.providers.removeAll { $0 == provider }
        }
        if plan.filters.moods.isEmpty, plan.referenceTitles.isEmpty {
            plan.requiresSemanticRanking = false
            plan.judgement = ""
        }
        return plan
    }

    /// What a chip can be changed to. Empty for a chip that can only be removed.
    func options(for chip: SearchChip.Kind, now: Date = Date()) -> [SearchChipOption] {
        func option(_ title: String, _ edit: (inout AISearchPlan) -> Void) -> SearchChipOption {
            var plan = self
            edit(&plan)
            return SearchChipOption(title: title, plan: plan)
        }
        switch chip {
        case .kind:
            return [option("Movies") { $0.filters.kind = .movie }, option("Series") { $0.filters.kind = .series }]
        case .years:
            let decade = Calendar(identifier: .gregorian).component(.year, from: now) / 10 * 10
            return stride(from: decade, through: 1950, by: -10).map { start in
                option("\(start)s") { ($0.filters.earliestYear, $0.filters.latestYear) = (start, start + 9) }
            }
        case .runtime:
            return [90, 120, 150, 180].map { (minutes: Int) in
                option("Under \(minutes) min") { ($0.filters.minimumRuntime, $0.filters.maximumRuntime) = (nil, minutes) }
            }
        case .score:
            return [6.0, 7.0, 7.5, 8.0].map { score in option(Self.scoreTitle(score)) { $0.filters.minimumScore = score } }
        default:
            return []
        }
    }

    /// "1990s", "1994", "From 2010", "Until 2009" or "1990–2004". Nil without a year.
    static func yearsTitle(_ earliest: Int?, _ latest: Int?) -> String? {
        switch (earliest, latest) {
        case (nil, nil): return nil
        case (let from?, nil): return "From \(from)"
        case (nil, let to?): return "Until \(to)"
        case (let from?, let to?):
            if from == to { return String(from) }
            if from % 10 == 0, to == from + 9 { return "\(from)s" }
            return "\(from)–\(to)"
        }
    }

    /// A score given out of 100 is read out of 10, as the query reads it.
    static func scoreTitle(_ score: Double) -> String {
        String(format: "TMDb %.1f+", score > 10 ? score / 10 : score)
    }
}

// MARK: - Candidates

/// A candidate's number in the list the model was shown (from 1), and why it fits.
struct RankedCandidate: Sendable, Equatable {
    let number: Int
    let reason: String

    init(number: Int, reason: String) {
        self.number = number
        self.reason = reason
    }
}

/// Chooses from a numbered list of real candidates, best first.
protocol CandidateRanking: Sendable {
    /// `references` describes the titles the request names, so "like Prisoners" is read as that film, not as a word.
    func rank(request: String, references: [String], candidates: [String], watched: [String]) async throws -> [RankedCandidate]
}

/// Facts attached only to search candidates; never written into a title's synopsis or saved metadata.
struct AISearchCandidate: Sendable {
    let item: MetaPreview
    let evidence: String
    let metadata: TMDbSearchMetadata?
    init(item: MetaPreview, evidence: String, metadata: TMDbSearchMetadata? = nil) {
        self.item = item; self.evidence = evidence; self.metadata = metadata
    }
}

struct AISearchUpdate: Sendable {
    enum Issue: Sendable, Equatable {
        case needsTMDbToken, database, ranking

        var text: String {
            switch self {
            case .needsTMDbToken: "Add a TMDB Read Access Token in Settings to use AI Search."
            case .database: "Some search data couldn't load. Try again."
            case .ranking: "On-device AI couldn't check some matches. Try again."
            }
        }
    }

    enum Stage: Sendable, Equatable {
        case interpreting, filters, titles, people, similar, themes, ranking, complete
        var text: String {
            switch self {
            case .interpreting: "Understanding your search…"
            case .filters: "Finding matches for your filters…"
            case .titles: "Checking titles…"
            case .people: "Checking cast, crew and studios…"
            case .similar: "Finding related films and series…"
            case .themes: "Searching themes, settings and tone…"
            case .ranking: "Checking more matches on your device…"
            case .complete: "Search complete"
            }
        }
    }
    let items: [MetaPreview]
    let stage: Stage
    let issue: Issue?
    /// What the search was read as asking for, once that is known: what the filter chips show.
    let plan: AISearchPlan?

    init(items: [MetaPreview], stage: Stage, issue: Issue? = nil, plan: AISearchPlan? = nil) {
        self.items = items
        self.stage = stage
        self.issue = issue
        self.plan = plan
    }
}
