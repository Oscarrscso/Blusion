import Foundation

extension AppearancePreferences {
    /// Ready-made looks, each the look of a streaming or film app as closely as these settings draw it: its canvas and accent, how its
    /// rows are titled, its cards' size, corners, gaps and captions, its progress line, its Home spotlight, the order of its title
    /// pages, its transitions and, on iPhone, its tab bar. Arthouse is the app's own editorial look (`Layout`).
    ///
    /// Applying one sets all of that together, with Play's fill, whether the buttons are glass, the headings' colour and the Mac's hover.
    /// The listener's text size, custom colours, start tab, Home's Continue Watching bar, the title page sections shown, spoiler hiding
    /// and animation speed stay their own.
    enum Preset: String, Sendable, CaseIterable, Identifiable {
        case original, netflix, appleTV, disneyPlus, primeVideo, letterboxd, plex, arthouse

        var id: String { rawValue }

        var label: String {
            switch self {
            case .original: "Original"
            case .netflix: "Netflix"
            case .appleTV: "Apple TV"
            case .disneyPlus: "Disney+"
            case .primeVideo: "Prime Video"
            case .letterboxd: "Letterboxd"
            case .plex: "Plex"
            case .arthouse: "Arthouse"
            }
        }

        /// The glass buttons, filters, the player and Settings' rows keep the capsules and circles they are drawn with, whatever a preset
        /// does to the posters, cards and panels. Play keeps its capsule too, unless the app squares it.
        static let controlCorners: [String: Double] = Dictionary(uniqueKeysWithValues: [
            CornerGroup.playButton, .actionButtons, .filters, .playerControls, .settingsRows,
        ].map { ($0.rawValue, 1) })

        /// Play as a rectangle with small rounded corners, as Netflix, Disney+ and Prime Video draw it.
        static let squarePlay = 0.3

