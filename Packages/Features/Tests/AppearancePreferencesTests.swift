import Foundation
import StremioKit
import Testing
@testable import Features
#if canImport(UIKit)
import UIKit
#endif

@Suite struct AppearancePreferencesTests {
    @Test func theDefaultsAreTheOriginalLook() {
        let appearance = AppearancePreferences()
        #expect(appearance.isDefault)
        #expect(appearance.preset == .original)
        #expect(appearance.accent == .olive)
        #expect(appearance.background == .graphite)
        #expect(appearance.buttonFinish == .glass && appearance.playStyle == .artwork)
        #expect(appearance.cardScale == 1 && appearance.cornerScale == 1.5 && appearance.spacingScale == 0.3)
        #expect(appearance.includesCircularButtons && appearance.cornerScale(for: .playButton) == 1.5)
        #expect(appearance.shelfSpacingScale == 1.4000000000000001 && appearance.sideMarginScale == 1.1)
        #expect(appearance.showsShelfDividers && appearance.shelfDividerFullWidth && appearance.outlinesButtons)
        #expect(appearance.shelfDividerThickness == 1.5 && appearance.shelfDividerOpacity == 0.07)
        #expect(appearance.cornerOverrides.isEmpty && appearance.progressThickness == .thin)
        #expect(appearance.phoneGridColumns == 3)
        #expect(!appearance.showsPosterTitles)
        #expect(appearance.captionLines == 1 && appearance.showsCaptionDetails)
        #expect(appearance.outline == .standard && appearance.artworkTone == .natural)
        #expect(appearance.headingFont == .matchText && appearance.headingWeight == .bold && appearance.headingSize == .standard)
        #expect(appearance.reading.textSize == .large && appearance.reading.width == .expanded && appearance.reading.weight == .semibold)
        #expect(appearance.reading.letterSpacing == .tight && appearance.reading.scale == .small)
        #expect(appearance.interface.followsReading && appearance.resolvedText(for: .interface).weight == .semibold)
        #expect(appearance.heroAutoAdvance == 0 && appearance.showsPageDots)
        #expect(appearance.showsFranchise && appearance.showsTitleSection(.franchise))
        #expect(appearance.animationSpeed == .fastest && !appearance.showsContinueBar)
        #expect(appearance.showsWatchAnywhere && appearance.showsTitlePageTabBar && !appearance.spoilerStills)
        #expect(appearance.orderedTitleSections == [.episodes, .reviews, .cast, .franchise, .related, .information, .watchAnywhere])
        #expect(appearance.startTab.tab == .home)
        #expect(appearance.backgroundRGB == AppearancePreferences.Background.graphite.rgb)
    }

