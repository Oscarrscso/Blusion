import Foundation

/// Why a widget's source cannot load. `message` is one plain sentence for the user.
public enum WidgetSourceError: Error, Equatable, Sendable {
    /// No installed, enabled addon has this catalog.
    case addonMissing(host: String?)
    /// A Trakt list, but no Trakt client ID is set in Settings.
    case needsTraktClientID
    case unsupported(kind: String)
    /// The request itself failed.
    case addon(AddonError)

    public var message: String {
        switch self {
        case .addonMissing(let host?): return "The addon for this row (\(host)) isn't installed or is turned off."
        case .addonMissing(nil): return "The addon for this row isn't installed or is turned off."
        case .needsTraktClientID: return "Add a Trakt client ID in Settings to show Trakt lists."
        case .unsupported: return "Blusion can't show this kind of row yet."
        case .addon(let error): return "The addon couldn't load this row: \(error.shortDescription.lowercased())."
        }
    }
}

/// Loads the items of widget sources. Results are cached in memory; a source that cannot load fails with a `WidgetSourceError`.
/// The first page of each source is also kept in `snapshots` (when given), so Home can show it again on the next launch.
public final class WidgetContentService: Sendable {
    private let registry: AddonRegistry
    private let client: AddonClient
    private let settings: any SettingsStore
    private let trakt: TraktClient
    private let snapshots: (any WidgetSnapshotStore)?
    private let now: @Sendable () -> Date
    private let cache = WidgetItemCache()

    public init(registry: AddonRegistry, client: AddonClient, settings: any SettingsStore,
                trakt: TraktClient? = nil, snapshots: (any WidgetSnapshotStore)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.registry = registry
        self.client = client
        self.settings = settings
        self.trakt = trakt ?? TraktClient(client: client)
        self.snapshots = snapshots
        self.now = now
    }

    /// Items of one source. `skip` is the number of items already loaded (paging). Results are cached per (source, limit, skip)
    /// for `cacheTTL` seconds; 0 bypasses the cache. A loaded first page replaces the source's snapshot.
    public func items(for source: WidgetSource, limit: Int = 20, skip: Int = 0, cacheTTL: Int = 3600) async throws -> [MetaPreview] {
        guard limit > 0 else { return [] }
        let offset = max(skip, 0)
        let ttl = max(cacheTTL, 0)
        if ttl > 0, let cached = await cache.items(for: source, limit: limit, skip: offset, at: now()) { return cached }
        let items = try await fetch(source, limit: limit, skip: offset)
        if offset == 0, let snapshots {
            await snapshots.save(items, for: source)
        }
        if ttl > 0 {
            await cache.store(items, for: source, limit: limit, skip: offset, ttl: TimeInterval(ttl), at: now())
        }
        return items
    }

    /// The items most recently loaded for a source, however old, so Home can show them while it loads again. The in-memory cache is
    /// asked first, then the snapshot store. Nothing is requested from an addon; nil when the source was never loaded.
    public func lastKnownItems(for source: WidgetSource, limit: Int = 20) async -> [MetaPreview]? {
        let known: [MetaPreview]?
        if let inMemory = await cache.latestFirstPage(for: source) {
            known = inMemory
        } else {
            known = await snapshots?.items(for: source)
        }
        return known.map { Array($0.prefix(max(limit, 0))) }
    }

    /// Several sources as one list, for a collection tile. Sources load concurrently and are interleaved round-robin; an item
    /// with the same type and id as one already taken is dropped. A failing source is skipped, and the call throws only when
    /// every source failed (with the first source's error).
    public func items(for sources: [WidgetSource], limit: Int = 40, cacheTTL: Int = 3600) async throws -> [MetaPreview] {
        guard !sources.isEmpty, limit > 0 else { return [] }
        let outcomes = await withTaskGroup(of: (Int, Result<[MetaPreview], WidgetSourceError>).self,
                                           returning: [Result<[MetaPreview], WidgetSourceError>].self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do {
                        let items = try await self.items(for: source, limit: limit, skip: 0, cacheTTL: cacheTTL)
                        return (index, .success(items))
                    } catch let error as WidgetSourceError {
                        return (index, .failure(error))
                    } catch {
                        return (index, .failure(.addon(AddonError.from(error))))
                    }
                }
            }
            var collected: [(Int, Result<[MetaPreview], WidgetSourceError>)] = []
            for await outcome in group { collected.append(outcome) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var lists: [[MetaPreview]] = []
        var firstError: WidgetSourceError?
        for outcome in outcomes {
            switch outcome {
            case .success(let items): lists.append(items)
            case .failure(let error): firstError = firstError ?? error
            }
        }
        if lists.isEmpty, let firstError { throw firstError }
        return Self.interleave(lists, limit: limit)
    }

