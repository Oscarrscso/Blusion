import Foundation

/// Trakt's timestamps ("2026-10-14T21:00:00.000Z", with or without the fraction). The formatters are made once: a history of a few
/// thousand episodes made two for every episode it read.
enum TraktDate {
    /// `ISO8601DateFormatter` is thread-safe and these are never changed after they are made.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let whole = ISO8601DateFormatter()

    static func parse(_ text: String) -> Date? {
        fractional.date(from: text) ?? whole.date(from: text)
    }

    /// Without the fraction, as Trakt takes `watched_at`.
    static func string(from date: Date) -> String {
        whole.string(from: date)
    }
}
