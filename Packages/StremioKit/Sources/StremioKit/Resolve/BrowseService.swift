import Foundation

/// A catalog of one installed addon, shown as a Board row or a Discover source.
public struct CatalogSource: Sendable, Equatable, Hashable, Identifiable {
    public let addon: AddonSummary
    public let baseURL: URL
    public let catalog: CatalogDescriptor

    public init(addon: AddonSummary, baseURL: URL, catalog: CatalogDescriptor) {
        self.addon = addon
        self.baseURL = baseURL
        self.catalog = catalog
    }

    public var id: String { "\(addon.id.uuidString)/\(catalog.key)" }
    public var type: String { catalog.type }
    public var title: String { catalog.name }
}

/// Browsing across the user's addons: catalog rows, paged catalogs with genre filter, multi-addon search, Detail with fallback.
public final class BrowseService: Sendable {
    public let registry: AddonRegistry
    public let client: AddonClient
    /// Types the UI shows. v1 is movies only (PLAN §1); series and other types still decode.
    public let visibleTypes: Set<String>

    public init(registry: AddonRegistry, client: AddonClient, visibleTypes: Set<String> = ["movie"]) {
        self.registry = registry
        self.client = client
        self.visibleTypes = visibleTypes
    }

    /// Browsable catalogs of enabled addons, in the user's addon order, then the addon's own catalog order.
    public func catalogSources(type: String? = nil) async -> [CatalogSource] {
        await registry.addons(providing: .catalog).flatMap { addon in
            addon.manifest.browsableCatalogs(type: type).filter { visibleTypes.contains($0.type) }.map {
                CatalogSource(addon: addon.summary, baseURL: addon.baseURL, catalog: $0)
            }
        }
    }

    /// One page. `skip` is the number of items already loaded (the protocol's pagination).
    public func page(_ source: CatalogSource, genre: String? = nil, skip: Int = 0) async throws -> [MetaPreview] {
        var extras: [ExtraParam] = []
        if let genre, !genre.isEmpty, source.catalog.extra(named: "genre") != nil { extras.append(ExtraParam("genre", genre)) }
        if skip > 0, source.catalog.supportsSkip { extras.append(ExtraParam("skip", String(skip))) }
        return try await client.catalog(base: source.baseURL, type: source.catalog.type, id: source.catalog.id, extras: extras)
    }

    /// Search every enabled addon that offers a searchable catalog. One response per addon, in the order they answer;
    /// an addon's catalogs are merged and de-duplicated, and it only fails if all of its catalogs fail.
    public func search(_ query: String) async -> AsyncStream<AddonResponse<[MetaPreview]>> {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return AsyncStream { $0.finish() } }
        let visible = visibleTypes
        let addons = await registry.addons(providing: .catalog).filter { addon in
            addon.manifest.searchableCatalogs.contains { visible.contains($0.type) }
        }
        let client = self.client
        return FanOut.run(over: addons) { addon in
            let catalogs = addon.manifest.searchableCatalogs.filter { visible.contains($0.type) }
            let outcomes = await withTaskGroup(of: (Int, Result<[MetaPreview], AddonError>).self) { group in
                for (index, catalog) in catalogs.enumerated() {
                    group.addTask {
                        do {
                            let items = try await client.catalog(base: addon.baseURL, type: catalog.type, id: catalog.id, extras: [ExtraParam("search", term)])
                            return (index, .success(items))
                        } catch {
                            return (index, .failure(AddonError.from(error)))
                        }
                    }
                }
                var collected: [(Int, Result<[MetaPreview], AddonError>)] = []
                for await outcome in group { collected.append(outcome) }
                return collected.sorted { $0.0 < $1.0 }
            }
            var seen = Set<String>()
            var merged: [MetaPreview] = []
            var firstError: AddonError?
            var anySuccess = false
            for (_, outcome) in outcomes {
                switch outcome {
                case .success(let items):
                    anySuccess = true
                    for item in items where seen.insert("\(item.type)/\(item.id)").inserted { merged.append(item) }
                case .failure(let error):
                    firstError = firstError ?? error
                }
            }
            if !anySuccess, let firstError { throw firstError }
            return merged
        }
    }

    /// Full metadata for Detail. Asks every addon that supports `meta` for this id and takes the first good answer;
    /// when none answers, Detail is built from the catalog preview (`isFallback`).
    public func detail(for preview: MetaPreview) async -> (detail: MetaDetail, isFallback: Bool) {
        let type = preview.type.isEmpty ? "movie" : preview.type
        let addons = await registry.addons(for: .meta, type: type, id: preview.id)
        let client = self.client
        for await response in FanOut.run(over: addons, operation: { try await client.meta(base: $0.baseURL, type: type, id: preview.id) }) {
            if let detail = response.value { return (detail.filling(from: preview), false) }
        }
        return (.fallback(from: preview), true)
    }
}
