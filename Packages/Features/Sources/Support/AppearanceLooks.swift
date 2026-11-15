import Foundation

/// A look the listener saved under a name on Settings → Appearance, to come back to with one tap.
struct AppearanceLook: Sendable, Equatable, Codable, Identifiable {
    var id: UUID
    var name: String
    var appearance: AppearancePreferences

    init(id: UUID = UUID(), name: String, appearance: AppearancePreferences) {
        self.id = id
        self.name = name
        self.appearance = appearance
    }
}

/// The saved looks, oldest first, as one JSON string under `defaultsKey`.
struct AppearanceLooks: Sendable, Equatable, RawRepresentable {
    static let defaultsKey = "settings.appearance.looks"
    /// More than enough for anyone, and a bound on what the defaults hold.
    static let limit = 50

    var looks: [AppearanceLook]

    init(looks: [AppearanceLook] = []) {
        self.looks = Array(looks.prefix(Self.limit))
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8), let looks = try? JSONDecoder().decode([AppearanceLook].self, from: data) else {
            return nil
        }
        self.init(looks: looks)
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(looks), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    /// Look by look, as `AppearancePreferences` compares itself, rather than `RawRepresentable`'s comparison of the JSON text, whose key
    /// order can differ between two encodings of the same looks.
    static func == (lhs: AppearanceLooks, rhs: AppearanceLooks) -> Bool {
        lhs.looks == rhs.looks
    }

    /// Adds `appearance` under `name`, trimmed, or replaces the look already saved under that name. An empty name is "Look N".
    mutating func save(_ appearance: AppearancePreferences, as name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? unusedLookName() : String(trimmed.prefix(40))
        if let index = looks.firstIndex(where: { $0.name.caseInsensitiveCompare(title) == .orderedSame }) {
            looks[index].appearance = appearance
        } else if looks.count < Self.limit {
            looks.append(AppearanceLook(name: title, appearance: appearance))
        }
    }

    /// "Look N" from the count up, skipping a name still in use: after a deletion the count's own name can belong to a saved look,
    /// which an empty name must not replace.
    private func unusedLookName() -> String {
        var number = looks.count + 1
        while looks.contains(where: { $0.name.caseInsensitiveCompare("Look \(number)") == .orderedSame }) { number += 1 }
        return "Look \(number)"
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