    @Test func legacyPosterChoicesMoveIntoTheLookAndTheOldKeysAreCleared() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = DefaultsSettingsStore.Keys.self
        defaults.set(false, forKey: keys.showsPosterRatings)
        defaults.set(true, forKey: keys.usesHeroPosters)
        defaults.set(PosterMarkPlacement.bottomLeading.rawValue, forKey: keys.posterMarkPlacement)
        AppearancePreferences.migratePosterArtwork(in: defaults)
        let look = AppearancePreferences.saved(in: defaults)
        #expect(!look.showsPosterRatings && look.usesHeroPosters && look.posterMarkPlacement == .bottomLeading)
        #expect(look.showsBestDiscOnPosters && look.showsColouredRatingLogos, "switches never saved keep their defaults")
        #expect(defaults.object(forKey: keys.showsPosterRatings) == nil && defaults.object(forKey: keys.posterMarkPlacement) == nil)
    }

    @Test func aSavedLookWithoutPosterFieldsKeepsItsOtherSettings() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var older = AppearancePreferences()
        older.accent = .custom
        // A look saved before the poster fields existed: the same JSON without them.
        var object = (try JSONSerialization.jsonObject(with: Data(older.rawValue.utf8)) as? [String: Any]) ?? [:]
        for key in ["usesHeroPosters", "showsPosterRatings", "showsColouredRatingLogos", "showsBestDiscOnPosters", "posterMarkPlacement"] {
            object.removeValue(forKey: key)
        }
        let withoutPosters = try JSONSerialization.data(withJSONObject: object)
        defaults.set(String(decoding: withoutPosters, as: UTF8.self), forKey: AppearancePreferences.defaultsKey)
        defaults.set(true, forKey: DefaultsSettingsStore.Keys.usesHeroPosters)
        AppearancePreferences.migratePosterArtwork(in: defaults)
        let look = AppearancePreferences.saved(in: defaults)
        #expect(look.accent == .custom && look.usesHeroPosters && look.showsPosterRatings)
    }

    @Test func withoutLegacyPosterChoicesTheLookStaysAtItsDefaults() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        AppearancePreferences.migratePosterArtwork(in: defaults)
        #expect(AppearancePreferences.saved(in: defaults).isDefault)
    }

    @Test func aSecondRunDoesNotOverwriteAChoiceMadeSinceTheFirst() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: DefaultsSettingsStore.Keys.showsPosterRatings)
        AppearancePreferences.migratePosterArtwork(in: defaults)
        var look = AppearancePreferences.saved(in: defaults)
        look.showsPosterRatings = true
        defaults.set(look.rawValue, forKey: AppearancePreferences.defaultsKey)
        // An older build writes the old key again; the migration has already run, so the newer choice stands.
        defaults.set(false, forKey: DefaultsSettingsStore.Keys.showsPosterRatings)
        AppearancePreferences.migratePosterArtwork(in: defaults)
        #expect(AppearancePreferences.saved(in: defaults).showsPosterRatings)
    }

    @Test func posterChoicesSurviveASaveRoundTrip() throws {
        var look = AppearancePreferences()
        look.usesHeroPosters = true
        look.showsPosterRatings = false
        look.showsColouredRatingLogos = false
        look.showsBestDiscOnPosters = false
        look.posterMarkPlacement = .bottomTrailing
        let loaded = try #require(AppearancePreferences(rawValue: look.rawValue))
        #expect(loaded == look)
        #expect(loaded.usesHeroPosters && !loaded.showsPosterRatings && !loaded.showsColouredRatingLogos)
        #expect(!loaded.showsBestDiscOnPosters && loaded.posterMarkPlacement == .bottomTrailing)
    }

    @Test func aPresetLeavesThePosterChoicesAlone() {
        var look = AppearancePreferences()
        look.usesHeroPosters = true
        look.posterMarkPlacement = .bottomLeading
        for preset in AppearancePreferences.Preset.allCases {
            let applied = preset.applied(to: look)
            #expect(applied.usesHeroPosters && applied.posterMarkPlacement == .bottomLeading, "\(preset) keeps the poster choices")
        }
    }

    @Test func restoringTheCardsResetsThePosterChoices() {
        var look = AppearancePreferences()
        look.usesHeroPosters = true
        look.showsPosterRatings = false
        #expect(!look.isDefault(.cards))
        let restored = look.restoringDefaults(of: .cards)
        #expect(!restored.usesHeroPosters && restored.showsPosterRatings)
        #expect(restored.isDefault(.cards) && restored.isDefault)
    }

    @Test func posterChoicesDoNotCountAsTheLookBeingChanged() {
        var look = AppearancePreferences()
        look.showsPosterRatings = false
        #expect(look.isDefaultExceptPosterArtwork && !look.isDefault)
        look.accent = .custom
        #expect(!look.isDefaultExceptPosterArtwork)
    }

    @Test func aSavedLookNeverChangesThePosterChoices() {
        var current = AppearancePreferences()
        current.usesHeroPosters = true
        current.showsPosterRatings = false
        // A look saved before the poster fields existed decodes them as defaults; applying it must keep the current switches.
        var saved = AppearancePreferences()
        saved.accent = .custom
        let applied = saved.keepingPosterArtwork(of: current)
        #expect(applied.accent == .custom && applied.usesHeroPosters && !applied.showsPosterRatings)
        // Only the poster switches differ: the look counts as the one on screen.
        var sameLook = current
        sameLook.posterMarkPlacement = .bottomLeading
        #expect(sameLook.keepingPosterArtwork(of: current) == current)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "AppearancePreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test func fontChoicesFavourSansSerif() {
        let faces = AppearancePreferences.FontStyle.allCases
        let serif: Set<AppearancePreferences.FontStyle> = [.serif, .charter, .georgia]
        let sans: Set<AppearancePreferences.FontStyle> = [
            .standard, .rounded, .avenir, .avenirNext, .futura, .gillSans, .helveticaNeue, .optima,
            .helvetica, .arial, .verdana, .trebuchet, .avenirNextCondensed, .galvji, .dinAlternate,
        ]
        #expect(Set(faces) == serif.union(sans).union([.monospaced]))
        #expect(serif.count < sans.count)
        #expect(faces.map(\.rawValue).prefix(12) == [
            "standard", "rounded", "serif", "monospaced", "avenir", "avenirNext", "futura", "gillSans", "helveticaNeue",
            "helvetica", "arial", "verdana",
        ])
        for face in sans.union(serif).subtracting([.standard, .rounded, .serif]) {
            #expect(face.familyName?.isEmpty == false, "\(face.rawValue)")
            #expect(!face.label.isEmpty)
        }
        for face in AppearancePreferences.FontStyle.allCases {
            #expect(AppearancePreferences.HeadingFont(rawValue: face.rawValue)?.font == face)
        }
    }

    @Test func unavailableKefaKeepsItsDefaultFallback() throws {
        let saved = try #require(AppearancePreferences(rawValue: #"{"font":"kefa","headingFont":"kefa","accent":"green"}"#))
        #expect(saved.font == .standard)
        #expect(saved.headingFont == .standard)
        #expect(saved.accent == .green)
    }

    @Test func aRetiredSerifFontBecomesNewYork() throws {
        var appearance = AppearancePreferences()
        appearance.font = .georgia
        appearance.reading.weight = .bold
        appearance.letterSpacing = .wide
        let saved = appearance.rawValue.replacingOccurrences(of: "\"georgia\"", with: "\"baskerville\"")
        let restored = try #require(AppearancePreferences(rawValue: saved))
        #expect(restored.font == .serif)
        #expect(restored.reading.weight == .bold)
        #expect(restored.letterSpacing == .wide)
        for retired in ["palatino", "iowan", "hoefler", "didot", "bodoni", "typewriter"] {
            let font = try JSONDecoder().decode(AppearancePreferences.FontStyle.self, from: Data("\"\(retired)\"".utf8))
            #expect(font == .serif)
            let heading = try JSONDecoder().decode(AppearancePreferences.HeadingFont.self, from: Data("\"\(retired)\"".utf8))
            #expect(heading == .serif)
        }
        let legacy = try #require(AppearancePreferences(rawValue: #"{"font":"georgia","headingFont":"didot"}"#))
        #expect(legacy.font == .georgia && legacy.headingFont == .serif)
        let unknown = try #require(AppearancePreferences(rawValue: #"{"font":"comicSans","accent":"green"}"#))
        #expect(unknown.font == .standard && unknown.accent == .green)
    }

    @Test func aSaveRoundTripsThroughItsRawValue() throws {
        var appearance = AppearancePreferences()
        appearance.accent = .custom
        appearance.customAccent = .init(red: 0.2, green: 0.4, blue: 0.6)
        appearance.background = .custom
        appearance.customBackground = .init(red: 0.1, green: 0.05, blue: 0)
        appearance.textSize = .accessibility2
        appearance.font = .serif
        appearance.boldText = true
        appearance.italicText = true
        appearance.fontWidth = .condensed
        appearance.letterSpacing = .wider
        appearance.headingFont = .monospaced
        appearance.headingWeight = .black
        appearance.headingWidth = .expanded
        appearance.headingSpacing = .wider
        appearance.uppercaseHeadings = true
        appearance.cardScale = 1.35
        appearance.cornerScale = 0
        appearance.spacingScale = 1.8
        appearance.phoneGridColumns = 6
        appearance.captionLines = 2
        appearance.outline = .strong
        appearance.artworkTone = .mono
        appearance.progressColour = .accent
        appearance.heroAutoAdvance = 12
        appearance.spoilerTitles = true
        appearance.showsFranchise = false
        appearance.sectionOrder = .castFirst
        appearance.animationSpeed = .off
        appearance.startTab = .library
        appearance.layout = .editorial
        let restored = try #require(AppearancePreferences(rawValue: appearance.rawValue))
        #expect(restored == appearance)
        #expect(!restored.isDefault)
        #expect(!restored.showsFranchise && !restored.showsTitleSection(.franchise))
        #expect(restored.accentRGB == appearance.customAccent)
        #expect(restored.backgroundRGB == appearance.customBackground)
    }

    @Test func aFieldThatCannotBeReadFallsBackOnItsOwn() throws {
        let saved = #"{"accent":"neon","background":"navy","phoneGridColumns":9,"cardSize":4,"captionLines":0,"heroAutoAdvance":7}"#
        let appearance = try #require(AppearancePreferences(rawValue: saved))
        #expect(appearance.accent == .olive)
        #expect(appearance.background == .navy)
        #expect(appearance.cornerScale == 1.5 && appearance.spacingScale == 0.3)
        #expect(appearance.cardScale == AppearancePreferences.cardScaleRange.upperBound)
        #expect(appearance.phoneGridColumns == AppearancePreferences.phoneGridColumnRange.upperBound)
        #expect(appearance.captionLines == 1)
        #expect(appearance.heroAutoAdvance == 0)
        #expect(appearance.font == .standard)
    }

    @Test func theOldFixedStepsReadIntoTheNewValues() throws {
        let saved = #"{"cardScale":"large","corners":"round","density":"compact","artworkOutline":false}"#
        let appearance = try #require(AppearancePreferences(rawValue: saved))
        #expect(appearance.cardScale == 1.2)
        #expect(appearance.cornerScale == 1.8)
        #expect(appearance.spacingScale == 0.66)
        #expect(appearance.outline == .off)
        // Written back under the new names only.
        let rewritten = appearance.rawValue
        #expect(!rewritten.contains("\"density\"") && !rewritten.contains("\"artworkOutline\""))
        #expect(AppearancePreferences(rawValue: rewritten) == appearance)
    }

    @Test func missingFieldsUseTheFactoryLookAndSavedLayoutChoicesSurvive() throws {
        #expect(AppearancePreferences(rawValue: "{}") == AppearancePreferences())
        let old = try #require(AppearancePreferences(rawValue: #"{"spacing":0.8,"sectionOrder":"castFirst","boldText":false}"#))
        #expect(old.shelfSpacingScale == nil && old.effectiveShelfSpacingScale == 0.8)
        #expect(old.titleSectionOrder.isEmpty && old.orderedTitleSections.prefix(2).elementsEqual([.episodes, .cast]))
        #expect(old.reading.weight == .regular)
        #expect(AppearancePreferences(rawValue: old.rawValue) == old)
        // A look from before the three text styles keeps the plain body text it had, at its own relative size.
        let flat = try #require(AppearancePreferences(rawValue: #"{"font":"serif","boldText":true,"fontWidth":"condensed"}"#))
        #expect(flat.reading.font == .serif && flat.reading.weight == .bold && flat.reading.width == .condensed)
        #expect(flat.reading.scale == .standard && flat.reading.letterSpacing == .standard && flat.reading.textSize == .system)
    }

    #if canImport(UIKit)
    @Test func theFactoryLookReadsAsNothingCustom() {
        let factory = AppearancePreferences()
        #expect(!factory.titlePagesSummary.contains("Custom order"))
        var reordered = factory
        reordered.titleSectionOrder = [.episodes, .cast, .reviews]
        #expect(reordered.titlePagesSummary.contains("Custom order"))
        #expect(AppearancePreferences.Preset.netflix.applied(to: factory).titlePagesSummary.contains("Cast first"))
        #expect(AppearancePreferences.AnimationSpeed.allCases.allSatisfy { $0.label != "Default" })
    }

    @Test func posterBackgroundSummaryAndBackdropContrast() throws {
        var appearance = AppearancePreferences()
        #expect(!appearance.titlePagesSummary.contains("Poster background"))
        appearance.blursBackground = true
        #expect(appearance.titlePagesSummary.contains("Poster background"))
        #expect(!appearance.titlePagesSummary.contains("Blurred background"))

        let white = try solidImage(red: 1, green: 1, blue: 1)
        let whiteBackdrop = try #require(TitleBackdropRequest(
            image: white, frame: CGSize(width: 390, height: 520), visibleBottom: 520, alignsTop: true, pageWidth: 390, scale: 1
        ).render())
        let whiteRGB = try middleRGB(of: whiteBackdrop)
        #expect(whiteRGB.red <= 0.35 && whiteRGB.green <= 0.35 && whiteRGB.blue <= 0.35)
        #expect(whiteRGB.red >= 0.15)

        let red = try solidImage(red: 1, green: 0, blue: 0)
        let redBackdrop = try #require(TitleBackdropRequest(
            image: red, frame: CGSize(width: 390, height: 520), visibleBottom: 520, alignsTop: true, pageWidth: 390, scale: 1
        ).render())
        let redRGB = try middleRGB(of: redBackdrop)
        #expect(redRGB.red - redRGB.green > 0.15 && redRGB.red - redRGB.blue > 0.15)
    }

    private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat, size: CGSize = CGSize(width: 80, height: 120)) throws -> UIImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let width = Int(size.width), height = Int(size.height)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let color = try #require(CGColor(colorSpace: colorSpace, components: [red, green, blue, 1]))
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: size))
        return UIImage(cgImage: try #require(context.makeImage()))
    }

    private func middleRGB(of image: UIImage) throws -> (red: Double, green: Double, blue: Double) {
        let cgImage = try #require(image.cgImage)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let offset = (width / 2) * 4
        return (Double(bytes[offset]) / 255, Double(bytes[offset + 1]) / 255, Double(bytes[offset + 2]) / 255)
    }
    #endif

    @Test func savedReadsTheDefaultsAndResetForgets() throws {
        let suite = "AppearancePreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppearancePreferences.saved(in: defaults).isDefault)
        var appearance = AppearancePreferences()
        appearance.accent = .green
        defaults.set(appearance.rawValue, forKey: AppearancePreferences.defaultsKey)
        #expect(AppearancePreferences.saved(in: defaults).accent == .green)
        AppearancePreferences.reset(in: defaults)
        #expect(AppearancePreferences.saved(in: defaults).isDefault)
    }

    @Test func aPresetIsRecognisedAndLeavesTheListenersOwnChoicesAlone() {
        var appearance = AppearancePreferences()
        appearance.showsReviews = false
        appearance.startTab = .discover
        appearance.heroAutoAdvance = 8
        appearance.animationSpeed = .off
        appearance.textSize = .accessibility2
        #expect(appearance.preset == nil)
        let disney = AppearancePreferences.Preset.disneyPlus.applied(to: appearance)
        #expect(disney.preset == .disneyPlus)
        #expect(disney.accent == .royal && disney.background == .navy)
        // The app's own spotlight and tab bar come with it.
        #expect(disney.heroAutoAdvance == 5 && !disney.phoneTabTitles && !disney.minimisesTabBar)
        #expect(!disney.showsReviews)
        #expect(disney.startTab == .discover)
        #expect(disney.animationSpeed == .off)
        #expect(disney.textSize == .accessibility2)
        var custom = disney
        custom.accent = .green
        #expect(custom.preset == nil)
    }

    @Test func aPresetShapesTheArtworkAndKeepsTheControlsRound() {
        var appearance = AppearancePreferences()
        appearance.cornerOverrides = [AppearancePreferences.CornerGroup.reviews.rawValue: 2]
        let netflix = AppearancePreferences.Preset.netflix.applied(to: appearance)
        #expect(netflix.cornerScale(for: .artwork) == 0.4 && netflix.cornerScale(for: .reviews) == 0.4)
        #expect(netflix.cornerScale(for: .playButton) == 0.3 && netflix.cornerScale(for: .filters) == 1)
        #expect(netflix.effectiveShelfSpacingScale == netflix.spacingScale && !netflix.showsShelfDividers)
        #expect(netflix.orderedTitleSections.prefix(2).elementsEqual([.episodes, .cast]))
        #expect(AppearancePreferences.Preset.appleTV.applied(to: appearance).cornerScale(for: .playButton) == 1)
        let arthouse = AppearancePreferences.Preset.arthouse.applied(to: appearance)
        #expect(arthouse.cornerScale(for: .filters) == 0 && arthouse.cornerScale(for: .actionButtons) == 1)
        #expect(arthouse.uppercaseCaptions && arthouse.artworkTone == .mono && arthouse.layout == .editorial)
        #expect(AppearancePreferences.Preset.appleTV.applied(to: arthouse).layout == .standard)
        #expect(AppearancePreferences.Preset.original.applied(to: arthouse).cornerOverrides == AppearancePreferences().cornerOverrides)
        // The other presets keep their own background, finish and gaps.
        #expect(arthouse.background == .black && arthouse.buttonFinish == .glass && arthouse.spacingScale == 1.25)
        let plex = AppearancePreferences.Preset.plex.applied(to: appearance)
        #expect(plex.spacingScale == 1 && plex.background == .charcoal)
    }

    @Test func presetsSetPlayTheButtonsFinishHeadingsAndHover() throws {
        let netflix = AppearancePreferences.Preset.netflix.applied(to: AppearancePreferences())
        #expect(netflix.playStyle == .white && netflix.buttonFinish == .solid && !netflix.hover.showsRim)
        let letterboxd = AppearancePreferences.Preset.letterboxd.applied(to: AppearancePreferences())
        #expect(letterboxd.headingColour == .secondary && letterboxd.playStyle == .accent && letterboxd.hover.cardLift == 0)
        let appleTV = AppearancePreferences.Preset.appleTV.applied(to: netflix)
        #expect(appleTV.buttonFinish == .glass && appleTV.playStyle == .white)
        #expect(AppearancePreferences.Preset.original.applied(to: letterboxd).hover == AppearancePreferences.Hover())
        var look = netflix
        look.headingColour = .accent
        let restored = try #require(AppearancePreferences(rawValue: look.rawValue))
        #expect(restored == look)
        #expect(look.restoringDefaults(of: .colour).playStyle == .artwork && look.restoringDefaults(of: .colour).buttonFinish == .glass)
        #expect(look.restoringDefaults(of: .text).headingColour == .primary)
    }

    @Test func everyPresetIsItsOwn() {
        let looks = AppearancePreferences.Preset.allCases.map { $0.applied(to: AppearancePreferences()) }
        for (preset, look) in zip(AppearancePreferences.Preset.allCases, looks) {
            #expect(look.preset == preset, "\(preset)")
        }
    }

    @Test func aPresetKeepsTheMixedColours() {
        var appearance = AppearancePreferences()
        appearance.customAccent = .init(red: 1, green: 0, blue: 0)
        appearance.customBackground = .init(red: 0, green: 0.1, blue: 0)
        let arthouse = AppearancePreferences.Preset.arthouse.applied(to: appearance)
        #expect(arthouse.customAccent == appearance.customAccent)
        #expect(arthouse.customBackground == appearance.customBackground)
    }

    @Test func restoringASectionLeavesTheOthers() {
        var appearance = AppearancePreferences()
        appearance.accent = .red
        appearance.cardScale = 1.5
        appearance.hidesSpoilers = true
        appearance.showsFranchise = false
        appearance.showsWatchAnywhere = false
        let restored = appearance.restoringDefaults(of: .cards)
        #expect(restored.cardScale == 1)
        #expect(restored.accent == .red && restored.hidesSpoilers && !restored.showsFranchise && !restored.showsWatchAnywhere)
        #expect(restored.isDefault(.cards) && !restored.isDefault(.colour) && !restored.isDefault(.titlePages))
        let restoredTitlePages = restored.restoringDefaults(of: .titlePages)
        #expect(restoredTitlePages.isDefault(.titlePages) && restoredTitlePages.showsFranchise && restoredTitlePages.showsWatchAnywhere)
        for section in AppearancePreferences.Section.allCases {
            #expect(AppearancePreferences().isDefault(section))
        }
        let all = AppearancePreferences.Section.allCases.reduce(appearance) { $0.restoringDefaults(of: $1) }
        #expect(all.isDefault)
    }

    @Test func theTintedBackgroundFollowsItsStrength() {
        var appearance = AppearancePreferences()
        appearance.accent = .white
        appearance.background = .tinted
        appearance.tintStrength = 0.2
        let rgb = appearance.backgroundRGB
        #expect(abs(rgb.red - 0.92 * 0.2) < 0.0001)
    }

    @Test func theLayoutKeyFollowsWhatChangesACardsHeight() {
        var appearance = AppearancePreferences()
        let original = appearance.layoutKey
        appearance.accent = .red
        appearance.artworkTone = .mono
        #expect(appearance.layoutKey == original)
        appearance.captionLines = 2
        #expect(appearance.layoutKey != original)
        appearance.captionLines = 1
        appearance.cardScale = 1.05
        #expect(appearance.layoutKey != original)
    }

    @Test func looksAreSavedByNameAndReplaced() throws {
        var looks = AppearanceLooks()
        var appearance = AppearancePreferences()
        appearance.accent = .pink
        looks.save(appearance, as: "  Night  ")
        looks.save(AppearancePreferences(), as: "")
        #expect(looks.looks.map(\.name) == ["Night", "Look 2"])
        appearance.accent = .mint
        looks.save(appearance, as: "night")
        #expect(looks.looks.count == 2)
        #expect(looks.looks[0].appearance.accent == .mint)
        let restored = try #require(AppearanceLooks(rawValue: looks.rawValue))
        #expect(restored == looks)
    }

    @Test func hoverDefaultsAreTheOriginalFeedback() {
        let hover = AppearancePreferences().hover
        #expect(hover.buttonBrightness == 0.15 && abs(hover.buttonScale - 1.025) < 0.0001)
        #expect(hover.glassFillOpacity == 0.18 && hover.glassRimOpacity == 0.35)
        #expect(abs(hover.segmentFillOpacity - 0.16) < 0.0001 && abs(hover.segmentRimOpacity - 0.3) < 0.0001)
        #expect(abs(hover.cardFillOpacity - 0.08) < 0.0001 && abs(hover.cardScale - 1.04) < 0.0001 && hover.castsShadow)
        #expect(hover.glowOpacity == 0.04 && hover.usesSystemHighlight && hover.duration(0.12) == 0.12)
    }

    @Test func hoverRoundTripsAndAnOldSaveReadsTheDefaults() throws {
        var appearance = AppearancePreferences()
        appearance.hover.brightness = 0.3
        appearance.hover.showsRim = false
        appearance.hover.speed = .instant
        let restored = try #require(AppearancePreferences(rawValue: appearance.rawValue))
        #expect(restored == appearance)
        #expect(restored.hover.glassRimOpacity == 0 && restored.hover.duration(0.12) == nil)

        let old = try #require(AppearancePreferences(rawValue: #"{"accent":"mint"}"#))
        #expect(old.hover == AppearancePreferences.Hover())
        let clamped = try #require(AppearancePreferences(rawValue: #"{"hover":{"brightness":9,"isEnabled":false}}"#))
        #expect(clamped.hover.brightness == AppearancePreferences.Hover.brightnessRange.upperBound && clamped.hover.buttonScale == 1)
    }

    @Test func restoringHoverLeavesTheRestAndPresetsSetTheirOwnHover() {
        var appearance = AppearancePreferences()
        appearance.accent = .mint
        appearance.hover.cardLift = 0.1
        #expect(!appearance.isDefault(.hover))
        let restored = appearance.restoringDefaults(of: .hover)
        #expect(restored.isDefault(.hover) && restored.accent == .mint)
        // A preset brings its app's hover; Arthouse's is the original feedback.
        #expect(AppearancePreferences.Preset.arthouse.applied(to: appearance).hover == AppearancePreferences.Hover())
        #expect(AppearancePreferences.Preset.disneyPlus.applied(to: appearance).hover.rimStrength == 1)
    }
}
