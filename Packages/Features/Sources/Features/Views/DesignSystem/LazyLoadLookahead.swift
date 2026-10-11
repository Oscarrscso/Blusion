#if canImport(UIKit)
import Foundation

/// How far a long list works ahead and behind the viewer, the "Lazy load" setting. The distance is counted in rows: the next page loads
/// when the viewer is that many rows from the end, and a paged grid lets go of artwork that many rows behind them. Near is one row; the
/// default keeps three rows (nine titles on a phone) each way, an 18 title buffer. The level is a device-local setting (UserDefaults
/// only, never synced); the Mac reads the same key.
enum LazyLoadLookahead {
    struct Level {
        let label: String
        let rows: Int
    }

    /// UserDefaults key of the chosen level (1...3), absent until the viewer moves the slider.
    static let defaultsKey = "settings.lazyLoadLookahead"
    static let defaultLevel = 2
    /// Titles across a phone's grid, the width a row is counted in.
    static let phoneColumns = 3
    /// Level 1, 2 and 3.
    static let levels = [Level(label: "Near", rows: 1), Level(label: "Balanced", rows: 3), Level(label: "Far", rows: 6)]

    /// The chosen level, 1...3; `defaultLevel` when nothing is saved (every existing install).
    static var level: Int {
        let saved = UserDefaults.standard.object(forKey: defaultsKey) as? Int ?? defaultLevel
        return min(max(saved, 1), levels.count)
    }

    /// Titles ahead of the end at which the next page loads, and titles behind the first one on screen at which artwork is released.
    static func titlesAhead(columns: Int = phoneColumns) -> Int {
        levels[level - 1].rows * max(1, columns)
    }

    /// The index in a list of `count` titles from which an appearing title loads the next page: every title at or after it does.
    static func triggerIndex(count: Int, columns: Int = phoneColumns) -> Int { max(0, count - 1 - titlesAhead(columns: columns)) }

    /// The element whose appearance loads the next page, or nil when the list is empty.
    static func triggerElement<C: RandomAccessCollection>(in items: C) -> C.Element? where C.Index == Int {
        let index = triggerIndex(count: items.count)
        return items.indices.contains(index) ? items[index] : nil
    }
}
#endif
