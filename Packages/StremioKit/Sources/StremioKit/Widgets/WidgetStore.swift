import Foundation

/// The user's Home layout. `nil` means the user never customised Home, so `DefaultWidgets` applies.
public protocol WidgetStore: Sendable {
    /// nil means the user never customised Home: show `DefaultWidgets` for the current addons.
    func load() async -> [HomeWidget]?
    /// nil goes back to the automatic layout.
    func save(_ widgets: [HomeWidget]?) async
}

public actor InMemoryWidgetStore: WidgetStore {
    private var widgets: [HomeWidget]?

    public init(_ widgets: [HomeWidget]? = nil) {
        self.widgets = widgets
    }

    public func load() async -> [HomeWidget]? { widgets }

    public func save(_ widgets: [HomeWidget]?) async { self.widgets = widgets }
}

/// Stores the layout as JSON in `UserDefaults`, wrapped as `{ "version": 1, "widgets": [...] }`. Unreadable data loads as nil.
public final class DefaultsWidgetStore: WidgetStore, @unchecked Sendable {
    public static let key = "home.widgets.v1"

    private static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var widgets: [HomeWidget]

        init(version: Int, widgets: [HomeWidget]) {
            self.version = version
            self.widgets = widgets
        }

        /// One widget that cannot be read (written by a newer build, or edited by hand) is left out instead of losing the whole layout.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            var list = try container.nestedUnkeyedContainer(forKey: .widgets)
            var decoded: [HomeWidget] = []
            while !list.isAtEnd {
                if let widget = try? list.decode(HomeWidget.self) {
                    decoded.append(widget)
                } else {
                    _ = try? list.decode(Skipped.self)
                }
            }
            widgets = decoded
        }

        private enum CodingKeys: String, CodingKey { case version, widgets }
        private struct Skipped: Decodable {}
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() async -> [HomeWidget]? {
        guard let data = defaults.data(forKey: Self.key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion else { return nil }
        return envelope.widgets
    }

    public func save(_ widgets: [HomeWidget]?) async {
        guard let widgets else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(Envelope(version: Self.currentVersion, widgets: widgets)) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
