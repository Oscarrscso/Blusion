import Foundation

/// The "Lazy load" setting: how many titles a long list keeps ready above and below the ones on screen. The count is in titles, the same
/// on every device and layout. A grid loads the posters of that many titles on each side of what the viewer sees, so scrolling does not
/// show empty posters; a paged grid also lets go of the artwork of titles further away than that, and requests its next page when any
/// title within that many of the end appears. Near is 3 titles each way, Balanced (the default) 9, Far 18. The level is a device-local
/// setting (UserDefaults only, never synced); the Mac reads the same key.
enum LazyLoadLookahead {
    struct Level {
        let label: String
        /// Titles kept ready on each side of the visible ones.
        let titles: Int
    }

    /// UserDefaults key of the chosen level (1...3), absent until the viewer moves the slider.
    static let defaultsKey = "settings.lazyLoadLookahead"
    static let defaultLevel = 2
    /// Level 1, 2 and 3.
    static let levels = [Level(label: "Near", titles: 3), Level(label: "Balanced", titles: 9), Level(label: "Far", titles: 18)]

    /// The chosen level, 1...3; `defaultLevel` when nothing is saved (every existing install) or the saved value is out of range.
    static func level(in defaults: UserDefaults = .standard) -> Int {
        let saved = defaults.object(forKey: defaultsKey) as? Int ?? defaultLevel
        return min(max(saved, 1), levels.count)
    }

    /// Titles kept ready on each side of the visible ones at `level`; a level outside 1...3 counts as the nearest one.
    static func titles(atLevel level: Int) -> Int {
        levels[min(max(level, 1), levels.count) - 1].titles
    }

    /// Titles ahead of the end at which the next page loads, and titles on each side of the screen that are kept loaded.
    static func titlesAhead(in defaults: UserDefaults = .standard) -> Int {
        titles(atLevel: level(in: defaults))
    }

    /// The index in a list of `count` titles from which an appearing title loads the next page: every title at or after it does.
    static func triggerIndex(count: Int, titles: Int) -> Int { max(0, count - 1 - titles) }

    static func triggerIndex(count: Int, in defaults: UserDefaults = .standard) -> Int {
        triggerIndex(count: count, titles: titlesAhead(in: defaults))
    }

    /// The element whose appearance loads the next page, or nil when the list is empty.
    static func triggerElement<C: RandomAccessCollection>(in items: C) -> C.Element? where C.Index == Int {
        let index = triggerIndex(count: items.count)
        return items.indices.contains(index) ? items[index] : nil
    }

    /// The indices to keep loaded when `visible` is on screen in a list of `count` titles: `titles` more on each side, clamped to the list.
    /// Nil when the list is empty or the visible range lies outside it.
    static func bufferRange(visible: ClosedRange<Int>, count: Int, titles: Int) -> ClosedRange<Int>? {
        let lower = max(0, visible.lowerBound - max(0, titles))
        let upper = min(count - 1, visible.upperBound + max(0, titles))
        return lower <= upper ? lower...upper : nil
    }
}
