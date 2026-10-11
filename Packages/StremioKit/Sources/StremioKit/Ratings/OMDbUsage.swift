import Foundation

/// How many requests this device has sent to OMDb today. The free key allows 1,000 a day, and OMDb counts by UTC day.
///
/// The count lives in `UserDefaults` on this device only and is never synced. It keeps today's number and starts again at 0 when the
/// UTC day changes.
public final class OMDbUsage: @unchecked Sendable {
    public static let dailyLimit = 1_000
    public static let shared = OMDbUsage()

    private static let dayKey = "omdb.usage.day"
    private static let countKey = "omdb.usage.count"

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    /// `UserDefaults` is thread-safe, but reading the count and writing it back is not one step.
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Counts one request, just before it is sent.
    public func record() {
        lock.lock()
        defer { lock.unlock() }
        let day = Self.utcDay(now())
        let count = defaults.string(forKey: Self.dayKey) == day ? defaults.integer(forKey: Self.countKey) : 0
        defaults.set(day, forKey: Self.dayKey)
        defaults.set(count + 1, forKey: Self.countKey)
    }

    /// Requests sent on the current UTC day. 0 when the stored count is from another day.
    public func today() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard defaults.string(forKey: Self.dayKey) == Self.utcDay(now()) else { return 0 }
        return max(0, defaults.integer(forKey: Self.countKey))
    }

    /// `yyyy-MM-dd` for the UTC calendar day of `date`.
    static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
