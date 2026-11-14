import Foundation
import StremioKit

public protocol DescriptionInterpreting: Sendable {
    func interpret(_ text: String) async -> DescribedSearch
    func plan(_ text: String) async -> AISearchPlan
}

public extension DescriptionInterpreting {
    func plan(_ text: String) async -> AISearchPlan {
        AISearchPlan(filters: await interpret(text),
                     titleQueries: DescribedSearch.readsLikeDescription(text) ? [] : [text])
    }
}

struct KeywordDescriptionInterpreter: DescriptionInterpreting {
    func interpret(_ text: String) async -> DescribedSearch { .reading(text) }

    func plan(_ text: String) async -> AISearchPlan {
        let description = DescribedSearch.readsLikeDescription(text)
        return AISearchPlan(filters: description ? .reading(text) : DescribedSearch(),
                            titleQueries: description ? [] : [text], requiresSemanticRanking: description)
    }
}

/// Small database batches are published as soon as they are checked. Model inference never hides an earlier batch.
public struct DescribedSearchService: Sendable {
    let interpreter: any DescriptionInterpreting
    let keywords: @Sendable (String) async -> [TMDbDiscoverQuery.Named]
    let titles: @Sendable (TMDbDiscoverQuery) async throws -> [MetaPreview]
    let pageTitles: (@Sendable (TMDbDiscoverQuery, Int) async throws -> [MetaPreview])?
    let titleMatches: @Sendable (String) async throws -> [MetaPreview]
    let ranker: (any CandidateRanking)?
    let resolveGenres: @Sendable ([MetaPreview]) async -> [MetaPreview]
    /// The titles of every named person, among the kinds and years the search allows.
    let peopleTitles: @Sendable ([AISearchPlan.Person], DescribedSearch) async throws -> [AISearchCandidate]
    let companies: @Sendable (String) async -> [TMDbDiscoverQuery.Named]
    let related: @Sendable (MetaPreview) async throws -> [MetaPreview]
    let watched: @Sendable () async -> Set<String>
    /// TMDb's people for a name, to check whether words of the search name someone.
    let people: @Sendable (String) async -> [TMDbTitlePerson]
    /// A title's rating out of 10, as the rating filters judge it, from its TMDb score and the other sites; a minimum score is held to it.
    let titleRating: @Sendable (MetaPreview, Double?) async -> Double?

    public init(interpreter: any DescriptionInterpreting, keywords: @escaping @Sendable (String) async -> [TMDbDiscoverQuery.Named],
                titles: @escaping @Sendable (TMDbDiscoverQuery) async throws -> [MetaPreview],
                ranker: (any CandidateRanking)? = nil,
                titleMatches: @escaping @Sendable (String) async throws -> [MetaPreview] = { _ in [] },
                peopleTitles: @escaping @Sendable ([AISearchPlan.Person], DescribedSearch) async throws -> [AISearchCandidate] = { _, _ in [] },
                companies: @escaping @Sendable (String) async -> [TMDbDiscoverQuery.Named] = { _ in [] },
                related: @escaping @Sendable (MetaPreview) async throws -> [MetaPreview] = { _ in [] },
                watched: @escaping @Sendable () async -> Set<String> = { [] },
                pageTitles: (@Sendable (TMDbDiscoverQuery, Int) async throws -> [MetaPreview])? = nil,
                people: @escaping @Sendable (String) async -> [TMDbTitlePerson] = { _ in [] },
                resolveGenres: @escaping @Sendable ([MetaPreview]) async -> [MetaPreview] = { $0 },
                titleRating: @escaping @Sendable (MetaPreview, Double?) async -> Double? = { _, tmdbScore in tmdbScore }) {
        self.titleRating = titleRating
        self.interpreter = interpreter
        self.keywords = keywords
        self.titles = titles
        self.ranker = ranker
        self.resolveGenres = resolveGenres
        self.titleMatches = titleMatches
        self.peopleTitles = peopleTitles
        self.companies = companies
        self.related = related
        self.watched = watched
        self.pageTitles = pageTitles
        self.people = people
    }

    static let limit = 40
    static let batchSize = 12
    static let candidateLimit = 72
    /// Stop after a useful row, rather than running inference until forty cards have accumulated. Eighteen read as too few.
    static let semanticTarget = 30
    /// The lowest TMDb score of the popular titles a search with nothing else to go on gets.
    static let crowdPleaserScore = 7.0

    /// Whether a title is named exactly as the words, accents, case, punctuation and a leading article aside ("lego movie" is The
    /// Lego Movie).
    static func isNamed(_ item: MetaPreview, _ name: String) -> Bool {
        bareName(item.name) == bareName(name)
    }

    /// Whether a title is named as the words or is a sequel under that name ("Scary Movie 3", "Alien: Romulus").
    static func isNamedOrSequel(_ item: MetaPreview, _ name: String) -> Bool {
        let title = bareName(item.name), wanted = bareName(name)
        return title == wanted || title.hasPrefix(wanted + " ")
    }

