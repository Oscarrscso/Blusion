#if canImport(UIKit)
import Foundation

/// How many titles before the end of a list the next page starts loading. Level 1 is the original behaviour: load when the last
/// title appears. The level is a device-local iPhone setting (UserDefaults only, never synced); the Mac always loads at the last title.
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

    /// Titles ahead of the end at which the next page loads. Always 0 on the Mac.
    static var titlesAhead: Int {
        #if !targetEnvironment(macCatalyst)
        levels[level - 1].titlesAhead
        #else
        0
        #endif
    }

    /// The index in a list of `count` titles whose appearance loads the next page.
    static func triggerIndex(count: Int) -> Int { max(0, count - 1 - titlesAhead) }

    /// The element whose appearance loads the next page, or nil when the list is empty.
    static func triggerElement<C: RandomAccessCollection>(in items: C) -> C.Element? where C.Index == Int {
        let index = triggerIndex(count: items.count)
        return items.indices.contains(index) ? items[index] : nil
    }
}
#endif
