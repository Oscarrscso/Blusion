#if canImport(UIKit)
import Foundation

/// How far a long list works ahead and behind the viewer, the "Lazy load" setting. Level 1 is the original behaviour: the next page loads
/// when the last title appears, and no artwork is released. Higher levels start the next page sooner, and a paged grid releases the
/// artwork of titles that are that many titles behind the first one on screen. The level is a device-local setting (UserDefaults only,
/// never synced); the Mac reads the same key.
enum LazyLoadLookahead {
    struct Level {
        let label: String
        let titlesAhead: Int
    }

    /// UserDefaults key of the chosen level (1...3), absent until the viewer moves the slider.
    static let defaultsKey = "settings.lazyLoadLookahead"
    static let defaultLevel = 2
    /// Level 1, 2 and 3.
    static let levels = [Level(label: "Near", titlesAhead: 0), Level(label: "Balanced", titlesAhead: 6), Level(label: "Far", titlesAhead: 15)]

    /// The chosen level, 1...3; `defaultLevel` when nothing is saved (every existing install).
    static var level: Int {
        let saved = UserDefaults.standard.object(forKey: defaultsKey) as? Int ?? defaultLevel
        return min(max(saved, 1), levels.count)
    }

    /// Titles ahead of the end at which the next page loads, and titles behind the first one on screen at which artwork is released.
    static var titlesAhead: Int {
        levels[level - 1].titlesAhead
    }

    /// The index in a list of `count` titles from which an appearing title loads the next page: every title at or after it does.
    static func triggerIndex(count: Int) -> Int { max(0, count - 1 - titlesAhead) }

    /// The element whose appearance loads the next page, or nil when the list is empty.
    static func triggerElement<C: RandomAccessCollection>(in items: C) -> C.Element? where C.Index == Int {
        let index = triggerIndex(count: items.count)
        return items.indices.contains(index) ? items[index] : nil
    }
}
#endif