    private static func bareName(_ name: String) -> String {
        let words = AISearchGrounding.normalized(name).split(separator: " ")
        let kept = words.count > 1 && ["the", "a", "an"].contains(words[0]) ? words.dropFirst() : words[...]
        return kept.joined(separator: " ")
    }
    /// Includes retries: a rejected batch cannot cause a fresh retry tree for every database page.
    static let rankingAttemptLimit = 8
    /// Candidate batches the model checks at once.
    static let rankingConcurrency = 2

    struct RankOutcome: Sendable {
        var items: [MetaPreview]
        /// Model calls made, the split halves' included.
        var attempts: Int
        var failed: Bool
    }

    /// The batch's titles the model picks, in its order, never one twice or one it was not shown. After a failure the batch is
    /// tried once more as two halves when `canSplit`, which can salvage a good half without retrying every synopsis.
    static func rank(_ batch: [AISearchCandidate], ranker: any CandidateRanking, request: String, references: [String],
                     canSplit: Bool) async -> RankOutcome {
        func select(_ part: [AISearchCandidate]) async throws -> [MetaPreview] {
            // No generated explanations are displayed in this row. Give the model enough story evidence and ask only for selections.
            let ranked = try await ranker.rank(request: request, references: references,
                                               candidates: part.map { line($0.item, evidence: $0.evidence) }, watched: [])
            var selected = Set<Int>()
            return ranked.compactMap { entry in
                guard (1...part.count).contains(entry.number), selected.insert(entry.number).inserted else { return nil }
                return part[entry.number - 1].item
            }
        }
        guard !Task.isCancelled else { return RankOutcome(items: [], attempts: 0, failed: false) }
        do {
            return RankOutcome(items: try await select(batch), attempts: 1, failed: false)
        } catch {
            guard !Task.isCancelled else { return RankOutcome(items: [], attempts: 1, failed: false) }
            guard canSplit else { return RankOutcome(items: [], attempts: 1, failed: true) }
            let midpoint = batch.count / 2
            var outcome = RankOutcome(items: [], attempts: 1, failed: false)
            for half in [Array(batch[..<midpoint]), Array(batch[midpoint...])] {
                guard !Task.isCancelled else { break }
                outcome.attempts += 1
                do { outcome.items += try await select(half) } catch { if !Task.isCancelled { outcome.failed = true } }
            }
            return outcome
        }
    }

    /// The titles a search asks for, published batch by batch. The on-device model reads only a search that describes something:
    /// words that could be a title ("Dune", "zombies") and plain filters ("90s comedy") are read from the words alone. With
    /// `supplied`, an edited plan, nothing is read again: the plan is searched as it stands.
    public func titles(for text: String, plan supplied: AISearchPlan? = nil,
                       onUpdate: @escaping @Sendable (AISearchUpdate) async -> Void = { _ in }) async -> [MetaPreview] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !Task.isCancelled else { return [] }
        await onUpdate(AISearchUpdate(items: [], stage: .interpreting, plan: supplied))
        let early = supplied == nil
        let filterOnly = early && DescribedSearch.isFilterOnly(term)
        let titleLike = early && !filterOnly && AISearchGrounding.mightBeTitle(term)
        let usesModel = early && !filterOnly && !titleLike
        func interpretation() async -> AISearchPlan? { usesModel ? await interpreter.plan(term) : nil }
        async let interpreted = interpretation()
        var output: [MetaPreview] = []
        var seen = Set<String>()
        var considered = Set<String>()
        var issue: AISearchUpdate.Issue?
        var rankingAttempts = 0
        var reported = supplied
        var factFilters = DescribedSearch()

        func update(_ stage: AISearchUpdate.Stage) async {
            guard !Task.isCancelled else { return }
            await onUpdate(AISearchUpdate(items: output, stage: stage, issue: issue, plan: reported))
        }
        func publish(_ items: [MetaPreview], stage: AISearchUpdate.Stage) async {
            guard !Task.isCancelled else { return }
            let filters = reported?.filters ?? factFilters
            let checked = filters.genres.isEmpty && filters.excludedGenres.isEmpty ? items : await resolveGenres(items)
            guard !Task.isCancelled else { return }
            for item in checked where Self.fits(item, filters: filters) && Self.fitsGenres(item, filters: filters, requireKnown: true) && output.count < Self.limit && seen.insert(item.identity).inserted {
                output.append(item)
            }
            await update(stage)
        }
        func recordFailure(_ error: any Error) {
            guard !Task.isCancelled else { return }
            if let source = error as? WidgetSourceError, source == .needsTMDbToken {
                issue = .needsTMDbToken
            } else if issue != .needsTMDbToken {
                issue = .database
            }
        }

