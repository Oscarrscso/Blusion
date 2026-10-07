#if canImport(SwiftData)
import Foundation
import SwiftData

/// Persisted addon metadata. Deliberately has no URL field: the manifest URL may embed a token and lives in the Keychain.
@Model
public final class AddonEntity {
    @Attribute(.unique) public var id: UUID
    public var manifestData: Data
    public var isEnabled: Bool
    public var order: Int
    public var installedAt: Date

    public init(id: UUID, manifestData: Data, isEnabled: Bool, order: Int, installedAt: Date) {
        self.id = id
        self.manifestData = manifestData
        self.isEnabled = isEnabled
        self.order = order
        self.installedAt = installedAt
    }
}

/// Schema versions. A new version is added whenever an entity changes; `BlusionMigrationPlan` (M7) links them.
public enum BlusionSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [AddonEntity.self] }
}
#endif
