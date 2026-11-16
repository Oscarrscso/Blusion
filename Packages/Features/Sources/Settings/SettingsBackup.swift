import CoreFoundation
import Foundation
import StremioKit

/// Only explicitly listed preferences enter a backup. Account stores and addon URLs are never read.
@MainActor
enum SettingsBackup {
    private static let playbackKeys = [
        "preferredResolution", "dataSaver", "ultraSaver", "subtitleLanguage", "fallbackEngineEnabled",
        "playerPreference", "autoPlayBestStream", "continueWatchingRefreshSeconds", "matchesEpisodeWidthToText",
        "autoPickWait", "autoPickSource",
    ]
    private static let downloadKeys = ["downloadsAllowCellular", "downloadsDeleteWhenWatched"]
    private static let generalDefaults: [String: Any] = [
        LazyLoadLookahead.defaultsKey: LazyLoadLookahead.defaultLevel,
        OptimisationSettings.homePreloadKey: OptimisationSettings.homePreloadMatchesLazyLoad,
        OptimisationSettings.pictureMemoryKey: OptimisationSettings.defaultPictureMemory,
        OptimisationSettings.downloadSlotsKey: OptimisationSettings.defaultDownloadSlots,
        OptimisationSettings.prefetchesStreamsKey: true,
        OptimisationSettings.readiesFirstStreamKey: true,
        OptimisationSettings.savesPowerKey: true,
        OptimisationSettings.lowPerformanceWidgetsKey: false,
        ImageCachePolicy.diskMegabytesKey: ImageCachePolicy.defaultDiskMegabytes,
        GhostMode.defaultsKey: false,
        "widgets.hidesRows": false,
    ]

    struct InvalidBackup: LocalizedError {
        var errorDescription: String? { "Invalid settings file." }
    }

    static func export(settings: PlaybackSettings, widgets: [HomeWidget]?, shuffle: WidgetShuffleSettings = WidgetShuffleSettings(),
        defaults: UserDefaults = .standard) throws -> Data {
        let saved = try object(settings)
        let root: [String: Any] = [
            "format": "blusionSettings", "version": 1,
            "appearance": try object(AppearancePreferences.saved(in: defaults)),
            "player": saved["player"] ?? [:], "haptics": try object(settings.haptics.resolvedForExport),
            "playback": Dictionary(uniqueKeysWithValues: playbackKeys.map { ($0, saved[$0] ?? NSNull()) }),
            "downloads": Dictionary(uniqueKeysWithValues: downloadKeys.map { ($0, saved[$0] ?? false) }),
            "general": generalDefaults,
            "widgetShuffle": try object(shuffle),
            "widgets": try widgets.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull(),
        ]
        var result = root
        var general = generalDefaults
        for key in general.keys { general[key] = defaults.object(forKey: key) ?? general[key] }
        result["general"] = general
        return try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    }

    struct Imported {
        let settings: PlaybackSettings
        let appearance: AppearancePreferences?
        let general: [String: Any]
        let includesWidgets: Bool
        let widgets: [HomeWidget]?
        let shuffle: WidgetShuffleSettings?
        let skipped: Int
    }

    static func decode(_ data: Data, current: PlaybackSettings, defaults: UserDefaults = .standard) throws -> Imported {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == "blusionSettings",
              let version = root["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1 else { throw InvalidBackup() }
        var saved = try object(current)
        var skipped = root.keys.filter { !["format", "version", "appearance", "player", "haptics", "playback", "downloads", "general",
            "widgets", "widgetShuffle"].contains($0) }.count
        for section in ["playback", "downloads"] {
            if let value = root[section] {
                guard let values = value as? [String: Any] else { throw InvalidBackup() }
                let keys = section == "playback" ? playbackKeys : downloadKeys
                for (key, entry) in values {
                    if keys.contains(key) { saved[key] = entry } else { skipped += 1 }
                }
            }
        }
        for section in ["player", "haptics"] {
            if let value = root[section] {
                guard let values = value as? [String: Any] else { throw InvalidBackup() }
                saved[section] = restore(section, values, over: saved[section] as? [String: Any] ?? [:])
            }
        }
        let settings = try JSONDecoder().decode(PlaybackSettings.self, from: JSONSerialization.data(withJSONObject: saved))
        var appearance: AppearancePreferences?
        if let value = root["appearance"] {
            guard let values = value as? [String: Any] else { throw InvalidBackup() }
            var merged = restore("appearance", values, over: try object(AppearancePreferences.saved(in: defaults)))
            // The corner overrides are a set of their own, not fields to fill in from the current look.
            if let overrides = values["cornerOverrides"] { merged["cornerOverrides"] = overrides }
            appearance = try JSONDecoder().decode(AppearancePreferences.self, from: JSONSerialization.data(withJSONObject: merged))
        }
        var general: [String: Any] = [:]
        if let value = root["general"] {
            guard let values = value as? [String: Any] else { throw InvalidBackup() }
            for (key, entry) in values {
                guard let expected = generalDefaults[key] as? NSNumber else { skipped += 1; continue }
                guard let number = entry as? NSNumber,
                      (CFGetTypeID(number) == CFBooleanGetTypeID()) == (CFGetTypeID(expected) == CFBooleanGetTypeID()),
                      number.doubleValue.isFinite,
                      number.doubleValue.rounded() == number.doubleValue else { throw InvalidBackup() }
                general[key] = entry
            }
        }
        var widgets: [HomeWidget]?
        if let value = root["widgets"], !(value is NSNull) {
            guard let entries = value as? [Any] else { throw InvalidBackup() }
            widgets = try JSONDecoder().decode([HomeWidget].self, from: JSONSerialization.data(withJSONObject: entries))
        }
        var shuffle: WidgetShuffleSettings?
        if let value = root["widgetShuffle"] {
            guard let values = value as? [String: Any] else { throw InvalidBackup() }
            shuffle = try JSONDecoder().decode(WidgetShuffleSettings.self, from: JSONSerialization.data(withJSONObject: values))
        }
        return Imported(settings: settings, appearance: appearance, general: general,
                        includesWidgets: root["widgets"] != nil, widgets: widgets, shuffle: shuffle, skipped: skipped)
    }

    private static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] else { throw InvalidBackup() }
        return result
    }

    /// Fields a section leaves out of what it saves while they are unset, each beside one it always writes.
    private static let unsetWhenOmitted: [String: [(field: String, beside: String)]] = [
        "appearance": [("shelfSpacing", "spacing"), ("titleSectionOrder", "sectionOrder")],
        "player": [("audioLanguage", "subtitleMode")],
    ]

    /// A backup's section laid over the current one. A field the backup saved as unset stays unset, rather than keeping the current value.
    private static func restore(_ section: String, _ values: [String: Any], over current: [String: Any]) -> [String: Any] {
        var merged = merge(current, values)
        for (field, beside) in unsetWhenOmitted[section] ?? [] where values[field] == nil && values[beside] != nil {
            merged[field] = nil
        }
        return merged
    }

    private static func merge(_ current: [String: Any], _ incoming: [String: Any]) -> [String: Any] {
        current.merging(incoming) { old, new in
            if let old = old as? [String: Any], let new = new as? [String: Any] { return merge(old, new) }
            return new
        }
    }
}
