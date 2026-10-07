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

/// Watch progress, one row per `StreamRequest.identity`. Added in schema V2.
@Model
public final class WatchProgressEntity {
    @Attribute(.unique) public var id: String
    public var type: String
    public var contentID: String
    public var title: String
    public var posterURLString: String?
    public var position: Double
    public var duration: Double
    public var isWatched: Bool
    public var updatedAt: Date
    public var season: Int?
    public var episode: Int?

    public init(id: String, type: String, contentID: String, title: String, posterURLString: String?, position: Double, duration: Double,
                isWatched: Bool, updatedAt: Date, season: Int?, episode: Int?) {
        self.id = id
        self.type = type
        self.contentID = contentID
        self.title = title
        self.posterURLString = posterURLString
        self.position = position
        self.duration = duration
        self.isWatched = isWatched
        self.updatedAt = updatedAt
        self.season = season
        self.episode = episode
    }
}

/// A saved title. Added in schema V2.
@Model
public final class LibraryEntity {
    @Attribute(.unique) public var id: String
    public var type: String
    public var contentID: String
    public var name: String
    public var posterURLString: String?
    public var releaseInfo: String?
    public var addedAt: Date

    public init(id: String, type: String, contentID: String, name: String, posterURLString: String?, releaseInfo: String?, addedAt: Date) {
        self.id = id
        self.type = type
        self.contentID = contentID
        self.name = name
        self.posterURLString = posterURLString
        self.releaseInfo = releaseInfo
        self.addedAt = addedAt
    }
}

/// V1 (M2): addons only.
public enum BlusionSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [AddonEntity.self] }
}

/// V2 (M7): adds watch progress and the library. Existing addon rows are untouched, so the migration is lightweight.
public enum BlusionSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] { [AddonEntity.self, WatchProgressEntity.self, LibraryEntity.self] }
}

public enum BlusionMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [BlusionSchemaV1.self, BlusionSchemaV2.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: BlusionSchemaV1.self, toVersion: BlusionSchemaV2.self)]
    }
}
#endif
