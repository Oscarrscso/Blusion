import Foundation

/// How the app looks, as the listener sets it on Settings → Appearance: colour (accent, page background), text (size, font, width,
/// weight, slant, spacing, and a style of its own for headings), cards (size, corners, spacing, columns, captions, outline, artwork tone,
/// progress bars), Home's spotlight, title pages (sections, their order, spoilers) and motion and navigation (start tab, transitions,
/// animation speed, the iPhone's tab bar).
///
/// Saved as one JSON string under `defaultsKey` in the standard defaults, so screens read it with `@AppStorage` and follow a change at
/// once. The root applies it (`appliesAppearance()`); cards and grids read it through `LayoutMetrics`. Every field decodes on its own, so
/// a value added later keeps older saves loading, and the fields that used to be fixed steps (card size, corners, spacing, the outline
/// switch) read the old steps into the new values. The defaults live here and nowhere else: Olive on Graphite, flat buttons, square
/// corners, the tightest gaps and a thin progress line.
public struct AppearancePreferences: Sendable, Equatable, Codable {
    public static let defaultsKey = "settings.appearance"

    // MARK: - Ranges and options

    public static let cardScaleRange: ClosedRange<Double> = 0.6...1.6
    public static let cornerScaleRange: ClosedRange<Double> = 0...2.5
    public static let spacingScaleRange: ClosedRange<Double> = 0.3...2
    public static let shelfSpacingScaleRange: ClosedRange<Double> = 0...3
    public static let sideMarginScaleRange: ClosedRange<Double> = 0...2
    public static let shelfDividerThicknessRange: ClosedRange<Double> = 0.5...4
    public static let shelfDividerOpacityRange: ClosedRange<Double> = 0.03...0.6
    public static let tintStrengthRange: ClosedRange<Double> = 0.04...0.3
    /// The column counts a phone's portrait and landscape title grids offer.
    public static let phoneGridColumnRange: ClosedRange<Int> = 2...6
    public static let captionLineRange: ClosedRange<Int> = 1...2
    /// Seconds between the spotlight's pages turning by themselves; zero leaves them for the listener to swipe.
    public static let heroAutoAdvanceOptions = [0, 5, 8, 12, 20, 30]

    // MARK: - Colour

    public var accent: Accent = .olive
    /// The accent when `accent` is `.custom`. Kept when another accent is chosen, so going back to Custom finds it again.
    public var customAccent = RGB(red: 0.42, green: 0.51, blue: 1)
    public var background: Background = .graphite
    /// The background when `background` is `.custom`. Kept like the custom accent.
    public var customBackground = RGB(red: 0.06, green: 0.06, blue: 0.08)
    /// How much of the accent the Tinted background has, as a share of the accent's own brightness (`tintStrengthRange`).
    public var tintStrength: Double = 0.11
    public var playStyle: PlayStyle = .artwork
    public var buttonFinish: ButtonFinish = .solid

    // MARK: - Text

    public var textSize: TextSize = .system
    public var font: FontStyle = .standard
    public var boldText = false
    public var italicText = false
    public var fontWidth: FontWidth = .standard
    public var letterSpacing: LetterSpacing = .standard
    public var lineSpacing: LineSpacing = .standard
    public var headingFont: HeadingFont = .matchText
    public var headingWeight: HeadingWeight = .bold
    public var headingSize: HeadingSize = .standard
    public var headingWidth: HeadingWidth = .matchText
    public var headingSpacing: HeadingSpacing = .matchText
    public var uppercaseHeadings = false
    public var headingColour: HeadingColour = .primary

    // MARK: - Cards

    /// Every card's width in shelves and wide grids, as a share of the layout's own (`cardScaleRange`).
    public var cardScale: Double = 1
    /// The roundness of posters, cards, tiles and stills, as a share of their own radius (`cornerScaleRange`). Zero is square.
    public var cornerScale: Double = 0
    /// Missing entries follow the global corner scale; overrides are absolute, not multiplied by it.
    public var cornerOverrides: [String: Double] = [:]
    public var includesCircularButtons = false