        // Words that could be a title are searched as one at once. They are a story topic too when TMDb has a keyword for each of
        // their topic words ("zombies", "Star Wars"), or a genre when they imply one ("anime", "space"): then only titles of exactly
        // that name stand for the title, and the topic's titles follow, instead of "Zombies of the Third Reich" alone.
        let lexical = AISearchGrounding.plan(ModelReading(), for: term)
        let phrases = AISearchGrounding.topicPhrases(in: term)
        var topics: [TMDbDiscoverQuery.Named] = []
        var wordsAreTopic = false
        var exactTitlesOnly = false
        if titleLike {
            func searchTitles() async -> Result<[MetaPreview], any Error> {
                do { return .success(try await titleMatches(term)) } catch { return .failure(error) }
            }
            async let matches = searchTitles()
            let found = AISearchGrounding.isAllTopic(term) && !phrases.isEmpty ? await exactKeywords(for: phrases) : []
            let result = await matches
            let titles = (try? result.get()) ?? []
            // A topic, unless a title of that very name shows it is a title ("Inception"); a plural word is a topic even then
            // ("zombies", though there is a film called Zombies).
            let words = AISearchGrounding.normalized(term).split(separator: " ").map(String.init)
            let plural = words.count == 1 && !AISearchGrounding.isSingular(words[0])
            wordsAreTopic = !found.isEmpty && AISearchGrounding.uncoveredTopics(in: term, by: found.map(\.name)).isEmpty
                && (plural || !titles.contains { Self.isNamed($0, term) })
            if wordsAreTopic { topics = found }
            exactTitlesOnly = wordsAreTopic
            if case .failure(let error) = result { recordFailure(error) }
            let shown = exactTitlesOnly ? titles.filter { Self.isNamed($0, term) } : titles
            considered.formUnion(shown.map(\.identity))
            await publish(shown, stage: .titles)
        } else if usesModel, !phrases.isEmpty, !AISearchGrounding.capitalisesATopic(term) {
            let found = await exactKeywords(for: phrases)
            if !found.isEmpty, AISearchGrounding.uncoveredTopics(in: term, by: found.map(\.name)).isEmpty { topics = found }
        }
        // Topics the words name outright are searched at once too, when TMDb's keywords answer every one of them and the words ask
        // for nothing a synopsis would have to show: titles tagged with each topic, in the requested genres, years and language,
        // need no check by the model ("funny heist movies", "time travel series", "Japanese samurai films with great reviews"). A
        // topic written with a capital ("Tom Hanks films") is likely a name, and a search that rules something out ("heist movies
        // without violence") or wants only unwatched titles needs what only the reading and history give, so those wait.
        var earlyQueries = Set<TMDbDiscoverQuery>()
        if !topics.isEmpty, lexical.trustsTopicMatches, !lexical.unwatchedOnly, lexical.referenceTitles.isEmpty,
           !AISearchGrounding.hasNegation(term) {
            let queries = lexical.queries(keywords: Array(topics.prefix(DescribedSearch.maxMoods)))
            earlyQueries = Set(queries)
            await withTaskGroup(of: Result<[MetaPreview], any Error>.self) { group in
                for query in queries {
                    group.addTask {
                        do { return .success(try await fetch(query, page: 0)) } catch { return .failure(error) }
                    }
                }
                for await result in group {
                    guard !Task.isCancelled else { group.cancelAll(); break }
                    switch result {
                    case .success(let items):
                        let fitting = items.filter { Self.fits($0, filters: lexical.filters) && considered.insert($0.identity).inserted }
                        await publish(fitting, stage: .themes)
                    case .failure(let error):
                        recordFailure(error)
                    }
                }
            }
        }

