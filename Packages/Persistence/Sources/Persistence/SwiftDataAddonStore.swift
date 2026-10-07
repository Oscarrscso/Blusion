#if canImport(SwiftData)
import Foundation
import SwiftData
import StremioKit

public enum PersistenceContainer {
    /// The app's container. `inMemory` is for tests; otherwise the store lives at `url` (default: SwiftData's default location).
    public static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: BlusionSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// `AddonStore` backed by SwiftData. The context is confined to this actor.
public actor SwiftDataAddonStore: AddonStore {
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    public func loadAll() async throws -> [AddonRecord] {
        let entities = try context.fetch(FetchDescriptor<AddonEntity>(sortBy: [SortDescriptor(\.order)]))
        return entities.map { AddonRecord(id: $0.id, manifestData: $0.manifestData, isEnabled: $0.isEnabled, order: $0.order, installedAt: $0.installedAt) }
    }

    public func save(_ records: [AddonRecord]) async throws {
        let existing = try context.fetch(FetchDescriptor<AddonEntity>())
        var byID: [UUID: AddonEntity] = [:]
        for entity in existing { byID[entity.id] = entity }
        let wanted = Set(records.map(\.id))
        for entity in existing where !wanted.contains(entity.id) { context.delete(entity) }
        for record in records {
            if let entity = byID[record.id] {
                entity.manifestData = record.manifestData
                entity.isEnabled = record.isEnabled
                entity.order = record.order
                entity.installedAt = record.installedAt
            } else {
                context.insert(AddonEntity(id: record.id, manifestData: record.manifestData, isEnabled: record.isEnabled,
                                           order: record.order, installedAt: record.installedAt))
            }
        }
        try context.save()
    }
}
#endif
