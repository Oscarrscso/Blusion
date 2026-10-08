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

    public var query = ""
    public private(set) var sections: [Section] = []
    public private(set) var failures: [Failure] = []
    public private(set) var phase: Phase = .idle
    /// False when no enabled addon offers a searchable catalog. A search then does no network work. See `refreshAvailability()`.
    public private(set) var hasSearchableAddons = true

    private let services: AppServices
    private let debounce: Duration
    private var task: Task<Void, Never>?

    public init(services: AppServices, debounce: Duration = .milliseconds(300)) {
        self.services = services
        self.debounce = debounce
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

    /// Asks whether any enabled addon can search. Call when the Search screen appears; every search checks again.
    public func refreshAvailability() async {
        let addons = await services.browse.searchableAddons()
        hasSearchableAddons = !addons.isEmpty
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
        task?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return reset() }
        phase = .searching
        await run(term)
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
        sections = []
        failures = []
        await refreshAvailability()
        guard !Task.isCancelled else { return }
        guard hasSearchableAddons else {
            phase = .done
            return
        }
        let order = await services.registry.addons.map(\.id)
        let stream = await services.browse.search(term)
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
    }

    /// Keeps sections in the user's addon order, whatever order the addons answer in.
    private func insert(_ section: Section, order: [UUID]) {
        func rank(_ id: UUID) -> Int { order.firstIndex(of: id) ?? Int.max }
        let index = sections.firstIndex { rank($0.addon.id) > rank(section.addon.id) } ?? sections.endIndex
        sections.insert(section, at: index)
    }

    /// The grouping key for an item's type: lower-case and trimmed, "other" when the addon sent no type.
    private static func groupType(_ type: String) -> String {
        let key = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? "other" : key
    }
}