    /// Why a source cannot load right now, decided without any network request; nil when it can.
    public func issue(with source: WidgetSource) async -> WidgetSourceError? {
        switch source {
        case .addonCatalog(let reference):
            let addons = await registry.addons
            return reference.resolve(in: addons) == nil ? .addonMissing(host: reference.host) : nil
        case .traktList:
            let clientID = await traktClientID()
            return clientID == nil ? .needsTraktClientID : nil
        case .unsupported(let kind):
            return .unsupported(kind: kind)
        }
    }

    /// Forgets every cached page (pull to refresh). The snapshots stay, so last-known items remain available while the reload runs.
    public func invalidate() async {
        await cache.removeAll()
    }

    /// Forgets everything the service remembers, cached pages and snapshots alike: the rows of a removed addon or a reset Home must not linger.
    public func forgetEverything() async {
        await cache.removeAll()
        await snapshots?.clear()
    }

    private func fetch(_ source: WidgetSource, limit: Int, skip: Int) async throws -> [MetaPreview] {
        switch source {
        case .addonCatalog(let reference):
            let addons = await registry.addons
            guard let match = reference.resolve(in: addons) else { throw WidgetSourceError.addonMissing(host: reference.host) }
            var extras: [ExtraParam] = []
            if let genre = reference.genre, !genre.isEmpty { extras.append(ExtraParam("genre", genre)) }
            if skip > 0 {
                // A catalog that cannot page has nothing beyond its first page.
                guard match.catalog.supportsSkip else { return [] }
                extras.append(ExtraParam("skip", String(skip)))
            }
            do {
                let items = try await client.catalog(base: match.addon.baseURL, type: match.catalog.type, id: match.catalog.id, extras: extras)
                return Array(items.prefix(limit))
            } catch {
                throw WidgetSourceError.addon(AddonError.from(error))
            }
        case .traktList(let list):
            guard let clientID = await traktClientID() else { throw WidgetSourceError.needsTraktClientID }
            do {
                let items = try await trakt.listItems(list, clientID: clientID, page: skip / limit + 1, limit: limit)
                return Array(items.prefix(limit))
            } catch {
                throw WidgetSourceError.addon(AddonError.from(error))
            }
        case .unsupported(let kind):
            throw WidgetSourceError.unsupported(kind: kind)
        }
    }

    /// The Trakt client ID from Settings, trimmed; nil when none is set.
    private func traktClientID() async -> String? {
        let current = await settings.load()
        guard let clientID = current.traktClientID?.trimmingCharacters(in: .whitespacesAndNewlines), !clientID.isEmpty else { return nil }
        return clientID
    }

    private static func interleave(_ lists: [[MetaPreview]], limit: Int) -> [MetaPreview] {
        var seen = Set<[String]>()
        var merged: [MetaPreview] = []
        let longest = lists.map(\.count).max() ?? 0
        for position in 0..<longest {
            for list in lists where position < list.count {
                let item = list[position]
                guard seen.insert([item.type, item.id]).inserted else { continue }
                merged.append(item)
                if merged.count == limit { return merged }
            }
        }
        return merged
    }
}

/// Pages loaded recently, keyed by source, limit and skip. Each entry expires at the TTL it was stored with.
private actor WidgetItemCache {
    private struct Key: Hashable {
        let source: WidgetSource
        let limit: Int
        let skip: Int
    }

    private struct Entry {
        let items: [MetaPreview]
        let expiresAt: Date
        let storedAt: Date
    }

    /// Bounds memory during a long session of paging. Expired entries stay until then, because they are the last-known items.
    private static let capacity = 200

    private var entries: [Key: Entry] = [:]

    func items(for source: WidgetSource, limit: Int, skip: Int, at date: Date) -> [MetaPreview]? {
        guard let entry = entries[Key(source: source, limit: limit, skip: skip)], entry.expiresAt > date else { return nil }
        return entry.items
    }

    /// The first page stored most recently for a source, whatever its limit and whether it has expired.
    func latestFirstPage(for source: WidgetSource) -> [MetaPreview]? {
        entries.filter { $0.key.source == source && $0.key.skip == 0 }
            .max { $0.value.storedAt < $1.value.storedAt }?
            .value.items
    }

    func store(_ items: [MetaPreview], for source: WidgetSource, limit: Int, skip: Int, ttl: TimeInterval, at date: Date) {
        let key = Key(source: source, limit: limit, skip: skip)
        entries[key] = Entry(items: items, expiresAt: date.addingTimeInterval(ttl), storedAt: date)
        guard entries.count > Self.capacity else { return }
        // The least recently stored entries go first; the one just stored is never the one removed.
        let oldestFirst = entries.filter { $0.key != key }.sorted { $0.value.storedAt < $1.value.storedAt }
        for evicted in oldestFirst.prefix(entries.count - Self.capacity) {
            entries[evicted.key] = nil
        }
    }

    func removeAll() {
        entries = [:]
    }
}