    public func cornerScale(for group: CornerGroup) -> Double {
        cornerOverrides[group.rawValue] ?? cornerScale
    }
    /// The gaps between cards and between shelves, as a share of the layout's own (`spacingScaleRange`).
    public var spacingScale: Double = 0.3
    /// The gap between shelves on its own; nil follows `spacingScale`.
    public var shelfSpacingScale: Double?
    /// The page's left and right margin, as a share of the layout's own (it also follows `spacingScale`, so tight spacing reaches the edges).
    public var sideMarginScale: Double = 1
    /// A horizontal line between shelves, with its thickness, strength and whether it runs edge to edge.
    public var showsShelfDividers = false
    public var shelfDividerThickness: Double = 1
    public var shelfDividerOpacity: Double = 0.12
    public var shelfDividerFullWidth = false
    public var effectiveShelfSpacingScale: Double { shelfSpacingScale ?? spacingScale }
    /// Poster columns of a grid (Library, Discover, See All) on a phone held upright.
    public var phoneGridColumns = 3
    /// Title columns on a phone held sideways, independently of the portrait grid.
    public var phoneLandscapeGridColumns = 3
    /// Every poster carries its title and a grey line underneath, as landscape and square cards do.
    public var showsPosterTitles = false
    /// Lines a card's title may take under it before it is cut off (`captionLineRange`). Every card of a kind keeps the same height.
    public var captionLines = 1
    /// The grey line under a card's title ("Drama · 2008").
    public var showsCaptionDetails = true
    /// A card's title in capitals.
    public var uppercaseCaptions = false
    public var outline: Outline = .standard
    public var artworkTone: ArtworkTone = .natural
    public var progressColour: ProgressColour = .white
    public var progressThickness: ProgressThickness = .thin
    /// The minutes left beside the progress line on Continue cards.
    public var showsTimeLeft = true

    // MARK: - Layout

    public var layout: Layout = .standard

    // MARK: - Home

    /// Seconds between the spotlight turning its page by itself; zero never (`heroAutoAdvanceOptions`).
    public var heroAutoAdvance = 0
    /// The dots under the spotlight that show which page it is on.
    public var showsPageDots = true

    // MARK: - Title pages

    /// Unwatched episodes on a title page hide what `spoilerStills`, `spoilerSynopses` and `spoilerTitles` say until they are started.
    public var hidesSpoilers = false
    public var spoilerStills = true
    public var spoilerSynopses = true
    public var spoilerTitles = false
    /// The synopsis opens unfolded.
    public var expandsSynopsis = false
    /// The title page's sections below the episodes.
    public var showsReviews = true
    public var showsCast = true
    public var showsInformation = true
    public var showsRelated = true
    /// Where the title can be watched in the viewer's region, from TMDb. Off until turned on, as it asks TMDb for each title.
    public var showsWatchAnywhere = false
    public var sectionOrder: SectionOrder = .reviewsFirst

    // MARK: - Navigation and motion

    public var startTab: StartTab = .home
    /// A card zooms into the title it opens, and the title zooms back into it.
    public var zoomTransitions = true
    public var animationSpeed: AnimationSpeed = .standard
    /// The iPhone's tab bar names its tabs under their icons.
    public var phoneTabTitles = false
    /// The iPhone's tab bar shrinks while a page scrolls down.
    public var minimisesTabBar = true
    /// The Continue Watching bar above the iPhone's tab bar.
    public var showsContinueBar = true

    // MARK: - Hover

    /// The Mac's hover feedback.
    public var hover = Hover()

    public init() {}

