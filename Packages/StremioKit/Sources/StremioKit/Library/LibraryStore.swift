import Foundation

/// A title the user saved. Carries enough of the catalog preview to draw a poster without asking an addon again.
public struct LibraryItem: Sendable, Codable, Equatable, Identifiable {
    /// `type/contentID`, e.g. `movie/tt1`.
    public var id: String
    public var type: String
    public var contentID: String
    public var name: String
    public var poster: URL?
    public var releaseInfo: String?
    public var addedAt: Date

    public init(id: String, type: String, contentID: String, name: String, poster: URL? = nil, releaseInfo: String? = nil, addedAt: Date) {
        self.id = id
        self.type = type
        self.contentID = contentID
        self.name = name
        self.poster = poster
        self.releaseInfo = releaseInfo
        self.addedAt = addedAt
    }

    public init(preview: MetaPreview, addedAt: Date = Date()) {
        let type = preview.type.isEmpty ? "movie" : preview.type
        self.init(id: Self.identity(type: type, contentID: preview.id), type: type, contentID: preview.id, name: preview.name,
                  poster: preview.poster, releaseInfo: preview.releaseInfo, addedAt: addedAt)
    }

    public static func identity(type: String, contentID: String) -> String { "\(type)/\(contentID)" }

    /// A preview good enough to open Detail.
    public var preview: MetaPreview {
        MetaPreview(id: contentID, type: type, name: name, poster: poster, releaseInfo: releaseInfo)
    }
}

public protocol LibraryStore: Sendable {
    /// Most recently added first.
    func all() async -> [LibraryItem]
    func contains(_ id: String) async -> Bool
    func add(_ item: LibraryItem) async
    func remove(_ id: String) async
    func clear() async
}

public actor InMemoryLibraryStore: LibraryStore {
    private var items: [String: LibraryItem] = [:]

    public init(_ initial: [LibraryItem] = []) {
        for item in initial { items[item.id] = item }
    }

    public func all() async -> [LibraryItem] { items.values.sorted { $0.addedAt > $1.addedAt } }
    public func contains(_ id: String) async -> Bool { items[id] != nil }
    public func add(_ item: LibraryItem) async { items[item.id] = item }
    public func remove(_ id: String) async { items[id] = nil }
    public func clear() async { items = [:] }
}
