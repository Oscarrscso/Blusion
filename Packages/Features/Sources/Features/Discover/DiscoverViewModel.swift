import Foundation
import Observation
import StremioKit

/// Discover: pick a catalog and genre, scroll, and `skip`-paginate.
@MainActor
@Observable
public final class DiscoverViewModel {
    public enum State: Equatable {
        case idle
        case loadingFirstPage
        case loaded
        case loadingMore
        case failed(AddonError)
    }

    public private(set) var sources: [CatalogSource] = []
    public private(set) var selectedSource: CatalogSource?
    /// The content type of `selectedSource`; nil until a source is selected.
    public private(set) var selectedType: String?
    public private(set) var selectedGenre: String?
    /// True when the type control is on "All": the catalog menu then lists the sources of every type.
    public private(set) var showsAllTypes = false
    public private(set) var items: [MetaPreview] = []
    public private(set) var state: State = .idle
    public private(set) var canLoadMore = false
    public var isOffline: Bool { state == .failed(.offline) }

    private let services: AppServices
    private var generation = 0
    /// Raw items received so far: the protocol's `skip` counts items the addon sent, not items left after de-duplication.
    private var receivedCount = 0

    public init(services: AppServices) {
        self.services = services
    }

    public var genres: [String] { selectedSource?.catalog.genreOptions ?? [] }
    public var hasSources: Bool { !sources.isEmpty }

    /// Distinct content types of `sources`: by `ContentTypeName.sortRank`, then by first appearance.
    public var types: [String] {
        var order: [String] = []
        for source in sources where !order.contains(source.type) { order.append(source.type) }
        return order.enumerated().sorted { lhs, rhs in
            let (left, right) = (ContentTypeName.sortRank(lhs.element), ContentTypeName.sortRank(rhs.element))
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The sources of the selected type; every source on "All" or when no type is selected.
    public var visibleSources: [CatalogSource] {
        guard !showsAllTypes, let selectedType else { return sources }
        return sources.filter { $0.type == selectedType }
    }

    /// Refreshes the catalog list, keeping the current selection when it still exists.
    /// Otherwise the first type (by `types`) and its first source are selected.
    public func loadSources() async {
        sources = await services.browse.catalogSources()
        if let current = selectedSource, sources.contains(current) { return }
        guard let type = types.first, let first = sources.first(where: { $0.type == type }) else {
            selectedSource = nil
            selectedType = nil
            items = []
            state = .idle
            return
        }
        await select(source: first)
    }

    /// Switches to a content type: selects that type's first source and reloads. Unknown types change nothing.
    public func select(type: String) async {
        showsAllTypes = false
        guard let first = sources.first(where: { $0.type == type }) else { return }
        await select(source: first)
    }

    /// Switches to "All": every type's sources are offered, and the current source stays (or the first one is selected).
    public func selectAllTypes() async {
        showsAllTypes = true
        guard selectedSource == nil, let first = sources.first else { return }
        await select(source: first)
    }

    public func select(source: CatalogSource) async {
        selectedSource = source
        selectedType = source.type
        if let genre = selectedGenre, !source.catalog.genreOptions.contains(genre) { selectedGenre = nil }
        await reload()
    }

    /// `nil` clears the filter.
    public func select(genre: String?) async {
        selectedGenre = genre
        await reload()
    }

    public func reload() async {
        guard let source = selectedSource else { return }
        generation += 1
        let current = generation
        items = []
        receivedCount = 0
        canLoadMore = false
        state = .loadingFirstPage
        do {
            let page = try await services.browse.page(source, genre: selectedGenre, skip: 0)
            guard current == generation else { return }
            append(page, source: source)
            state = .loaded
        } catch {
            guard current == generation else { return }
            state = .failed(AddonError.from(error))
        }
    }

    /// Call when the last item scrolls into view. Does nothing while a load is running or after an empty page.
    public func loadMore() async {
        guard canLoadMore, state == .loaded, let source = selectedSource else { return }
        let current = generation
        state = .loadingMore
        do {
            let page = try await services.browse.page(source, genre: selectedGenre, skip: receivedCount)
            guard current == generation else { return }
            append(page, source: source)
            state = .loaded
        } catch {
            guard current == generation else { return }
            // Keep what we have; the user can scroll again to retry.
            state = .loaded
        }
    }

    private func append(_ page: [MetaPreview], source: CatalogSource) {
        receivedCount += page.count
        let known = Set(items.map(\.id))
        items.append(contentsOf: page.filter { !known.contains($0.id) })
        canLoadMore = !page.isEmpty && source.catalog.supportsSkip
    }
}