        if filterOnly {
            var filters = DescribedSearch.reading(term)
            let words = Set(term.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            if words.isDisjoint(with: ["film", "films", "movie", "movies", "tv", "show", "shows", "series", "television"]) {
                filters.kind = nil
            }
            factFilters = filters
            let queries = AISearchPlan(filters: filters).queries(keywords: [])
            var exhausted = Set<TMDbDiscoverQuery>()
            for page in 0..<(pageTitles == nil ? 1 : 3) {
                // Movie and series requests are independent; a slow one must not hide the other.
                await withTaskGroup(of: (TMDbDiscoverQuery, Result<[MetaPreview], any Error>).self) { group in
                    for query in queries where !exhausted.contains(query) {
                        group.addTask {
                            do { return (query, .success(try await fetch(query, page: page))) } catch { return (query, .failure(error)) }
                        }
                    }
                    for await (query, result) in group {
                        guard !Task.isCancelled, output.count < Self.limit else { group.cancelAll(); break }
                        switch result {
                        case .success(let items):
                            if items.isEmpty { exhausted.insert(query) }
                            await publish(items.filter { Self.fits($0, filters: filters) }, stage: .filters)
                        case .failure(let error):
                            recordFailure(error)
                            exhausted.insert(query)
                        }
                    }
                }
                if output.count == Self.limit || Task.isCancelled { break }
            }
        }
        var reading: AISearchPlan
        if let supplied {
            reading = supplied
        } else if let read = await interpreted {
            reading = read
            // People the model did not list are still found when TMDb has someone of that very name.
            if reading.people.isEmpty, var grounded = await planNamingPeople(in: term) {
                grounded.interpretationFailed = reading.interpretationFailed
                reading = grounded
            }
        } else if filterOnly {
            reading = AISearchPlan(filters: factFilters, requiresSemanticRanking: false)
        } else {
            // Words that could be a title are searched as one, and as a topic when TMDb's keywords showed them to be one.
            reading = AISearchPlan(filters: DescribedSearch(), titleQueries: [term], requiresSemanticRanking: false)
            reading.titlesFromWords = wordsAreTopic
            reading.trustsTopicMatches = true
        }
        guard !Task.isCancelled else { return [] }
        if reading.interpretationFailed { issue = issue ?? .ranking }
        // Words that are a topic are searched as one, whatever the model made of them: first, so the cap below can't drop them.
        var topicIndex = 0
        for topic in topics where wordsAreTopic && !reading.filters.moods.contains(where: { AISearchGrounding.isSameTopic($0, topic.name) }) {
            reading.filters.moods.insert(topic.name, at: topicIndex)
            topicIndex += 1
        }
        reading.filters.moods = Array(reading.filters.moods.prefix(DescribedSearch.maxMoods))
        // A search with nothing the reading could use ("something to watch tonight") gets well-liked popular titles, not nothing.
        if early, reading.filters.isEmpty, reading.titleQueries.isEmpty || reading.titlesFromWords, reading.people.isEmpty,
           reading.referenceTitles.isEmpty, reading.companies.isEmpty, reading.language == nil, reading.providers.isEmpty {
            reading.filters.minimumScore = Self.crowdPleaserScore
        }
        let plan = reading
        reported = plan
        // Factual filter requests do not need their plots scored for genre or release year.
        if filterOnly {
            await update(.complete)
            return output
        }
        let history = plan.unwatchedOnly || plan.watchedOnly || !plan.referenceTitles.isEmpty ? await watched() : []
        var excluded = plan.watchedOnly ? [] : history
        var references: [MetaPreview] = []
        var target = plan.requiresSemanticRanking && ranker != nil ? Self.semanticTarget : Self.limit
        let request = plan.judgement.isEmpty ? term : term + "\nWhat the synopsis should show: " + plan.judgement

        func finished() -> Bool {
            Task.isCancelled || output.count >= target || considered.count >= Self.candidateLimit
                || (plan.requiresSemanticRanking && ranker != nil && rankingAttempts >= Self.rankingAttemptLimit)
        }
        /// Takes each list's fresh candidates and publishes them, after the model's check when the search needs one. Batches are
        /// checked two at a time (on this Mac two calls side by side took about as long as one), and published in the lists' order.
        func consume(_ lists: [(found: [AISearchCandidate], stage: AISearchUpdate.Stage, verified: Bool)]) async {
            guard !finished(), let first = lists.first else { return }
            await update(first.stage)
            var batches: [[AISearchCandidate]] = []
            for list in lists {
                let needsGenres = !plan.filters.genres.isEmpty || !plan.filters.excludedGenres.isEmpty
                let checked = needsGenres ? await resolveGenres(list.found.map(\.item)) : list.found.map(\.item)
                guard !Task.isCancelled else { return }
                let candidates = zip(list.found, checked).map { candidate, item in
                    AISearchCandidate(item: item, evidence: candidate.evidence, metadata: candidate.metadata)
                }
                var scores: [String: Double] = [:]
                if plan.filters.minimumScore != nil { scores = await ratings(of: candidates) }
                guard !Task.isCancelled else { return }
                let fresh = candidates.filter { candidate in
                    let item = candidate.item
                    guard !excluded.contains(item.identity), !plan.watchedOnly || history.contains(item.identity),
                          Self.fits(item, filters: plan.filters),
                          Self.fitsMetadata(candidate, plan: plan, score: scores[item.identity]),
                          considered.count < Self.candidateLimit else { return false }
                    return considered.insert(item.identity).inserted
                }
                for start in stride(from: 0, to: fresh.count, by: Self.batchSize) {
                    let batch = Array(fresh[start..<min(start + Self.batchSize, fresh.count)])
                    if ranker != nil, plan.requiresSemanticRanking, !list.verified {
                        batches.append(batch)
                    } else {
                        guard !Task.isCancelled, output.count < target else { return }
                        await publish(batch.map(\.item), stage: list.stage)
                    }
                }
            }
            guard let ranker, !batches.isEmpty, !Task.isCancelled, output.count < target else { return }
            await update(.ranking)
            let referenceLines = references.map { Self.line($0) }
            var next = 0
            var shown = 0
            var done: [Int: [MetaPreview]] = [:]
            var reserved: [Int: Int] = [:]
            await withTaskGroup(of: (Int, RankOutcome).self) { group in
                var running = 0
                while true {
                    // Each call holds its own attempt and, when it may split after a failure, the two halves' too, so the
                    // search-wide budget holds however many calls run at once; what a call did not use is given back.
                    // Not `finished()`: reaching the candidate limit must not leave candidates already taken unchecked.
                    while running < Self.rankingConcurrency, next < batches.count, !Task.isCancelled, output.count < target {
                        let batch = batches[next]
                        let canSplit = batch.count > 1 && rankingAttempts + 3 <= Self.rankingAttemptLimit
                        let reserve = canSplit ? 3 : 1
                        guard rankingAttempts + reserve <= Self.rankingAttemptLimit else { break }
                        rankingAttempts += reserve
                        reserved[next] = reserve
                        let index = next
                        group.addTask {
                            (index, await Self.rank(batch, ranker: ranker, request: request, references: referenceLines, canSplit: canSplit))
                        }
                        next += 1
                        running += 1
                    }
                    guard let (index, outcome) = await group.next() else { break }
                    running -= 1
                    rankingAttempts -= (reserved[index] ?? 1) - outcome.attempts
                    if outcome.failed, !Task.isCancelled { issue = issue ?? .ranking }
                    done[index] = outcome.items
                    while let items = done.removeValue(forKey: shown) {
                        await publish(items, stage: .ranking)
                        shown += 1
                    }
                    // Once enough results are visible, cancel any in-flight inference rather than
                    // spending the remaining model budget on titles that will never be presented.
                    if Task.isCancelled || output.count >= target { group.cancelAll() }
                }
            }
        }
        func consume(_ found: [AISearchCandidate], stage: AISearchUpdate.Stage) async {
            await consume([(found, stage, false)])
        }

        for name in plan.titleQueries {
            guard !finished() else { break }
            do {
                let matches = try await titleMatches(name)
                let found = exactTitlesOnly ? matches.filter { Self.isNamed($0, name) }
                    : plan.titleSequelsOnly ? matches.filter { Self.isNamedOrSequel($0, name) } : matches
                if plan.titlesFromWords {
                    // The words' own filters ("Scary Movie" reads horror, "1917" a year) never hide the title they name.
                    await publish(found.filter { !excluded.contains($0.identity) && considered.insert($0.identity).inserted }, stage: .titles)
                } else {
                    await consume(found.map { AISearchCandidate(item: $0, evidence: "Database title search: \(name)") }, stage: .titles)
                }
                if !found.isEmpty, plan.people.isEmpty, plan.referenceTitles.isEmpty, plan.companies.isEmpty { break }
            } catch { recordFailure(error) }
        }
        if !plan.people.isEmpty {
            await update(.people)
            do { await consume(try await peopleTitles(plan.people, plan.filters), stage: .people) } catch { recordFailure(error) }
        }
        for name in plan.referenceTitles {
            guard !finished() else { break }
            do {
                let matches = try await titleMatches(name)
                guard let seed = matches.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
                references.append(seed)
                excluded.insert(seed.identity)
                let found = try await related(seed)
                await consume(found.map {
                    AISearchCandidate(item: $0, evidence: "TMDb recommendation related to \(seed.name)")
                }, stage: .similar)
            } catch { recordFailure(error) }
        }
        // A title the model named is the answer once found, as before. Words that only stood in for a title ("time travel") end
        // the search only when a title of exactly that name is found; otherwise the themes are searched.
        let foundTitle = output.contains { item in plan.titleQueries.contains { Self.isNamed(item, $0) } }
        let wordsAskMore = !foundTitle || wordsAreTopic || !plan.filters.genres.isEmpty
        if !finished(), plan.people.isEmpty, plan.titleQueries.isEmpty || output.isEmpty || (plan.titlesFromWords && wordsAskMore),
           !plan.filters.isEmpty || plan.language != nil || !plan.companies.isEmpty || !references.isEmpty || !plan.providers.isEmpty {
            var studios: [TMDbDiscoverQuery.Named] = []
            for name in plan.companies {
                let matches = await companies(name)
                if let exact = matches.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { studios.append(exact) }
            }
            if plan.companies.isEmpty || studios.count == plan.companies.count {
                // Resolve independent topics together, keeping the interpreter's order.
                async let includedTopics = keywords(for: plan.filters.moods)
                async let excludedTopics = keywords(for: plan.excludedTopics)
                let (matched, omitted) = await (includedTopics, excludedTopics)
                // Every requested topic is a TMDb keyword of that very name and nothing else needs a synopsis: the tagged titles are
                // the answer.
                let verifiedThemes = plan.trustsTopicMatches && !matched.isEmpty
                    && plan.filters.moods.prefix(DescribedSearch.maxMoods).allSatisfy { mood in
                        matched.contains { AISearchGrounding.isSameTopic($0.name, mood) }
                    }
                if verifiedThemes { target = Self.limit }
                let themed = matched.isEmpty ? [] : plan.queries(keywords: matched, excluded: omitted, companies: studios)
                // Without a genre in the words, the wider pool is drawn from the reference title's genres ("like Prisoners" draws on
                // crime dramas, not whatever is popular this week) or from the genres the feel words imply.
                // The two genres together come first ("dark gritty" reads crime thrillers), then the first alone; a reference's
                // genres only together, since "like Prisoners" is not any drama.
                var implied: [String] = []
                if plan.filters.genres.isEmpty {
                    if let seed = references.first {
                        implied = Array(seed.genres.prefix(2))
                    } else if ranker != nil, plan.requiresSemanticRanking {
                        implied = AISearchGrounding.poolGenres(in: term)
                    }
                }
                let pools = implied.isEmpty ? [plan.filters.genres]
                    : [implied] + (references.isEmpty && implied.count > 1 ? [[implied[0]]] : [])
                let poolQueries = pools.map { genres in
                    var pool = plan
                    pool.filters.genres = genres
                    return pool.queries(keywords: [], excluded: omitted, companies: studios)
                }
                // Asked one after another, films before series when the words name no kind: TV's genres are wider ("Sci-Fi &
                // Fantasy" put Supernatural and Pokémon first for "dark atmospheric sci-fi"), and series still follow.
                let broad = [TMDbDiscoverQuery.Kind.movie, .series].flatMap { kind in
                    poolQueries.map { $0.filter { $0.kind == kind } }
                }.filter { !$0.isEmpty }
                var exhausted = Set<TMDbDiscoverQuery>()

                /// One page of every query in the rounds, asked together; the candidates are then taken in the rounds' order.
                func discover(_ rounds: [(queries: [TMDbDiscoverQuery], stage: AISearchUpdate.Stage, verified: Bool)], page: Int) async {
                    guard !finished(), let first = rounds.first(where: { !$0.queries.isEmpty }) else { return }
                    await update(first.stage)
                    var pages: [TMDbDiscoverQuery: [MetaPreview]] = [:]
                    // A first page already searched before the model's reading is not asked for again.
                    var asked: [TMDbDiscoverQuery] = []
                    for query in rounds.flatMap(\.queries)
                        where !exhausted.contains(query) && !(page == 0 && earlyQueries.contains(query)) && !asked.contains(query) {
                        asked.append(query)
                    }
                    await withTaskGroup(of: (TMDbDiscoverQuery, Result<[MetaPreview], any Error>).self) { group in
                        for query in asked {
                            group.addTask {
                                do { return (query, .success(try await fetch(query, page: page))) } catch { return (query, .failure(error)) }
                            }
                        }
                        for await (query, result) in group {
                            guard !Task.isCancelled else { group.cancelAll(); break }
                            switch result {
                            case .success(let found):
                                if found.isEmpty { exhausted.insert(query) }
                                pages[query] = found
                            case .failure(let error):
                                recordFailure(error)
                                exhausted.insert(query)
                            }
                        }
                    }
                    var lists: [(found: [AISearchCandidate], stage: AISearchUpdate.Stage, verified: Bool)] = []
                    for round in rounds {
                        for query in round.queries {
                            guard let found = pages.removeValue(forKey: query) else { continue }
                            let facts = Self.facts(for: query)
                            lists.append((found.map { AISearchCandidate(item: $0, evidence: facts) }, round.stage, round.verified))
                        }
                    }
                    await consume(lists)
                }
                // Give requested themes the first slots and the first inference budget. Broaden one page at a time for recall.
                // Never exhaust generic popularity pages before even requesting the relevant pool. When the model checks every
                // candidate, the theme and wider pools of a page are asked and checked together.
                let wider = broad.map { (queries: $0, stage: AISearchUpdate.Stage.filters, verified: false) }
                for page in 0..<(pageTitles == nil ? 1 : 3) {
                    let themes = (queries: themed, stage: AISearchUpdate.Stage.themes, verified: verifiedThemes)
                    if ranker != nil, !verifiedThemes {
                        await discover([themes] + wider, page: page)
                    } else {
                        await discover([themes], page: page)
                        if themed.isEmpty || output.isEmpty { await discover(wider, page: page) }
                    }
                    if finished() { break }
                }
            }
        }
        guard !Task.isCancelled else { return [] }
        await update(.complete)
        return output
    }

