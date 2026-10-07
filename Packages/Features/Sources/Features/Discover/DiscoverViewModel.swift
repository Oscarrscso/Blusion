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
    public private(set) var selectedGenre: String?
    public private(set) var items: [MetaPreview] = []
    public private(set) var state: State = .idle
    public private(set) var canLoadMore = false

    private let services: AppServices
    private var generation = 0
    /// Raw items received so far: the protocol's `skip` counts items the addon sent, not items left after de-duplication.
    private var receivedCount = 0

    public init(services: AppServices) {
        self.services = services
    }

    public var genres: [String] { selectedSource?.catalog.genreOptions ?? [] }
    public var hasSources: Bool { !sources.isEmpty }

    /// Refreshes the catalog list, keeping the current selection when it still exists.
    public func loadSources() async {
        sources = await services.browse.catalogSources()
        if let current = selectedSource, sources.contains(current) { return }
        guard let first = sources.first else {
            selectedSource = nil
            items = []
            state = .idle
            return
        }
        await select(source: first)
    }

    public func select(source: CatalogSource) async {
        selectedSource = source
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