    /// Copies what a preset sets from `look`: colour, Play's fill and the buttons' finish, text but its size, cards, corners, the layout,
    /// Home's spotlight, the title page's layout, zoom transitions, the iPhone's tab bar and the Mac's hover. The custom colours stay.
    mutating func takeLook(from look: AppearancePreferences) {
        accent = look.accent
        background = look.background
        tintStrength = look.tintStrength
        playStyle = look.playStyle
        buttonFinish = look.buttonFinish
        font = look.font
        boldText = look.boldText
        italicText = look.italicText
        fontWidth = look.fontWidth
        letterSpacing = look.letterSpacing
        lineSpacing = look.lineSpacing
        headingFont = look.headingFont
        headingWeight = look.headingWeight
        headingSize = look.headingSize
        headingWidth = look.headingWidth
        headingSpacing = look.headingSpacing
        uppercaseHeadings = look.uppercaseHeadings
        headingColour = look.headingColour
        cardScale = look.cardScale
        cornerScale = look.cornerScale
        cornerOverrides = look.cornerOverrides
        includesCircularButtons = look.includesCircularButtons
        spacingScale = look.spacingScale
        shelfSpacingScale = look.shelfSpacingScale
        sideMarginScale = look.sideMarginScale
        showsShelfDividers = look.showsShelfDividers
        shelfDividerThickness = look.shelfDividerThickness
        shelfDividerOpacity = look.shelfDividerOpacity
        shelfDividerFullWidth = look.shelfDividerFullWidth
        phoneGridColumns = look.phoneGridColumns
        phoneLandscapeGridColumns = look.phoneLandscapeGridColumns
        showsPosterTitles = look.showsPosterTitles
        captionLines = look.captionLines
        showsCaptionDetails = look.showsCaptionDetails
        uppercaseCaptions = look.uppercaseCaptions
        outline = look.outline
        artworkTone = look.artworkTone
        progressColour = look.progressColour
        progressThickness = look.progressThickness
        showsTimeLeft = look.showsTimeLeft
        layout = look.layout
        heroAutoAdvance = look.heroAutoAdvance
        showsPageDots = look.showsPageDots
        expandsSynopsis = look.expandsSynopsis
        sectionOrder = look.sectionOrder
        zoomTransitions = look.zoomTransitions
        phoneTabTitles = look.phoneTabTitles
        minimisesTabBar = look.minimisesTabBar
        hover = look.hover
    }

    // MARK: - Coding

