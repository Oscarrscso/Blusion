import Foundation
import Observation
import StremioKit

/// Search: debounced, fans out to every searchable addon, and shows per-addon error chips instead of failing as a whole.
@MainActor
@Observable
public final class SearchViewModel {
    public struct Section: Identifiable, Equatable {
        public let addon: AddonSummary
        public var items: [MetaPreview]
        public var id: UUID { addon.id }
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

    private let services: AppServices
    private let debounce: Duration
    private var task: Task<Void, Never>?

    public init(services: AppServices, debounce: Duration = .milliseconds(300)) {
        self.services = services
        self.debounce = debounce
    }

    public var hasResults: Bool { sections.contains { !$0.items.isEmpty } }
    public var showsNoResults: Bool { phase == .done && !hasResults && failures.isEmpty }

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
}