    /// The search read again with the people its words name, when TMDb has someone of each name: "Tom Hanks films from the 90s",
    /// "Brad Pitt and George Clooney movies", "Christopher Nolan directed films". Nil when the words name nobody. At most three
    /// names are looked up, one request each.
    private func planNamingPeople(in term: String) async -> AISearchPlan? {
        var named: [(phrase: AISearchGrounding.PersonPhrase, person: TMDbTitlePerson)] = []
        for phrase in AISearchGrounding.personPhrases(in: term) {
            guard !Task.isCancelled else { return nil }
            if let person = await people(phrase.phrase).first(where: { SearchResults.isSameName($0.name, phrase.phrase) }) {
                named.append((phrase, person))
            }
        }
        guard !named.isEmpty else { return nil }
        func role(_ entry: (phrase: AISearchGrounding.PersonPhrase, person: TMDbTitlePerson)) -> AISearchPlan.Person.Role {
            if let role = entry.phrase.role { return role }
            switch entry.person.roles.first {
            case "Directing": return .director
            case "Writing": return .writer
            default: return .cast
            }
        }
        func names(_ wanted: AISearchPlan.Person.Role) -> [String] { named.filter { role($0) == wanted }.map { $0.phrase.phrase } }
        var plan = AISearchGrounding.plan(ModelReading(cast: names(.cast), directors: names(.director), writers: names(.writer),
                                                       creators: names(.creator)), for: term)
        // TMDb's own spelling of each name is what the credits are looked up by.
        for index in plan.people.indices {
            guard let entry = named.first(where: { AISearchGrounding.normalized($0.phrase.phrase) == AISearchGrounding.normalized(plan.people[index].name) })
            else { continue }
            plan.people[index].name = entry.person.name
            plan.people[index].character = entry.phrase.character
        }
        return plan.people.isEmpty ? nil : plan
    }