    /// Written out, rather than synthesised, so that each field falls back to its default on its own, so that the old fixed steps read
    /// into their new values, and so that the JSON coding never goes through `RawRepresentable`'s, which would call `rawValue`, which
    /// encodes again.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
            (try? container.decode(Value.self, forKey: key)) ?? fallback
        }
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        func legacy(_ key: CodingKeys, _ steps: [String: Double]) -> Double? {
            (try? container.decode(String.self, forKey: key)).flatMap { steps[$0] }
        }
        accent = read(.accent, accent)
        customAccent = read(.customAccent, customAccent)
        background = read(.background, background)
        customBackground = read(.customBackground, customBackground)
        tintStrength = clamp(read(.tintStrength, tintStrength), Self.tintStrengthRange, 0.11)
        playStyle = read(.playStyle, playStyle)
        buttonFinish = read(.buttonFinish, buttonFinish)

        textSize = read(.textSize, textSize)
        font = read(.font, font)
        boldText = read(.boldText, boldText)
        italicText = read(.italicText, italicText)
        fontWidth = read(.fontWidth, fontWidth)
        letterSpacing = read(.letterSpacing, letterSpacing)
        lineSpacing = read(.lineSpacing, lineSpacing)
        headingFont = read(.headingFont, headingFont)
        headingWeight = read(.headingWeight, headingWeight)
        headingSize = read(.headingSize, headingSize)
        headingWidth = read(.headingWidth, headingWidth)
        headingSpacing = read(.headingSpacing, headingSpacing)
        uppercaseHeadings = read(.uppercaseHeadings, uppercaseHeadings)
        headingColour = read(.headingColour, headingColour)

        // Card size, corners and spacing were fixed steps saved by name; a save from then reads the step's value.
        cardScale = clamp(read(.cardSize, legacy(.legacyCardScale, Self.legacyCardScales) ?? 1), Self.cardScaleRange, 1)
        cornerScale = clamp(read(.cornerScale, legacy(.legacyCorners, Self.legacyCornerScales) ?? cornerScale), Self.cornerScaleRange,
                            cornerScale)
        cornerOverrides = read(.cornerOverrides, cornerOverrides).filter { key, value in
            CornerGroup(rawValue: key) != nil && value.isFinite
        }.mapValues { min(max($0, Self.cornerScaleRange.lowerBound), Self.cornerScaleRange.upperBound) }
        includesCircularButtons = read(.includesCircularButtons, includesCircularButtons)
        spacingScale = clamp(read(.spacing, legacy(.legacyDensity, Self.legacySpacingScales) ?? spacingScale), Self.spacingScaleRange,
                             spacingScale)
        shelfSpacingScale = (try? container.decodeIfPresent(Double.self, forKey: .shelfSpacing)).flatMap { $0 }
            .map { clamp($0, Self.shelfSpacingScaleRange, spacingScale) }
        sideMarginScale = clamp(read(.sideMargin, sideMarginScale), Self.sideMarginScaleRange, sideMarginScale)
        showsShelfDividers = read(.showsShelfDividers, showsShelfDividers)
        shelfDividerThickness = clamp(read(.shelfDividerThickness, shelfDividerThickness), Self.shelfDividerThicknessRange,
                                      shelfDividerThickness)
        shelfDividerOpacity = clamp(read(.shelfDividerOpacity, shelfDividerOpacity), Self.shelfDividerOpacityRange, shelfDividerOpacity)
        shelfDividerFullWidth = read(.shelfDividerFullWidth, shelfDividerFullWidth)
        phoneGridColumns = min(max(read(.phoneGridColumns, phoneGridColumns), Self.phoneGridColumnRange.lowerBound),
                               Self.phoneGridColumnRange.upperBound)
        phoneLandscapeGridColumns = min(max(read(.phoneLandscapeGridColumns, phoneLandscapeGridColumns), Self.phoneGridColumnRange.lowerBound),
                                        Self.phoneGridColumnRange.upperBound)
        showsPosterTitles = read(.showsPosterTitles, showsPosterTitles)
        captionLines = min(max(read(.captionLines, captionLines), Self.captionLineRange.lowerBound), Self.captionLineRange.upperBound)
        showsCaptionDetails = read(.showsCaptionDetails, showsCaptionDetails)
        uppercaseCaptions = read(.uppercaseCaptions, uppercaseCaptions)
        // The outline was a switch; off reads as Off.
        let legacyOutline: Outline? = (try? container.decode(Bool.self, forKey: .legacyArtworkOutline)).map { $0 ? .standard : .off }
        outline = read(.outline, legacyOutline ?? outline)
        artworkTone = read(.artworkTone, artworkTone)
        progressColour = read(.progressColour, progressColour)
        progressThickness = read(.progressThickness, progressThickness)
        showsTimeLeft = read(.showsTimeLeft, showsTimeLeft)
        layout = read(.layout, layout)

        let advance = read(.heroAutoAdvance, heroAutoAdvance)
        heroAutoAdvance = Self.heroAutoAdvanceOptions.contains(advance) ? advance : 0
        showsPageDots = read(.showsPageDots, showsPageDots)

        hidesSpoilers = read(.hidesSpoilers, hidesSpoilers)
        spoilerStills = read(.spoilerStills, spoilerStills)
        spoilerSynopses = read(.spoilerSynopses, spoilerSynopses)
        spoilerTitles = read(.spoilerTitles, spoilerTitles)
        expandsSynopsis = read(.expandsSynopsis, expandsSynopsis)
        showsReviews = read(.showsReviews, showsReviews)
        showsCast = read(.showsCast, showsCast)
        showsInformation = read(.showsInformation, showsInformation)
        showsWatchAnywhere = read(.showsWatchAnywhere, showsWatchAnywhere)
        showsRelated = read(.showsRelated, showsRelated)
        sectionOrder = read(.sectionOrder, sectionOrder)

        startTab = read(.startTab, startTab)
        zoomTransitions = read(.zoomTransitions, zoomTransitions)
        animationSpeed = read(.animationSpeed, animationSpeed)
        phoneTabTitles = read(.phoneTabTitles, phoneTabTitles)
        minimisesTabBar = read(.minimisesTabBar, minimisesTabBar)
        showsContinueBar = read(.showsContinueBar, showsContinueBar)

        hover = read(.hover, hover)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accent, forKey: .accent)
        try container.encode(customAccent, forKey: .customAccent)
        try container.encode(background, forKey: .background)
        try container.encode(customBackground, forKey: .customBackground)
        try container.encode(tintStrength, forKey: .tintStrength)
        try container.encode(playStyle, forKey: .playStyle)
        try container.encode(buttonFinish, forKey: .buttonFinish)

        try container.encode(textSize, forKey: .textSize)
        try container.encode(font, forKey: .font)
        try container.encode(boldText, forKey: .boldText)
        try container.encode(italicText, forKey: .italicText)
        try container.encode(fontWidth, forKey: .fontWidth)
        try container.encode(letterSpacing, forKey: .letterSpacing)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(headingFont, forKey: .headingFont)
        try container.encode(headingWeight, forKey: .headingWeight)
        try container.encode(headingSize, forKey: .headingSize)
        try container.encode(headingWidth, forKey: .headingWidth)
        try container.encode(headingSpacing, forKey: .headingSpacing)
        try container.encode(uppercaseHeadings, forKey: .uppercaseHeadings)
        try container.encode(headingColour, forKey: .headingColour)

        try container.encode(cardScale, forKey: .cardSize)
        try container.encode(cornerScale, forKey: .cornerScale)
        try container.encode(cornerOverrides, forKey: .cornerOverrides)
        try container.encode(includesCircularButtons, forKey: .includesCircularButtons)
        try container.encode(spacingScale, forKey: .spacing)
        try container.encodeIfPresent(shelfSpacingScale, forKey: .shelfSpacing)
        try container.encode(sideMarginScale, forKey: .sideMargin)
        try container.encode(showsShelfDividers, forKey: .showsShelfDividers)
        try container.encode(shelfDividerThickness, forKey: .shelfDividerThickness)
        try container.encode(shelfDividerOpacity, forKey: .shelfDividerOpacity)
        try container.encode(shelfDividerFullWidth, forKey: .shelfDividerFullWidth)
        try container.encode(phoneGridColumns, forKey: .phoneGridColumns)
        try container.encode(phoneLandscapeGridColumns, forKey: .phoneLandscapeGridColumns)
        try container.encode(showsPosterTitles, forKey: .showsPosterTitles)
        try container.encode(captionLines, forKey: .captionLines)
        try container.encode(showsCaptionDetails, forKey: .showsCaptionDetails)
        try container.encode(uppercaseCaptions, forKey: .uppercaseCaptions)
        try container.encode(outline, forKey: .outline)
        try container.encode(artworkTone, forKey: .artworkTone)
        try container.encode(progressColour, forKey: .progressColour)
        try container.encode(progressThickness, forKey: .progressThickness)
        try container.encode(showsTimeLeft, forKey: .showsTimeLeft)
        try container.encode(layout, forKey: .layout)

        try container.encode(heroAutoAdvance, forKey: .heroAutoAdvance)
        try container.encode(showsPageDots, forKey: .showsPageDots)

        try container.encode(hidesSpoilers, forKey: .hidesSpoilers)
        try container.encode(spoilerStills, forKey: .spoilerStills)
        try container.encode(spoilerSynopses, forKey: .spoilerSynopses)
        try container.encode(spoilerTitles, forKey: .spoilerTitles)
        try container.encode(expandsSynopsis, forKey: .expandsSynopsis)
        try container.encode(showsReviews, forKey: .showsReviews)
        try container.encode(showsCast, forKey: .showsCast)
        try container.encode(showsInformation, forKey: .showsInformation)
        try container.encode(showsRelated, forKey: .showsRelated)
        try container.encode(showsWatchAnywhere, forKey: .showsWatchAnywhere)
        try container.encode(sectionOrder, forKey: .sectionOrder)

        try container.encode(startTab, forKey: .startTab)
        try container.encode(zoomTransitions, forKey: .zoomTransitions)
        try container.encode(animationSpeed, forKey: .animationSpeed)
        try container.encode(phoneTabTitles, forKey: .phoneTabTitles)
        try container.encode(minimisesTabBar, forKey: .minimisesTabBar)
        try container.encode(showsContinueBar, forKey: .showsContinueBar)

        try container.encode(hover, forKey: .hover)
    }

    private enum CodingKeys: String, CodingKey {
        case accent, customAccent, background, customBackground, tintStrength, playStyle, buttonFinish
        case textSize, font, boldText, italicText, fontWidth, letterSpacing, lineSpacing, headingFont, headingWeight, headingSize,
             headingWidth, headingSpacing, uppercaseHeadings, headingColour
        case cornerOverrides, includesCircularButtons
        case shelfSpacing, sideMargin, showsShelfDividers, shelfDividerThickness, shelfDividerOpacity, shelfDividerFullWidth
        case cardSize, cornerScale, spacing, phoneGridColumns, showsPosterTitles, captionLines, showsCaptionDetails, uppercaseCaptions,
             outline, artworkTone, progressColour, progressThickness, showsTimeLeft
        case phoneLandscapeGridColumns
        case layout
        case heroAutoAdvance, showsPageDots
        case hidesSpoilers, spoilerStills, spoilerSynopses, spoilerTitles, expandsSynopsis, showsReviews, showsCast, showsInformation,
             showsRelated, showsWatchAnywhere, sectionOrder
        case startTab, zoomTransitions, animationSpeed, phoneTabTitles, minimisesTabBar, showsContinueBar
        case hover
        /// The fixed steps saved before the sliders, read once and never written.
        case legacyCardScale = "cardScale", legacyCorners = "corners", legacyDensity = "density", legacyArtworkOutline = "artworkOutline"
    }

    static let legacyCardScales: [String: Double] = ["small": 0.82, "standard": 1, "large": 1.2, "huge": 1.42]
    static let legacyCornerScales: [String: Double] = ["square": 0, "subtle": 0.5, "standard": 1, "round": 1.8]
    static let legacySpacingScales: [String: Double] = ["compact": 0.66, "standard": 1, "roomy": 1.35]

    /// Field by field. Written out so that equality never falls to `RawRepresentable`'s, which would compare the JSON text, and split
    /// into groups so the type checker stays quick.
    public static func == (lhs: AppearancePreferences, rhs: AppearancePreferences) -> Bool {
        let colours: Bool = lhs.accent == rhs.accent && lhs.customAccent == rhs.customAccent && lhs.background == rhs.background
            && lhs.customBackground == rhs.customBackground && lhs.tintStrength == rhs.tintStrength
            && lhs.playStyle == rhs.playStyle && lhs.buttonFinish == rhs.buttonFinish
        let text: Bool = lhs.textSize == rhs.textSize && lhs.font == rhs.font && lhs.boldText == rhs.boldText
            && lhs.italicText == rhs.italicText && lhs.fontWidth == rhs.fontWidth
        let spacing: Bool = lhs.letterSpacing == rhs.letterSpacing && lhs.lineSpacing == rhs.lineSpacing
        let headings: Bool = lhs.headingFont == rhs.headingFont && lhs.headingWeight == rhs.headingWeight
            && lhs.headingSize == rhs.headingSize && lhs.uppercaseHeadings == rhs.uppercaseHeadings
        let headingShape: Bool = lhs.headingWidth == rhs.headingWidth && lhs.headingSpacing == rhs.headingSpacing
            && lhs.headingColour == rhs.headingColour
        let sizes: Bool = lhs.cardScale == rhs.cardScale && lhs.cornerScale == rhs.cornerScale && lhs.spacingScale == rhs.spacingScale
            && lhs.phoneGridColumns == rhs.phoneGridColumns
            && lhs.phoneLandscapeGridColumns == rhs.phoneLandscapeGridColumns
            && lhs.shelfSpacingScale == rhs.shelfSpacingScale && lhs.sideMarginScale == rhs.sideMarginScale
            && lhs.showsShelfDividers == rhs.showsShelfDividers && lhs.shelfDividerThickness == rhs.shelfDividerThickness
            && lhs.shelfDividerOpacity == rhs.shelfDividerOpacity && lhs.shelfDividerFullWidth == rhs.shelfDividerFullWidth
            && lhs.cornerOverrides == rhs.cornerOverrides && lhs.includesCircularButtons == rhs.includesCircularButtons
        let captions: Bool = lhs.showsPosterTitles == rhs.showsPosterTitles && lhs.captionLines == rhs.captionLines
            && lhs.showsCaptionDetails == rhs.showsCaptionDetails && lhs.uppercaseCaptions == rhs.uppercaseCaptions
        let artwork: Bool = lhs.outline == rhs.outline && lhs.artworkTone == rhs.artworkTone
        let progress: Bool = lhs.progressColour == rhs.progressColour && lhs.progressThickness == rhs.progressThickness
            && lhs.showsTimeLeft == rhs.showsTimeLeft
        let home: Bool = lhs.heroAutoAdvance == rhs.heroAutoAdvance && lhs.showsPageDots == rhs.showsPageDots
        let spoilers: Bool = lhs.hidesSpoilers == rhs.hidesSpoilers && lhs.spoilerStills == rhs.spoilerStills
            && lhs.spoilerSynopses == rhs.spoilerSynopses && lhs.spoilerTitles == rhs.spoilerTitles
        let sections: Bool = lhs.expandsSynopsis == rhs.expandsSynopsis && lhs.showsReviews == rhs.showsReviews
            && lhs.showsCast == rhs.showsCast && lhs.showsInformation == rhs.showsInformation && lhs.showsRelated == rhs.showsRelated
            && lhs.showsWatchAnywhere == rhs.showsWatchAnywhere && lhs.sectionOrder == rhs.sectionOrder
        let navigation: Bool = lhs.startTab == rhs.startTab && lhs.zoomTransitions == rhs.zoomTransitions
            && lhs.animationSpeed == rhs.animationSpeed
        let tabs: Bool = lhs.phoneTabTitles == rhs.phoneTabTitles && lhs.minimisesTabBar == rhs.minimisesTabBar
            && lhs.showsContinueBar == rhs.showsContinueBar
        let hover: Bool = lhs.hover == rhs.hover && lhs.layout == rhs.layout
        return colours && text && spacing && headings && headingShape && sizes && captions && artwork && progress && home && spoilers
            && sections && navigation && tabs && hover
    }

    // MARK: - Reading

    /// The preset this look is, if it is one.
    public var preset: Preset? {
        Preset.allCases.first { $0.applied(to: self) == self }
    }

    /// The accent's colour, the app's own included.
    public var accentRGB: RGB {
        accent == .custom ? customAccent : (accent.rgb ?? Accent.blusion.rgb ?? customAccent)
    }

    /// The page background's colour.
    public var backgroundRGB: RGB {
        switch background {
        case .tinted: accentRGB.scaled(by: tintStrength)
        case .custom: customBackground
        default: background.rgb ?? RGB(red: 0, green: 0, blue: 0)
        }
    }

    public var isDefault: Bool { self == AppearancePreferences() }

    /// The parts of Settings → Appearance, each with a page of its own and its own Restore Defaults.
    public enum Section: String, Sendable, CaseIterable, Identifiable {
        case colour, text, cards, corners, home, titlePages, motion, hover

        public var id: String { rawValue }
    }

    /// This look with one section back at its defaults and the rest as it is.
    public func restoringDefaults(of section: Section) -> AppearancePreferences {
        let defaults = AppearancePreferences()
        var result = self
        switch section {
        case .colour:
            result.accent = defaults.accent
            result.customAccent = defaults.customAccent
            result.background = defaults.background
            result.customBackground = defaults.customBackground
            result.tintStrength = defaults.tintStrength
            result.playStyle = defaults.playStyle
            result.buttonFinish = defaults.buttonFinish
        case .text:
            result.textSize = defaults.textSize
            result.font = defaults.font
            result.boldText = defaults.boldText
            result.italicText = defaults.italicText
            result.fontWidth = defaults.fontWidth
            result.letterSpacing = defaults.letterSpacing
            result.lineSpacing = defaults.lineSpacing
            result.headingFont = defaults.headingFont
            result.headingWeight = defaults.headingWeight
            result.headingSize = defaults.headingSize
            result.headingWidth = defaults.headingWidth
            result.headingSpacing = defaults.headingSpacing
            result.uppercaseHeadings = defaults.uppercaseHeadings
            result.headingColour = defaults.headingColour
        case .cards:
            result.cardScale = defaults.cardScale
            result.spacingScale = defaults.spacingScale
            result.shelfSpacingScale = defaults.shelfSpacingScale
            result.sideMarginScale = defaults.sideMarginScale
            result.showsShelfDividers = defaults.showsShelfDividers
            result.shelfDividerThickness = defaults.shelfDividerThickness
            result.shelfDividerOpacity = defaults.shelfDividerOpacity
            result.shelfDividerFullWidth = defaults.shelfDividerFullWidth
            result.phoneGridColumns = defaults.phoneGridColumns
            result.phoneLandscapeGridColumns = defaults.phoneLandscapeGridColumns
            result.showsPosterTitles = defaults.showsPosterTitles
            result.captionLines = defaults.captionLines
            result.showsCaptionDetails = defaults.showsCaptionDetails
            result.uppercaseCaptions = defaults.uppercaseCaptions
            result.outline = defaults.outline
            result.artworkTone = defaults.artworkTone
            result.progressColour = defaults.progressColour
            result.progressThickness = defaults.progressThickness
            result.showsTimeLeft = defaults.showsTimeLeft
        case .corners:
            result.cornerScale = defaults.cornerScale
            result.cornerOverrides = defaults.cornerOverrides
            result.includesCircularButtons = defaults.includesCircularButtons
        case .home:
            result.heroAutoAdvance = defaults.heroAutoAdvance
            result.showsPageDots = defaults.showsPageDots
        case .titlePages:
            result.hidesSpoilers = defaults.hidesSpoilers
            result.spoilerStills = defaults.spoilerStills
            result.spoilerSynopses = defaults.spoilerSynopses
            result.spoilerTitles = defaults.spoilerTitles
            result.expandsSynopsis = defaults.expandsSynopsis
            result.showsReviews = defaults.showsReviews
            result.showsCast = defaults.showsCast
            result.showsInformation = defaults.showsInformation
            result.showsRelated = defaults.showsRelated
            result.sectionOrder = defaults.sectionOrder
        case .motion:
            result.startTab = defaults.startTab
            result.zoomTransitions = defaults.zoomTransitions
            result.animationSpeed = defaults.animationSpeed
            result.phoneTabTitles = defaults.phoneTabTitles
            result.minimisesTabBar = defaults.minimisesTabBar
            result.showsContinueBar = defaults.showsContinueBar
        case .hover:
            result.hover = defaults.hover
        }
        return result
    }

    public func isDefault(_ section: Section) -> Bool { restoringDefaults(of: section) == self }

    /// What a card's height depends on besides its own shape, size and width: a shelf or grid that measured its cards measures again when
    /// this changes.
    public var layoutKey: String {
        let numbers = [cardScale, spacingScale, cornerScale, effectiveShelfSpacingScale, sideMarginScale, shelfDividerThickness, shelfDividerOpacity].map { String(format: "%.3f", $0) }
        let text = [textSize.rawValue, font.rawValue, "\(boldText)", "\(italicText)", fontWidth.rawValue, letterSpacing.rawValue,
                    lineSpacing.rawValue, headingFont.rawValue, headingWeight.rawValue, headingSize.rawValue, headingWidth.rawValue,
                    headingSpacing.rawValue, "\(uppercaseHeadings)"]
        let captions = ["\(showsPosterTitles)", "\(captionLines)", "\(showsCaptionDetails)", "\(uppercaseCaptions)", "\(phoneGridColumns)", "\(phoneLandscapeGridColumns)", "\(showsShelfDividers)", "\(shelfDividerFullWidth)"]
        return (numbers + text + captions).joined(separator: "|")
    }

    /// What is saved now, or the defaults.
    public static func saved(in defaults: UserDefaults = .standard) -> AppearancePreferences {
        defaults.string(forKey: defaultsKey).flatMap(AppearancePreferences.init(rawValue:)) ?? AppearancePreferences()
    }

    /// Back to the defaults (Settings → Clear data → Settings, and Appearance's Reset).
    public static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// The JSON string `@AppStorage` keeps.
extension AppearancePreferences: RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8), let value = try? JSONDecoder().decode(AppearancePreferences.self, from: data) else {
            return nil
        }
        self = value
    }

    public var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
