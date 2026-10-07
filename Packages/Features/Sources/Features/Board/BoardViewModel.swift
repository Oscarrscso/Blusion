import Foundation
import Observation
import StremioKit

/// Board: one row per browsable catalog of the user's addons, each filling in as its addon answers.
@MainActor
@Observable
public final class BoardViewModel {
    public struct Row: Identifiable, Equatable {
        public let source: CatalogSource
        public var state: Loadable<[MetaPreview]>
        public var id: String { source.id }
    }

    public enum Phase: Equatable {
        case loading
        /// Nothing installed: the empty state explains how to add an addon by URL.
        case noAddons
        /// Addons are installed but none offers a browsable catalog (e.g. stream-only addons).
        case noCatalogs
        case ready
    }

    public private(set) var rows: [Row] = []
    public private(set) var phase: Phase = .loading

    private let services: AppServices
    /// nil until the first emission, so an empty initial registry still triggers the first load.
    private var signature: [String]?
    private var generation = 0

    public init(services: AppServices) {
        self.services = services
    }

    /// Rebuilds the rows from the registry and loads each one concurrently.
    public func load() async {
        generation += 1
        let current = generation
        let addons = await services.registry.addons
        let sources = await services.browse.catalogSources()
        guard current == generation else { return }
        if addons.isEmpty {
            rows = []
            phase = .noAddons
            return
        }
        if sources.isEmpty {
            rows = []
            phase = .noCatalogs
            return
        }
        rows = sources.map { Row(source: $0, state: .loading) }
        phase = .ready
        let browse = services.browse
        await withTaskGroup(of: (String, Loadable<[MetaPreview]>).self) { group in
            for source in sources {
                group.addTask {
                    do { return (source.id, .loaded(try await browse.page(source))) } catch { return (source.id, .failed(AddonError.from(error))) }
                }
            }
            for await (id, state) in group where current == generation {
                if let index = rows.firstIndex(where: { $0.id == id }) { rows[index].state = state }
            }
        }
    }

    public func retry(rowID: Row.ID) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let source = rows[index].source
        rows[index].state = .loading
        let state: Loadable<[MetaPreview]>
        do { state = .loaded(try await services.browse.page(source)) } catch { state = .failed(AddonError.from(error)) }
        if let current = rows.firstIndex(where: { $0.id == rowID }) { rows[current].state = state }
    }

    /// Reloads whenever the set, order or enabled state of addons changes. Run from a view's `.task`; cancelling stops it.
    public func observeAddons() async {
        for await addons in await services.registry.updates() {
            let newSignature = addons.map { "\($0.id.uuidString):\($0.isEnabled)" }
            guard newSignature != signature else { continue }
            signature = newSignature
            await load()
        }
    }
}
