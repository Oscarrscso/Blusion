import Foundation
import StremioKit
import Testing
@testable import Features

@MainActor
@Suite struct SettingsBackupTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "SettingsBackupTests.\(UUID().uuidString)")! }

    @Test func exportExcludesSecretsAndRoundTripsPreferences() throws {
        let defaults = defaults()
        var settings = PlaybackSettings(streamingServerURL: "https://user:password@example.com", traktClientID: "private-client",
                                        omdbAPIKey: "private-omdb", tmdbReadToken: "private-tmdb",
                                        openSubtitlesAPIKey: "private-os", openSubtitlesUsername: "private-user", openSubtitlesPassword: "private-password")
        settings.autoPlayBestStream = true
        settings.downloadsAllowCellular = true
        let widget = HomeWidget(title: "Watching", content: .continueWatching)
        let data = try SettingsBackup.export(settings: settings, widgets: [widget], defaults: defaults)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("private-"))
        #expect(!text.contains("https://"))
        let imported = try SettingsBackup.decode(data, current: PlaybackSettings(), defaults: defaults)
        #expect(imported.settings.autoPlayBestStream)
        #expect(imported.settings.downloadsAllowCellular)
        #expect(imported.settings.streamingServerURL == nil)
        #expect(imported.widgets == [widget])
    }

    @Test func exportsIncludeEveryHapticEvenWhenDisabledOrUsingDefaults() throws {
        let customised = HapticPreferences(isEnabled: false, overallStrength: 1.5,
                                          places: [.reviews: .init(isOn: false, feel: .heavy, strength: 0.4)],
                                          shelfTickSpacing: 28, reviewTickLimit: 6)
        struct Export: Decodable { let haptics: HapticPreferences }

        for source in [HapticPreferences(), customised] {
            let backup = try SettingsBackup.export(settings: PlaybackSettings(haptics: source), widgets: nil, defaults: defaults())
            var exports = [backup]
            let look = try AppearanceDefaultExport.makeJSON(appearance: AppearancePreferences(), haptics: source)
            exports.append(Data(look.utf8))
            for data in exports {
                let haptics = try JSONDecoder().decode(Export.self, from: data).haptics
                #expect(haptics.usesDefaults == (source == HapticPreferences()))
                #expect(haptics.isEnabled == source.isOn)
                #expect(haptics.overallStrength == source.overall)
                #expect(haptics.shelfTickSpacing == source.shelfTickSpacingPoints)
                #expect(haptics.reviewTickLimit == source.reviewTicks)
                for place in HapticPreferences.Place.allCases {
                    #expect(haptics[place].isOn == source.plays(place))
                    #expect(haptics[place].feel == source.feel(place))
                    #expect(haptics[place].strength == source.strength(place))
                }
            }
        }
    }

    @Test func restoringABackupKeepsItsLinkedSpacingSectionOrderAndCorners() throws {
        let preset = defaults()
        let netflix = AppearancePreferences.Preset.netflix.applied(to: AppearancePreferences())
        preset.set(netflix.rawValue, forKey: AppearancePreferences.defaultsKey)
        let backup = try SettingsBackup.export(settings: PlaybackSettings(), widgets: nil, defaults: preset)

        // A fresh install has the factory look, with a shelf gap and a section order of its own.
        let fresh = defaults()
        let restored = try #require(try SettingsBackup.decode(backup, current: PlaybackSettings(), defaults: fresh).appearance)
        #expect(restored == netflix)
        #expect(restored.shelfSpacingScale == nil && restored.effectiveShelfSpacingScale == netflix.spacingScale)
        #expect(restored.orderedTitleSections.prefix(2).elementsEqual([.episodes, .cast]))

        // The other way round, the preset's corner overrides do not outlive the factory look restored over it.
        let factory = try SettingsBackup.export(settings: PlaybackSettings(), widgets: nil, defaults: fresh)
        #expect(try SettingsBackup.decode(factory, current: PlaybackSettings(), defaults: preset).appearance == AppearancePreferences())

        // A backup from before the section list keeps Cast First, and a field it does not carry stays as it is.
        let old = Data(#"{"format":"blusionSettings","version":1,"appearance":{"sectionOrder":"castFirst"}}"#.utf8)
        let legacy = try #require(try SettingsBackup.decode(old, current: PlaybackSettings(), defaults: fresh).appearance)
        #expect(legacy.titleSectionOrder.isEmpty && legacy.orderedTitleSections.prefix(2).elementsEqual([.episodes, .cast]))
        #expect(legacy.shelfSpacingScale == AppearancePreferences().shelfSpacingScale)
    }

    @Test func restoringABackupClearsAnAudioLanguageItSavedAsUnset() throws {
        let backup = try SettingsBackup.export(settings: PlaybackSettings(), widgets: nil, defaults: defaults())
        var current = PlaybackSettings()
        current.player.audioLanguage = "jpn"
        #expect(try SettingsBackup.decode(backup, current: current, defaults: defaults()).settings.player.audioLanguage == nil)
        let partial = Data(#"{"format":"blusionSettings","version":1,"player":{"prefersSDH":true}}"#.utf8)
        let kept = try SettingsBackup.decode(partial, current: current, defaults: defaults()).settings.player
        #expect(kept.audioLanguage == "jpn" && kept.prefersSDH)
    }

    @Test func partialImportPreservesOtherSettingsAndRejectsSecretKeys() throws {
        let current = PlaybackSettings(streamingServerURL: "saved-server", omdbAPIKey: "saved-key")
        let data = Data(#"{"format":"blusionSettings","version":1,"playback":{"autoPlayBestStream":true,"streamingServerURL":"attacker"},"general":{"secret":"attacker"}}"#.utf8)
        let imported = try SettingsBackup.decode(data, current: current, defaults: defaults())
        #expect(imported.settings.autoPlayBestStream)
        #expect(imported.settings.streamingServerURL == "saved-server")
        #expect(imported.settings.omdbAPIKey == "saved-key")
        #expect(imported.appearance == nil)
        #expect(!imported.includesWidgets)
        #expect(imported.general.isEmpty)
        #expect(imported.skipped == 2)
    }

    @Test func invalidVersionAndMalformedSectionsFailValidation() {
        for json in [#"{"format":"blusionSettings","version":true}"#,
                     #"{"format":"blusionSettings","version":2}"#,
                     #"{"format":"blusionSettings","version":1,"downloads":[]}"#,
                     #"{"format":"blusionSettings","version":1,"widgets":5}"#,
                     #"{"format":"blusionSettings","version":1,"widgetShuffle":false}"#,
                     #"{"format":"blusionSettings","version":1,"playback":{"playerPreference":"invalid"}}"#] {
            #expect(throws: (any Error).self) {
                try SettingsBackup.decode(Data(json.utf8), current: PlaybackSettings(), defaults: defaults())
            }
        }
    }
}