        /// `appearance` with this preset's look.
        func applied(to appearance: AppearancePreferences) -> AppearancePreferences {
            var look = AppearancePreferences()
            if self != .original {
                // The themed looks keep their own typography, spacing and section order.
                look.background = .black
                look.buttonFinish = .glass
                look.reading = TextStyle()
                look.spacingScale = 1
                look.shelfSpacingScale = nil
                look.sideMarginScale = 1
                look.showsShelfDividers = false
                look.shelfDividerFullWidth = false
                look.shelfDividerThickness = 1
                look.shelfDividerOpacity = 0.12
                look.cornerOverrides = Self.controlCorners
                look.includesCircularButtons = false
                look.outlinesButtons = false
                look.titleSectionOrder = []
                look.showsTitlePageTabBar = false
            }
            switch self {
            case .original:
                break
            case .netflix:
                // Red on #141414, kept for progress and the switches. Small bold row titles set close; smaller box art with 4-point
                // corners, no captions, in very tight rows; rectangles throughout: Play, the title page's buttons (circles included),
                // the stream cards, reviews and Settings' rows, with capsule filters as Netflix's chips are; a tall billboard that stays
                // on its title, without dots; a thin red line with no minutes; Cast before Reviews; labelled tabs on a fixed bar.
                look.accent = .crimson
                look.background = .graphite
                look.headingWeight = .bold
                look.headingSize = .small
                look.headingSpacing = .tight
                look.cardScale = 0.9
                look.spacingScale = 0.5
                look.cornerScale = 0.4
                look.cornerOverrides[CornerGroup.playButton.rawValue] = Self.squarePlay
                look.cornerOverrides[CornerGroup.actionButtons.rawValue] = Self.squarePlay
                look.cornerOverrides[CornerGroup.settingsRows.rawValue] = 0.4
                look.includesCircularButtons = true
                look.outline = .off
                look.progressColour = .accent
                look.progressThickness = .thin
                look.showsTimeLeft = false
                look.showsPageDots = false
                look.sectionOrder = .castFirst
                look.phoneTabTitles = true
                look.minimisesTabBar = false
                // A white Play and flat grey buttons, no glass; on the Mac a card grows on hover, without rim or glow.
                look.playStyle = .white
                look.buttonFinish = .solid
                look.hover.grow = 0.05
                look.hover.cardLift = 0.1
                look.hover.showsRim = false
                look.hover.showsGlow = false
                look.hover.speed = .fast
            case .appleTV:
                // Black with white as the accent. Large bold row titles; big cards, two across in grids, with generous rounded
                // corners (reviews, stream cards and Settings' rows alike) and wide gaps, each titled with its genre and year
                // underneath; a tall spotlight turning every 8 seconds with its dots; a white line with the minutes left; Cast before
                // Reviews; labelled tabs on a bar that shrinks.
                look.accent = .white
                look.headingSize = .large
                look.cardScale = 1.25
                look.spacingScale = 1.35
                look.phoneGridColumns = 2
                look.cornerScale = 1.4
                look.cornerOverrides[CornerGroup.settingsRows.rawValue] = 1.4
                look.outline = .off
                look.showsPosterTitles = true
                look.lineSpacing = .relaxed
                look.heroAutoAdvance = 8
                look.sectionOrder = .castFirst
                look.phoneTabTitles = true
                // A white Play on Apple's own glass; on the Mac a card lifts with its shadow and a soft glow.
                look.playStyle = .white
                look.hover.cardLift = 0.06
                look.hover.glowStrength = 0.1
                look.hover.showsRim = false
            case .disneyPlus:
                // Royal blue on Disney+'s navy. Semibold row titles with a little air; rounded tiles with a visible edge, as Disney+
                // outlines its tiles; a squared Play beside round buttons; rounded-rectangle filters; a shorter banner turning every
                // 5 seconds with its dots; a blue line; icon-only tabs on a bar that stays put.
                look.accent = .royal
                look.background = .navy
                look.headingWeight = .semibold
                look.headingSpacing = .wide
                look.cardScale = 1.05
                look.spacingScale = 1.1
                look.cornerScale = 0.8
                look.cornerOverrides[CornerGroup.playButton.rawValue] = Self.squarePlay
                look.cornerOverrides[CornerGroup.filters.rawValue] = 0.5
                look.cornerOverrides[CornerGroup.settingsRows.rawValue] = 0.8
                look.outline = .standard
                look.progressColour = .accent
                look.heroAutoAdvance = 5
                look.phoneTabTitles = false
                look.minimisesTabBar = false
                // A white Play and flat buttons; on the Mac a tile lifts inside a bright white rim, as Disney+ frames the one in focus.
                look.playStyle = .white
                look.buttonFinish = .solid
                look.hover.cardLift = 0.05
                look.hover.rimStrength = 1
                look.hover.showsGlow = false
            case .primeVideo:
                // Sky blue on Prime Video's ink. Small bold row titles set close; 6-point cards in close rows; a squared Play and
                // rounded-rectangle buttons beside round icons; a spotlight turning every 8 seconds with its dots; a thin blue line;
                // labelled tabs on a bar that stays put.
                look.accent = .sky
                look.background = .ink
                look.headingSize = .small
                look.headingSpacing = .tight
                look.cardScale = 0.95
                look.spacingScale = 0.75
                look.cornerScale = 0.6
                look.cornerOverrides[CornerGroup.playButton.rawValue] = Self.squarePlay
                look.cornerOverrides[CornerGroup.actionButtons.rawValue] = 0.5
                look.cornerOverrides[CornerGroup.settingsRows.rawValue] = 0.6
                look.outline = .off
                look.progressColour = .accent
                look.progressThickness = .thin
                look.heroAutoAdvance = 8
                look.phoneTabTitles = true
                look.minimisesTabBar = false
                // A sky-blue Play and flat buttons; on the Mac a card lifts and brightens, without rim or glow.
                look.playStyle = .accent
                look.buttonFinish = .solid
                look.hover.cardLift = 0.07
                look.hover.brightness = 0.2
                look.hover.showsRim = false
                look.hover.showsGlow = false
            case .letterboxd:
                // Green on Letterboxd's steel. Small semibold spaced capitals for section titles and relaxed lines for reading
                // reviews; a dense wall of small posters, four across, with 3-point corners, a faint edge and narrow gaps; small-cornered
                // filters, reviews and Settings' rows; a short backdrop that stays put, without dots; a thin green line with no
                // minutes; the synopsis unfolded and Reviews first; cards open without zooming; icon-only tabs.
                look.accent = .green
                look.background = .steel
                look.headingWeight = .semibold
                look.headingSize = .small
                look.headingSpacing = .wide
                look.uppercaseHeadings = true
                look.lineSpacing = .relaxed
                look.cardScale = 0.75
                look.spacingScale = 0.6
                look.phoneGridColumns = 4
                look.cornerScale = 0.3
                look.cornerOverrides[CornerGroup.filters.rawValue] = 0.3
                look.cornerOverrides[CornerGroup.settingsRows.rawValue] = 0.3
                look.outline = .faint
                look.progressColour = .accent
                look.progressThickness = .thin
                look.showsTimeLeft = false
                look.showsPageDots = false
                look.expandsSynopsis = true
                look.zoomTransitions = false
                look.phoneTabTitles = false
                // Grey section titles; a green Play and flat buttons; on the Mac a poster stays put and takes an outline.
                look.headingColour = .secondary
                look.playStyle = .accent
                look.buttonFinish = .solid
                look.hover.grow = 0
                look.hover.cardLift = 0
                look.hover.cardShadow = false
                look.hover.rimStrength = 0.7
                look.hover.showsGlow = false
                look.hover.speed = .instant
            case .plex:
                // Amber on Plex's charcoal. Semibold row titles; 5-point posters, each titled with its year underneath, as a media
                // library lists them; rounded-rectangle filters and Settings' rows; a shorter spotlight that stays put, without dots;
                // a thick amber line; Cast before Reviews; labelled tabs.
                look.accent = .amber
                look.background = .charcoal
                look.headingWeight = .semibold
                look.cornerScale = 0.5
                look.cornerOverrides[CornerGroup.filters.rawValue] = 0.4
                look.cornerOverrides[CornerGroup.settingsRows.rawValue] = 0.5
                look.outline = .off
                look.showsPosterTitles = true
                look.progressColour = .accent
                look.progressThickness = .thick
                look.showsPageDots = false
                look.sectionOrder = .castFirst
                look.phoneTabTitles = true
                // An amber Play and flat buttons; on the Mac a poster lifts a little inside a rim.
                look.playStyle = .accent
                look.buttonFinish = .solid
                look.hover.cardLift = 0.03
                look.hover.rimStrength = 0.6
                look.hover.showsGlow = false
            case .arthouse:
                // Editorial: condensed text, large medium-weight capitals for headings and titles, black-and-white stills in square
                // frames with their captions, olive as the one colour, and square tags.
                look.accent = .olive
                look.fontWidth = .condensed
                look.headingWeight = .medium
                look.headingSize = .huge
                look.uppercaseHeadings = true
                look.cardScale = 1.2
                look.spacingScale = 1.25
                look.phoneGridColumns = 2
                look.cornerScale = 0
                look.cornerOverrides[CornerGroup.filters.rawValue] = nil
                look.showsPosterTitles = true
                look.captionLines = 2
                look.uppercaseCaptions = true
                look.outline = .off
                look.artworkTone = .mono
                look.progressThickness = .thin
                look.layout = .editorial
            }
            var result = appearance
            result.takeLook(from: look)
            return result
        }
    }
}
