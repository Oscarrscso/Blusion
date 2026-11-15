import Foundation
import StremioKit

/// Sectioned JSON of the active appearance and haptic settings for baking into code defaults: each Appearance page's fields under
/// the page's name (see `AppearancePreferences.encodeBySection`), then the haptics.
enum AppearanceDefaultExport {
    private struct Payload: Encodable {
        let appearance: AppearancePreferences
        let haptics: HapticPreferences

        private enum CodingKeys: String, CodingKey { case version, haptics }

        func encode(to encoder: Encoder) throws {
            try appearance.encodeBySection(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(2, forKey: .version)
            try container.encode(haptics, forKey: .haptics)
        }
    }

    static func makeJSON(appearance: AppearancePreferences, haptics: HapticPreferences) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(Payload(appearance: appearance, haptics: haptics.resolvedForExport)), as: UTF8.self)
    }
}