    private func fetch(_ query: TMDbDiscoverQuery, page: Int) async throws -> [MetaPreview] {
        if let pageTitles { return try await pageTitles(query, page * Self.batchSize) }
        return try await titles(query)
    }

    /// TMDb's keyword for each phrase that is that phrase itself, in the phrases' order; a word inside a pair already found is not
    /// looked for again.
    private func exactKeywords(for phrases: [String]) async -> [TMDbDiscoverQuery.Named] {
        let answers = await withTaskGroup(of: (Int, [TMDbDiscoverQuery.Named]).self) { group in
            for (index, phrase) in phrases.enumerated() {
                group.addTask { (index, Self.sameTopic(await keywords(phrase), phrase)) }
            }
            var found: [Int: [TMDbDiscoverQuery.Named]] = [:]
            for await (index, matches) in group where !matches.isEmpty { found[index] = matches }
            return found
        }
        var lists: [[TMDbDiscoverQuery.Named]] = []
        var coveredWords = Set<String>()
        for (index, phrase) in phrases.enumerated() {
            guard let matches = answers[index] else { continue }
            let words = Set(AISearchGrounding.normalized(phrase).split(separator: " ").flatMap { AISearchGrounding.stems(String($0)) })
            guard !words.isSubset(of: coveredWords) else { continue }
            lists.append(matches)
            coveredWords.formUnion(words)
        }
        return Self.firstsFirst(lists)
    }

