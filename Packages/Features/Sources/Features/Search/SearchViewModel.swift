import Foundation
import Observation
import StremioKit

/// Search: debounced, fans out to every searchable addon, and shows per-addon error chips instead of failing as a whole.
/// Results come per addon (`sections`) and per content type (`groups`, what the screen shows).
@MainActor
@Observable
public final class SearchViewModel {
    public struct Section: Identifiable, Equatable {
        public let addon: AddonSummary
        public var items: [MetaPreview]
        public var id: UUID { addon.id }
    }

    /// The results of one content type across every addon: one row on the Search screen.
    public struct Group: Identifiable, Equatable {
        public let type: String
        public let title: String
        public var items: [MetaPreview]
        public var id: String { type }
    }

    public struct Failure: Identifiable, Equatable {
        public let addon: AddonSummary
        public let error: AddonError
        public var id: UUID { addon.id }
        public var text: String { "\(addon.name): \(error.shortDescription)" }
    }

    public enum Phase: Equatable {
        case idle
        case searching
        case done
    }

    /// A genre of one catalog, offered on the idle Search page. `source` opens that catalog filtered to the genre.
    public struct GenreShortcut: Identifiable, Hashable, Sendable {
        public let name: String
        public let source: WidgetSource
        public var id: String { name }

        public init(name: String, source: WidgetSource) {
            self.name = name
            self.source = source
        }
    }

    public var query = ""
    public private(set) var sections: [Section] = []
    public private(set) var failures: [Failure] = []
    public private(set) var phase: Phase = .idle
    /// False when no enabled addon offers a searchable catalog. A search then does no network work. See `refreshAvailability()`.
    public private(set) var hasSearchableAddons = true
    /// Genres to browse from the idle Search page. Filled by `refreshAvailability()`.
    public private(set) var browseGenres: [GenreShortcut] = []
    /// The last searches that returned something, newest first, at most 8. Kept in the history store.
    public private(set) var recentQueries: [String]

    private static let maxRecents = 8
    private static let maxGenres = 16

    private let services: AppServices
    private let debounce: Duration
    private let history: any SearchHistoryStore
    private var task: Task<Void, Never>?

    /// `history` keeps the recent searches. Without one they live only as long as this model.
    public init(services: AppServices, debounce: Duration = .milliseconds(300), history: (any SearchHistoryStore)? = nil) {
        let store = history ?? InMemorySearchHistoryStore()
        self.services = services
        self.debounce = debounce
        self.history = store
        self.recentQueries = Self.normalised(store.load())
    }

    public var hasResults: Bool { sections.contains { !$0.items.isEmpty } }
    /// Nothing came back and every addon failed because the device is offline.
    public var isOffline: Bool { !hasResults && Connectivity.isOffline(failures.map(\.error)) }
    /// "No results" needs an addon that could have answered; with none installed the screen says so instead.
    public var showsNoResults: Bool { hasSearchableAddons && phase == .done && !hasResults && failures.isEmpty }
    public var showsNoSearchableAddons: Bool { !hasSearchableAddons }

    /// Results across all addons, grouped by content type: movie first, then series, then other types in order of first appearance.
    /// Within a group items keep addon order (the user's order) then the addon's own order; duplicates (same `identity`) appear once.
    public var groups: [Group] {
        var seen = Set<String>()
        var order: [String] = []
        var itemsByType: [String: [MetaPreview]] = [:]
        for section in sections {
            for item in section.items where seen.insert(item.identity).inserted {
                let type = Self.groupType(item.type)
                if itemsByType[type] == nil { order.append(type) }
                itemsByType[type, default: []].append(item)
            }
        }
        let leading = ["movie", "series"]
        let types = leading.filter { itemsByType[$0] != nil } + order.filter { !leading.contains($0) }
        return types.map { Group(type: $0, title: ContentTypeName.plural($0), items: itemsByType[$0] ?? []) }
    }

    /// Asks whether any enabled addon can search, and reads the browse genres. Call when the Search screen appears; every search checks again.
    public func refreshAvailability() async {
        recentQueries = Self.normalised(history.load())
        let addons = await services.browse.searchableAddons()
        hasSearchableAddons = !addons.isEmpty
        let sources = await services.browse.catalogSources()
        browseGenres = Self.genreShortcuts(in: sources)
    }