    /// Each topic's main keyword before any topic's second, so a second form never takes the place of another topic.
    static func firstsFirst(_ lists: [[TMDbDiscoverQuery.Named]]) -> [TMDbDiscoverQuery.Named] {
        var chosen: [TMDbDiscoverQuery.Named] = []
        for rank in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where list.count > rank && !chosen.contains(list[rank]) { chosen.append(list[rank]) }
        }
        return chosen
    }

    /// TMDb's keywords that are the topic itself, the singular one first and two at most: "zombie" tags thousands of titles and
    /// "zombies" a handful, so both are asked for, and the topic is not left to the smaller one.
    static func sameTopic(_ found: [TMDbDiscoverQuery.Named], _ phrase: String) -> [TMDbDiscoverQuery.Named] {
        let same = found.filter { AISearchGrounding.isSameTopic($0.name, phrase) }
        func isSingular(_ keyword: TMDbDiscoverQuery.Named) -> Bool {
            AISearchGrounding.normalized(keyword.name).split(separator: " ").allSatisfy { AISearchGrounding.isSingular(String($0)) }
        }
        return Array((same.filter(isSingular) + same.filter { !isSingular($0) }).prefix(2))
    }

    private func keywords(for topics: [String]) async -> [TMDbDiscoverQuery.Named] {
        await withTaskGroup(of: (Int, [TMDbDiscoverQuery.Named]).self) { group in
            for (index, topic) in topics.prefix(DescribedSearch.maxMoods).enumerated() {
                group.addTask { (index, await keyword(topic)) }
            }
            var found: [(Int, [TMDbDiscoverQuery.Named])] = []
            for await answer in group { found.append(answer) }
            return Self.firstsFirst(found.sorted { $0.0 < $1.0 }.map(\.1))
        }
    }

    /// The topic's own keywords when TMDb has them (both "zombie" and "zombies"), else the one keyword that names it.
    private func keyword(_ topic: String) async -> [TMDbDiscoverQuery.Named] {
        let found = await keywords(topic)
        let same = Self.sameTopic(found, topic)
        if !same.isEmpty { return same }
        func terms(_ text: String) -> Set<String> {
            Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map { word in
                if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
                if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
                return String(word)
            })
        }
        let words = terms(topic)
        let match = found.first { $0.name.caseInsensitiveCompare(topic) == .orderedSame }
            ?? found.first { match in
                !words.isEmpty && words.isSubset(of: terms(match.name))
            }
        return match.map { [$0] } ?? []
    }

    private static func facts(for query: TMDbDiscoverQuery) -> String {
        var parts = [query.kind.title, query.genres.map(\.name).joined(separator: ", ")]
        if let value = query.language { parts.append("Original language: \(value)") }
        if let value = query.releasedFrom { parts.append("Released from: \(value)") }
        if let value = query.releasedTo { parts.append("Released through: \(value)") }
        if let value = query.minimumRuntime { parts.append("Runtime at least \(value) minutes") }
        if let value = query.maximumRuntime { parts.append("Runtime at most \(value) minutes") }
        if let value = query.minimumScore { parts.append("Rated at least \(value)/10") }
        if !query.companies.isEmpty { parts.append(query.companies.map(\.name).joined(separator: ", ")) }
        if !query.keywords.isEmpty { parts.append("At least one database topic: " + query.keywords.map(\.name).joined(separator: ", ")) }
        return parts.filter { !$0.isEmpty }.joined(separator: "; ")
    }

    /// A longer synopsis avoids losing the requested subject after the first sentence. Twelve such lines still fit a small model prompt.
    static func line(_ item: MetaPreview, evidence: String = "") -> String {
        var copy = item
        copy.description = nil
        let heading = Self.heading(copy)
        let synopsis = item.description?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
        return heading + (synopsis.isEmpty ? "" : ". Synopsis: " + String(synopsis.prefix(480)))
            + (evidence.isEmpty ? "" : ". Database evidence: " + String(evidence.prefix(320)))
    }

    /// Each candidate's rating out of 10 by identity (see `titleRating`), asked for six at a time; one no site has scored is left out.
    private func ratings(of candidates: [AISearchCandidate]) async -> [String: Double] {
        var scores: [String: Double] = [:]
        for start in stride(from: 0, to: candidates.count, by: 6) {
            let batch = candidates[start..<min(start + 6, candidates.count)]
            let found = await withTaskGroup(of: (String, Double?).self, returning: [String: Double].self) { group in
                for candidate in batch {
                    let item = candidate.item, tmdbScore = candidate.metadata?.score
                    group.addTask { (item.identity, await titleRating(item, tmdbScore)) }
                }
                var answers: [String: Double] = [:]
                for await (identity, score) in group { if let score { answers[identity] = score } }
                return answers
            }
            scores.merge(found) { first, _ in first }
            if Task.isCancelled { break }
        }
        return scores
    }

    /// `score` is the candidate's rating out of 10 (see `titleRating`), which a minimum score is held to.
    private static func fitsMetadata(_ candidate: AISearchCandidate, plan: AISearchPlan, score: Double?) -> Bool {
        guard let metadata = candidate.metadata else { return true }
        guard fitsGenres(candidate.item, filters: plan.filters, requireKnown: true) else { return false }
        if let language = plan.language, metadata.language != language { return false }
        if let minimum = plan.filters.minimumScore, (score ?? -1) < (minimum > 10 ? minimum / 10 : minimum) { return false }
        return plan.companies.allSatisfy { name in metadata.companies.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
    }

    private static func fits(_ item: MetaPreview, filters: DescribedSearch) -> Bool {
        fitsRuntime(item, filters) && fitsKindAndYears(item, filters) && fitsGenres(item, filters: filters)
    }

    /// A candidate's facts as the model reads them: "Zodiac (2007), film. Crime, Drama, Mystery. 157 min".
    static func heading(_ item: MetaPreview) -> String {
        var parts = [item.releaseInfo.map { "\(item.name) (\($0))" } ?? item.name]
        parts[0] += item.type == "series" ? ", series" : ", film"
        if !item.genres.isEmpty { parts.append(item.genres.prefix(3).joined(separator: ", ")) }
        if let runtime = item.runtime, !runtime.isEmpty { parts.append(runtime) }
        return parts.joined(separator: ". ")
    }

    /// False for a title whose known runtime is outside the request's: the model does not weigh runtimes reliably. A title with no
    /// known runtime is kept.
    static func fitsRuntime(_ item: MetaPreview, _ search: DescribedSearch) -> Bool {
        guard let minutes = minutes(item.runtime) else { return true }
        if let longest = search.maximumRuntime, minutes > longest { return false }
        if let shortest = search.minimumRuntime, minutes < shortest { return false }
        return true
    }

    /// False for a title of the other kind, or released outside the request's years when its year is known. TMDb's recommendations
    /// are not filtered by TMDb, so they are checked here.
    static func fitsKindAndYears(_ item: MetaPreview, _ search: DescribedSearch) -> Bool {
        if let kind = search.kind, item.type != (kind == .movie ? "movie" : "series") { return false }
        guard let year = item.releaseInfo.flatMap({ Int($0.prefix(4)) }) else { return true }
        if let earliest = search.earliestYear, year < earliest { return false }
        if let latest = search.latestYear, year > latest { return false }
        return true
    }

    /// "157 min", "2h 37min" or "2 h" as minutes; nil when it says no number.
    static func minutes(_ runtime: String?) -> Int? {
        guard let runtime = runtime?.lowercased() else { return nil }
        let numbers = runtime.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = numbers.first else { return nil }
        guard runtime.contains("h") else { return first }
        return first * 60 + (numbers.count > 1 ? numbers[1] : 0)
    }

    private static func fitsGenres(_ item: MetaPreview, filters: DescribedSearch, requireKnown: Bool = false) -> Bool {
        if !filters.genres.isEmpty {
            if item.genres.isEmpty { return !requireKnown }
            guard filters.genres.allSatisfy({ MediaGenres.contains($0, in: item.genres) }) else { return false }
        }
        return !filters.excludedGenres.contains { MediaGenres.contains($0, in: item.genres) }
    }
}