    /// Forgets one recent search. Case-insensitive, like the de-duplication.
    public func removeRecent(_ query: String) {
        let key = Self.key(query)
        recentQueries.removeAll { Self.key($0) == key }
        history.save(recentQueries)
    }

    public func clearRecents() {
        recentQueries = []
        history.save([])
    }

    /// Call whenever `query` changes. Cancels the previous search and starts a new debounced one.
    public func queryDidChange() {
        task?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            reset()
            return
        }
        phase = .searching
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.run(term)
        }
    }

    /// Runs a search immediately (the keyboard's Search button) and waits for it.
    public func submit() async {
        guard !Task.isCancelled else { return }
        task?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return reset() }
        phase = .searching
        let search = Task { [weak self] in
            guard let self else { return }
            await self.run(term)
        }
        task = search
        await withTaskCancellationHandler {
            await search.value
        } onCancel: {
            search.cancel()
        }
    }

    /// Waits for the in-flight debounced search (used by tests and by accessibility announcements).
    public func waitUntilDone() async {
        await task?.value
    }

    private func reset() {
        sections = []
        failures = []
        phase = .idle
    }

    private func run(_ term: String) async {
        guard !Task.isCancelled else { return }
        sections = []
        failures = []
        await refreshAvailability()
        guard !Task.isCancelled else { return }
        guard hasSearchableAddons else {
            phase = .done
            return
        }
        let order = await services.registry.addons.map(\.id)
        let stream = await services.browse.search(term, incremental: true)
        for await response in stream {
            guard !Task.isCancelled else { return }
            switch response.result {
            case .success(let items):
                insert(Section(addon: response.addon, items: items), order: order)
            case .failure(let error):
                failures.append(Failure(addon: response.addon, error: error))
            }
        }
        guard !Task.isCancelled else { return }
        phase = .done
        if hasResults { remember(term) }
    }

    /// Puts a query that found something at the top of the recents, in place of an older copy of it.
    private func remember(_ term: String) {
        recentQueries = Self.normalised([term] + recentQueries)
        history.save(recentQueries)
    }

    /// Keeps sections in the user's addon order, whatever order the addons answer in.
    private func insert(_ section: Section, order: [UUID]) {
        if let index = sections.firstIndex(where: { $0.id == section.id }) {
            sections[index] = section
            return
        }
        func rank(_ id: UUID) -> Int { order.firstIndex(of: id) ?? Int.max }
        let index = sections.firstIndex { rank($0.addon.id) > rank(section.addon.id) } ?? sections.endIndex
        sections.insert(section, at: index)
    }

    /// The grouping key for an item's type: lower-case and trimmed, "other" when the addon sent no type.
    private static func groupType(_ type: String) -> String {
        let key = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? "other" : key
    }

    /// Up to 16 genres of one catalog: the first movie catalog that has genre options, else the first catalog that has any.
    /// Blank and repeated genres are left out, since each one is an id in the Search page.
    static func genreShortcuts(in sources: [CatalogSource]) -> [GenreShortcut] {
        let withGenres = sources.filter { !$0.catalog.genreOptions.isEmpty }
        guard let source = withGenres.first(where: { $0.catalog.type == "movie" }) ?? withGenres.first else { return [] }
        var seen = Set<String>()
        let names = source.catalog.genreOptions.filter { name in
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert(name).inserted
        }
        return names.prefix(maxGenres).map { name in
            GenreShortcut(name: name, source: .addonCatalog(AddonCatalogReference(
                manifestID: nil, host: source.addon.host, catalogType: source.catalog.type, catalogID: source.catalog.id, genre: name)))
        }
    }

    /// Recent searches as stored: trimmed, no blanks, one copy of each (the first one kept), at most 8.
    private static func normalised(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for query in queries {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, seen.insert(key(term)).inserted else { continue }
            result.append(term)
            if result.count == maxRecents { break }
        }
        return result
    }

    /// How two recent searches are compared: case-insensitively.
    private static func key(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
