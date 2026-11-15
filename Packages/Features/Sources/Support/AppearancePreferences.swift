import Foundation
import StremioKit

/// How the app looks, as the listener sets it on Settings → Appearance: colour (accent, page background), text (reading, interface and
/// headings, each with the same size, face, width, weight, slant, spacing, colour and case), cards (size, corners, spacing, columns,
/// captions, outline, artwork tone, progress bars), Home's spotlight, title pages (sections, their order, spoilers) and motion and
/// navigation (start tab, transitions, animation speed, the iPhone's tab bar).
///
/// Saved as one JSON string under `defaultsKey` in the standard defaults, so screens read it with `@AppStorage` and follow a change at
/// once. The root applies it (`appliesAppearance()`); cards and grids read it through `LayoutMetrics`. Every field decodes on its own, so
/// a value added later keeps older saves loading, and the fields that used to be fixed steps (card size, corners, spacing, the outline
/// switch) read the old steps into the new values.
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
    public var customAccent = RGB(red: 0.058990478515625, green: 0, blue: 0.2928619384765625)
    public var background: Background = .graphite
    /// The background when `background` is `.custom`. Kept like the custom accent.
    public var customBackground = RGB(red: 0, green: 0, blue: 0.049957275390625)
    /// How much of the accent the Tinted background has, as a share of the accent's own brightness (`tintStrengthRange`).
    public var tintStrength: Double = 0.11
    public var playStyle: PlayStyle = .artwork
    public var buttonFinish: ButtonFinish = .glass

    // MARK: - Text

    /// Prose: synopses and other reading. Its text size is the listener's own and a preset leaves it.
    public var reading: TextStyle = {
        var style = TextStyle()
        style.textSize = .large
        style.width = .expanded
        style.weight = .semibold
        style.letterSpacing = .tight
        style.scale = .small
        return style
    }()
    /// Buttons, metadata, captions and other interface text. Each choice follows reading until it is set.
    public var interface = TextStyle.followingReading()
    /// Shelf and section headings. The face, width, spacing, slant and text size follow reading; weight and size are their own.
    public var headings = TextStyle.headings()

    public func storedText(for role: TextRole) -> TextStyle {
        switch role {
        case .reading: reading
        case .interface: interface
        case .display: headings
        }
    }

    public mutating func setStoredText(_ style: TextStyle, for role: TextRole) {
        switch role {
        case .reading: reading = style
        case .interface: interface = style
        case .display: headings = style
        }
    }

    /// `role`'s choices, with any it still borrows filled in from reading.
    public func resolvedText(for role: TextRole) -> TextStyle {
        let stored = storedText(for: role)
        guard role != .reading else { return stored }
        var resolved = stored
        if stored.followsTextSize { resolved.textSize = reading.textSize }
        if stored.followsFont { resolved.font = reading.font }
        if stored.followsWidth { resolved.width = reading.width }
        if stored.followsWeight { resolved.weight = reading.weight }
        if stored.followsItalic { resolved.italic = reading.italic }
        if stored.followsLetterSpacing { resolved.letterSpacing = reading.letterSpacing }
        if stored.followsLineSpacing { resolved.lineSpacing = reading.lineSpacing }
        if stored.followsScale { resolved.scale = reading.scale }
        return resolved
    }

    public var textSize: TextSize {
        get { reading.textSize }
        set { reading.textSize = newValue }
    }

    public var font: FontStyle {
        get { reading.font }
        set { reading.font = newValue }
    }

    /// Reading in a heavy weight. Kept so earlier saves, which stored a switch, still read.
    public var boldText: Bool {
        get { reading.weight == .bold || reading.weight == .heavy || reading.weight == .black }
        set {
            reading.weight = newValue ? .bold : .regular
            reading.followsWeight = false
        }
    }

    public var italicText: Bool {
        get { reading.italic }
        set { reading.italic = newValue }
    }

    public var fontWidth: FontWidth {
        get { reading.width }
        set { reading.width = newValue }
    }

    public var letterSpacing: LetterSpacing {
        get { reading.letterSpacing }
        set { reading.letterSpacing = newValue }
    }

    public var lineSpacing: LineSpacing {
        get { reading.lineSpacing }
        set { reading.lineSpacing = newValue }
    }

    public var headingFont: HeadingFont {
        get { headings.followsFont ? .matchText : (HeadingFont(rawValue: headings.font.rawValue) ?? .matchText) }
        set {
            if let font = newValue.font {
                headings.font = font
                headings.followsFont = false
            } else {
                headings.followsFont = true
            }
        }
    }

    /// Buttons, metadata, captions and other interface text. `matchText` uses the reading face.
    public var interfaceFont: HeadingFont {
        get { interface.followsFont ? .matchText : (HeadingFont(rawValue: interface.font.rawValue) ?? .matchText) }
        set {
            if let font = newValue.font {
                interface.font = font
                interface.followsFont = false
            } else {
                interface.followsFont = true
            }
        }
    }

    public var headingWeight: HeadingWeight {
        get { headings.weight }
        set {
            headings.weight = newValue
            headings.followsWeight = false
        }
    }

    public var headingSize: HeadingSize {
        get { headings.scale }
        set {
            headings.scale = newValue
            headings.followsScale = false
        }
    }

    public var headingWidth: HeadingWidth {
        get {
            guard !headings.followsWidth else { return .matchText }
            switch headings.width {
            case .compressed: return .compressed
            case .condensed: return .condensed
            case .standard: return .standard
            case .expanded: return .expanded
            }
        }
        set {
            if let width = newValue.width {
                headings.width = width
                headings.followsWidth = false
            } else {
                headings.followsWidth = true
            }
        }
    }

    public var headingSpacing: HeadingSpacing {
        get {
            guard !headings.followsLetterSpacing else { return .matchText }
            switch headings.letterSpacing {
            case .tight: return .tight
            case .standard: return .standard
            case .wide: return .wide
            case .wider: return .wider
            }
        }
        set {
            if let spacing = newValue.spacing {
                headings.letterSpacing = spacing
                headings.followsLetterSpacing = false
            } else {
                headings.followsLetterSpacing = true
            }
        }
    }

    public var uppercaseHeadings: Bool {
        get { headings.capitals }
        set { headings.capitals = newValue }
    }

    public var headingColour: HeadingColour {
        get { headings.colour }
        set { headings.colour = newValue }
    }

    // MARK: - Cards

    /// Every card's width in shelves and wide grids, as a share of the layout's own (`cardScaleRange`).
    public var cardScale: Double = 1
    /// The roundness of posters, cards, tiles and stills, as a share of their own radius (`cornerScaleRange`). Zero is square.
    public var cornerScale: Double = 1.5
    /// Missing entries follow the global corner scale; overrides are absolute, not multiplied by it.
    public var cornerOverrides: [String: Double] = [:]
    public var includesCircularButtons = true

    public func cornerScale(for group: CornerGroup) -> Double {
        cornerOverrides[group.rawValue] ?? cornerScale
    }
    /// The gaps between cards and between shelves, as a share of the layout's own (`spacingScaleRange`).
    public var spacingScale: Double = 0.3
    /// The gap between shelves on its own; nil follows `spacingScale`.
    public var shelfSpacingScale: Double? = 1.4000000000000001
    /// The page's left and right margin, as a share of the layout's own (it also follows `spacingScale`, so tight spacing reaches the edges).
    public var sideMarginScale: Double = 1.1
    /// A horizontal line between shelves, with its thickness, strength and whether it runs edge to edge.
    public var showsShelfDividers = true
    public var shelfDividerThickness: Double = 1.5
    public var shelfDividerOpacity: Double = 0.07
    public var shelfDividerFullWidth = true
    /// The lines between a title page's sections: Home's shelf lines, or these of its own.
    public var titleDividersFollowHome = true
    public var showsTitleDividers = true
    public var titleDividerThickness: Double = 1
    public var titleDividerOpacity: Double = 0.06
    public var titleDividerFullWidth = false
    public var effectiveShowsTitleDividers: Bool { titleDividersFollowHome ? showsShelfDividers : showsTitleDividers }
    public var effectiveTitleDividerThickness: Double { titleDividersFollowHome ? shelfDividerThickness : titleDividerThickness }
    public var effectiveTitleDividerOpacity: Double { titleDividersFollowHome ? shelfDividerOpacity : titleDividerOpacity }
    public var effectiveTitleDividerFullWidth: Bool { titleDividersFollowHome ? shelfDividerFullWidth : titleDividerFullWidth }
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
    /// Buttons take the cards' hairline (Outline's strength, or Default when cards have none).
    public var outlinesButtons = true
    public var artworkTone: ArtworkTone = .natural
    public var progressColour: ProgressColour = .white
    public var progressThickness: ProgressThickness = .thin
    /// The minutes left beside the progress line on Continue cards.
    public var showsTimeLeft = true

    // MARK: - Poster artwork

    /// Poster cards use 1200-pixel hero artwork; details reuse it while loading the full-resolution image.
    public var usesHeroPosters = false
    /// IMDb and Letterboxd ratings on posters.
    public var showsPosterRatings = true
    /// Rating logos keep their brand colours. Off, they take the text colour, so they match the rest of the screen.
    public var showsColouredRatingLogos = true
    /// Film posters carry a 4K or Blu-ray mark beside their ratings when Best Blurays names that disc as the film's best.
    public var showsBestDiscOnPosters = true
    /// Where a poster's disc or streamer brand sits: in the ratings pill, or on its own in a corner. Top right by default.
    public var posterMarkPlacement: PosterMarkPlacement = .topTrailing

    // MARK: - Layout

    public var layout: Layout = .standard

    // MARK: - Home

    /// Seconds between the spotlight turning its page by itself; zero never (`heroAutoAdvanceOptions`).
    public var heroAutoAdvance = 0
    /// Retained for saved-look compatibility; showcase dots are always visible.
    public var showsPageDots = true
    /// Maximum titles shown in Continue Watching, after filtering by kind.
    public var continueWatchingLimit = 12

    // MARK: - Title pages

    /// Unwatched episodes on a title page hide what `spoilerStills`, `spoilerSynopses` and `spoilerTitles` say until they are started.
    public var hidesSpoilers = false
    public var spoilerStills = false
    public var spoilerSynopses = true
    public var spoilerTitles = false
    /// The synopsis opens unfolded.
    public var expandsSynopsis = false
    /// The hero picture runs down the whole page as an episode card's still runs under its text, in place of the fade to the page's colour.
    public var blursBackground = false
    /// The title page's sections below Play, synopsis and ratings.
    public var showsReviews = true
    public var showsCast = true
    public var showsInformation = true
    public var showsFranchise = true
    public var showsRelated = true
    /// Where the title can be watched in the viewer's region, from TMDb.
    public var showsWatchAnywhere = true
    public var sectionOrder: SectionOrder = .reviewsFirst
    /// Empty keeps the earlier Reviews First / Cast First choice, including existing saved looks and presets.
    public var titleSectionOrder: [TitleSection] = [.episodes, .reviews, .cast, .franchise, .related, .information, .watchAnywhere]
    /// On iPhone held upright, a title page keeps the tab bar so Home can be tapped from it.
    public var showsTitlePageTabBar = true

    public var orderedTitleSections: [TitleSection] {
        let saved = titleSectionOrder.isEmpty && sectionOrder == .castFirst
            ? [.episodes, .cast, .reviews, .information, .franchise, .related, .watchAnywhere] : titleSectionOrder
        var order: [TitleSection] = []
        for section in saved + TitleSection.allCases where !order.contains(section) {
            order.append(section)
        }
        return order
    }

    public func showsTitleSection(_ section: TitleSection) -> Bool {
        switch section {
        case .episodes: true
        case .reviews: showsReviews
        case .cast: showsCast
        case .information: showsInformation
        case .franchise: showsFranchise
        case .related: showsRelated
        case .watchAnywhere: showsWatchAnywhere
        }
    }

    // MARK: - Navigation and motion

    public var startTab: StartTab = .home
    /// A card zooms into the title it opens, and the title zooms back into it.
    public var zoomTransitions = true
    public var animationSpeed: AnimationSpeed = .fastest
    /// The iPhone's tab bar names its tabs under their icons.
    public var phoneTabTitles = false
    /// The iPhone's tab bar shrinks while a page scrolls down.
    public var minimisesTabBar = true
    /// The Continue Watching bar above the iPhone's tab bar.
    public var showsContinueBar = false

    // MARK: - Hover

    /// The Mac's hover feedback.
    public var hover = Hover()

    public init() {}

    /// Copies what a preset sets from `look`: colour, Play's fill and the buttons' finish, text but its size, cards, corners, the layout,
    /// Home's spotlight, the title page's layout, zoom transitions, the iPhone's tab bar and the Mac's hover. The custom colours stay.
    mutating func takeLook(from look: AppearancePreferences) {
        let readingSize = reading.textSize
        let interfaceSize = interface.textSize
        let interfaceFollowsSize = interface.followsTextSize
        let keptHeadingTextSize = headings.textSize
        let headingFollowsSize = headings.followsTextSize
        for field in Self.fields where field.inLook { field.copy(&self, look) }
        reading.textSize = readingSize
        interface.textSize = interfaceSize
        interface.followsTextSize = interfaceFollowsSize
        headings.textSize = keptHeadingTextSize
        headings.followsTextSize = headingFollowsSize
    }

    // MARK: - Fields

    /// One saved field: the Appearance page whose Restore Defaults covers it, whether a preset sets it, and how it is read, written,
    /// compared and copied. Coding, equality, restoring a page and taking a look all walk `fields`, so a setting is declared once and
    /// listed once.
    private struct Field: Sendable {
        /// The property's name, which a sectioned export files the field under.
        let name: String
        let section: Section?
        let inLook: Bool
        let isPosterArtwork: Bool
        let read: @Sendable (inout AppearancePreferences, KeyedDecodingContainer<CodingKeys>) -> Void
        let write: @Sendable (AppearancePreferences, inout KeyedEncodingContainer<CodingKeys>) throws -> Void
        let equal: @Sendable (AppearancePreferences, AppearancePreferences) -> Bool
        let copy: @Sendable (inout AppearancePreferences, AppearancePreferences) -> Void
        /// The field's value for a sectioned export; nil leaves it out.
        let value: @Sendable (AppearancePreferences) -> (any Encodable & Sendable)?
    }

    /// The fields whose property is not named as its saved key is.
    private static let propertyNames: [CodingKeys: String] = [
        .cardSize: "cardScale", .spacing: "spacingScale", .sideMargin: "sideMarginScale", .interfaceText: "interface", .headingText: "headings",
    ]

    private typealias Path<Value> = WritableKeyPath<AppearancePreferences, Value> & Sendable
    private typealias Reader = @Sendable (inout AppearancePreferences, KeyedDecodingContainer<CodingKeys>) -> Void

    /// A field saved under `key`. Without a `read` of its own, a missing or unreadable value leaves the default in place.
    private static func field<Value: Codable & Equatable & Sendable>(_ path: Path<Value>, _ key: CodingKeys, _ section: Section?, look: Bool = true,
                                                          poster: Bool = false, read: Reader? = nil) -> Field {
        Field(name: propertyNames[key] ?? key.stringValue, section: section, inLook: look, isPosterArtwork: poster,
              read: read ?? { look, container in look[keyPath: path] = container.read(key, look[keyPath: path]) },
              write: { look, container in try container.encode(look[keyPath: path], forKey: key) },
              equal: { $0[keyPath: path] == $1[keyPath: path] },
              copy: { $0[keyPath: path] = $1[keyPath: path] },
              value: { $0[keyPath: path] })
    }

    /// A share kept inside `range`; a value that is not a number leaves the default.
    private static func share(_ path: Path<Double>, _ key: CodingKeys, _ range: ClosedRange<Double>, _ section: Section?) -> Field {
        field(path, key, section, read: { look, container in
            look[keyPath: path] = clamp(container.read(key, look[keyPath: path]), range, look[keyPath: path])
        })
    }

    /// A count kept inside `range`.
    private static func count(_ path: Path<Int>, _ key: CodingKeys, _ range: ClosedRange<Int>, _ section: Section?, look: Bool = true) -> Field {
        field(path, key, section, look: look, read: { look, container in
            look[keyPath: path] = min(max(container.read(key, look[keyPath: path]), range.lowerBound), range.upperBound)
        })
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    /// Every stored field, in the order it is read: a later field may lean on an earlier one (the shelf gap on the card gap).
    private static let fields: [Field] = colourFields + textFields + cardFields + posterFields + homeFields + titlePageFields + motionFields

    private static let colourFields: [Field] = [
        field(\.accent, .accent, .colour),
        field(\.customAccent, .customAccent, .colour, look: false),
        field(\.background, .background, .colour),
        field(\.customBackground, .customBackground, .colour, look: false),
        share(\.tintStrength, .tintStrength, tintStrengthRange, .colour),
        field(\.playStyle, .playStyle, .colour),
        field(\.buttonFinish, .buttonFinish, .colour),
    ]

    /// The three text styles are read together by `readText`, which also understands the fields that came before them.
    private static let textFields: [Field] = [
        field(\.reading, .reading, .text, read: { _, _ in }),
        field(\.interface, .interfaceText, .text, read: { _, _ in }),
        field(\.headings, .headingText, .text, read: { _, _ in }),
    ]

    private static let cardFields: [Field] = [
        // Card size, corners and spacing were fixed steps saved by name; a save from then reads the step's value.
        field(\.cardScale, .cardSize, .cards, read: { look, container in
            look.cardScale = clamp(container.read(.cardSize, container.legacyStep(.legacyCardScale, legacyCardScales) ?? 1), cardScaleRange, 1)
        }),
        field(\.cornerScale, .cornerScale, .corners, read: { look, container in
            let saved = container.read(.cornerScale, container.legacyStep(.legacyCorners, legacyCornerScales) ?? look.cornerScale)
            look.cornerScale = clamp(saved, cornerScaleRange, look.cornerScale)
        }),
        field(\.cornerOverrides, .cornerOverrides, .corners, read: { look, container in
            look.cornerOverrides = container.read(.cornerOverrides, look.cornerOverrides).filter { key, value in
                CornerGroup(rawValue: key) != nil && value.isFinite
            }.mapValues { min(max($0, cornerScaleRange.lowerBound), cornerScaleRange.upperBound) }
        }),
        field(\.includesCircularButtons, .includesCircularButtons, .corners),
        field(\.spacingScale, .spacing, .cards, read: { look, container in
            let saved = container.read(.spacing, container.legacyStep(.legacyDensity, legacySpacingScales) ?? look.spacingScale)
            look.spacingScale = clamp(saved, spacingScaleRange, look.spacingScale)
        }),
        shelfSpacingField,
        share(\.sideMarginScale, .sideMargin, sideMarginScaleRange, .cards),
        field(\.showsShelfDividers, .showsShelfDividers, .home),
        share(\.shelfDividerThickness, .shelfDividerThickness, shelfDividerThicknessRange, .home),
        share(\.shelfDividerOpacity, .shelfDividerOpacity, shelfDividerOpacityRange, .home),
        field(\.shelfDividerFullWidth, .shelfDividerFullWidth, .home),
        field(\.titleDividersFollowHome, .titleDividersFollowHome, .titlePages),
        field(\.showsTitleDividers, .showsTitleDividers, .titlePages),
        share(\.titleDividerThickness, .titleDividerThickness, shelfDividerThicknessRange, .titlePages),
        share(\.titleDividerOpacity, .titleDividerOpacity, shelfDividerOpacityRange, .titlePages),
        field(\.titleDividerFullWidth, .titleDividerFullWidth, .titlePages),
        count(\.phoneGridColumns, .phoneGridColumns, phoneGridColumnRange, .cards),
        count(\.phoneLandscapeGridColumns, .phoneLandscapeGridColumns, phoneGridColumnRange, .cards),
        field(\.showsPosterTitles, .showsPosterTitles, .cards),
        count(\.captionLines, .captionLines, captionLineRange, .cards),
        field(\.showsCaptionDetails, .showsCaptionDetails, .cards),
        field(\.uppercaseCaptions, .uppercaseCaptions, .cards),
        // The outline was a switch; off reads as Off.
        field(\.outline, .outline, .cards, read: { look, container in
            let legacy: Outline? = (try? container.decode(Bool.self, forKey: .legacyArtworkOutline)).map { $0 ? .standard : .off }
            look.outline = container.read(.outline, legacy ?? look.outline)
        }),
        field(\.outlinesButtons, .outlinesButtons, .cards),
        field(\.artworkTone, .artworkTone, .cards),
        field(\.progressColour, .progressColour, .cards),
        field(\.progressThickness, .progressThickness, .cards),
        field(\.showsTimeLeft, .showsTimeLeft, .cards),
    ]

    /// The gap between shelves. An omitted gap in a saved layout with card spacing means the two gaps are linked, and nil is not written.
    private static let shelfSpacingField = Field(
        name: "shelfSpacingScale", section: .cards, inLook: true, isPosterArtwork: false,
        read: { look, container in
            guard container.contains(.shelfSpacing) || container.contains(.spacing) || container.contains(.legacyDensity) else { return }
            look.shelfSpacingScale = (try? container.decode(Double.self, forKey: .shelfSpacing))
                .map { clamp($0, shelfSpacingScaleRange, look.spacingScale) }
        },
        write: { look, container in try container.encodeIfPresent(look.shelfSpacingScale, forKey: .shelfSpacing) },
        equal: { $0.shelfSpacingScale == $1.shelfSpacingScale },
        copy: { $0.shelfSpacingScale = $1.shelfSpacingScale },
        value: { $0.shelfSpacingScale })

    /// The poster switches are the listener's own: no preset, saved look or pasted look sets them.
    private static let posterFields: [Field] = [
        field(\.usesHeroPosters, .usesHeroPosters, .cards, look: false, poster: true),
        field(\.showsPosterRatings, .showsPosterRatings, .cards, look: false, poster: true),
        field(\.showsColouredRatingLogos, .showsColouredRatingLogos, .cards, look: false, poster: true),
        field(\.showsBestDiscOnPosters, .showsBestDiscOnPosters, .cards, look: false, poster: true),
        field(\.posterMarkPlacement, .posterMarkPlacement, .cards, look: false, poster: true),
    ]

    private static let homeFields: [Field] = [
        // No page's Restore Defaults covers the layout.
        field(\.layout, .layout, nil),
        field(\.heroAutoAdvance, .heroAutoAdvance, .home, read: { look, container in
            let advance = container.read(.heroAutoAdvance, look.heroAutoAdvance)
            look.heroAutoAdvance = heroAutoAdvanceOptions.contains(advance) ? advance : 0
        }),
        field(\.showsPageDots, .showsPageDots, .home),
        count(\.continueWatchingLimit, .continueWatchingLimit, 1...100, .home, look: false),
    ]

    private static let titlePageFields: [Field] = [
        field(\.hidesSpoilers, .hidesSpoilers, .titlePages, look: false),
        field(\.spoilerStills, .spoilerStills, .titlePages, look: false),
        field(\.spoilerSynopses, .spoilerSynopses, .titlePages, look: false),
        field(\.spoilerTitles, .spoilerTitles, .titlePages, look: false),
        field(\.expandsSynopsis, .expandsSynopsis, .titlePages),
        field(\.blursBackground, .blursBackground, .titlePages),
        field(\.showsReviews, .showsReviews, .titlePages, look: false),
        field(\.showsCast, .showsCast, .titlePages, look: false),
        field(\.showsInformation, .showsInformation, .titlePages, look: false),
        field(\.showsFranchise, .showsFranchise, .titlePages, look: false),
        field(\.showsWatchAnywhere, .showsWatchAnywhere, .titlePages, look: false),
        field(\.showsRelated, .showsRelated, .titlePages, look: false),
        field(\.sectionOrder, .sectionOrder, .titlePages),
        field(\.titleSectionOrder, .titleSectionOrder, .titlePages, read: { look, container in
            guard container.contains(.titleSectionOrder) || container.contains(.sectionOrder) else { return }
            look.titleSectionOrder = container.read(.titleSectionOrder, [String]()).compactMap(TitleSection.init(rawValue:))
        }),
        field(\.showsTitlePageTabBar, .showsTitlePageTabBar, .titlePages),
    ]

    private static let motionFields: [Field] = [
        field(\.startTab, .startTab, .motion, look: false),
        field(\.zoomTransitions, .zoomTransitions, .motion),
        field(\.animationSpeed, .animationSpeed, .motion, look: false),
        field(\.phoneTabTitles, .phoneTabTitles, .motion),
        field(\.minimisesTabBar, .minimisesTabBar, .motion),
        field(\.showsContinueBar, .showsContinueBar, .motion, look: false),
        field(\.hover, .hover, .hover),
    ]

    // MARK: - Coding

    /// Written out, rather than synthesised, so that each field falls back to its default on its own, so that the old fixed steps read
    /// into their new values, and so that the JSON coding never goes through `RawRepresentable`'s, which would call `rawValue`, which
    /// encodes again.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for field in Self.fields { field.read(&self, container) }
        readText(from: container)
    }

    private mutating func readText(from container: KeyedDecodingContainer<CodingKeys>) {
        guard !container.contains(.reading) else {
            reading = container.read(.reading, reading)
            interface = container.read(.interfaceText, interface)
            headings = container.read(.headingText, headings)
            return
        }
        // A look saved before the three text styles spelled its typography out in these fields; what they do not cover was plain.
        if [CodingKeys.textSize, .font, .boldText, .italicText, .fontWidth, .letterSpacing, .lineSpacing].contains(where: container.contains) {
            reading = TextStyle()
        }
        reading.textSize = container.read(.textSize, reading.textSize)
        reading.font = container.read(.font, reading.font)
        if let bold = try? container.decode(Bool.self, forKey: .boldText) {
            reading.weight = bold ? .bold : .regular
        }
        reading.italic = container.read(.italicText, reading.italic)
        reading.width = container.read(.fontWidth, reading.width)
        reading.letterSpacing = container.read(.letterSpacing, reading.letterSpacing)
        reading.lineSpacing = container.read(.lineSpacing, reading.lineSpacing)
        if let font = container.read(.interfaceFont, HeadingFont.matchText).font {
            interface.font = font
            interface.followsFont = false
        }
        if let font = container.read(.headingFont, HeadingFont.matchText).font {
            headings.font = font
            headings.followsFont = false
        }
        headings.weight = container.read(.headingWeight, headings.weight)
        headings.followsWeight = false
        headings.scale = container.read(.headingSize, headings.scale)
        headings.followsScale = false
        if let width = container.read(.headingWidth, HeadingWidth.matchText).width {
            headings.width = width
            headings.followsWidth = false
        }
        if let spacing = container.read(.headingSpacing, HeadingSpacing.matchText).spacing {
            headings.letterSpacing = spacing
            headings.followsLetterSpacing = false
        }
        headings.capitals = container.read(.uppercaseHeadings, headings.capitals)
        headings.colour = container.read(.headingColour, headings.colour)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for field in Self.fields { try field.write(self, &container) }
        // The typography as it was saved before the three text styles, for a build from then.
        try container.encode(textSize, forKey: .textSize)
        try container.encode(font, forKey: .font)
        try container.encode(boldText, forKey: .boldText)
        try container.encode(italicText, forKey: .italicText)
        try container.encode(fontWidth, forKey: .fontWidth)
        try container.encode(letterSpacing, forKey: .letterSpacing)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(headingFont, forKey: .headingFont)
        try container.encode(interfaceFont, forKey: .interfaceFont)
        try container.encode(headingWeight, forKey: .headingWeight)
        try container.encode(headingSize, forKey: .headingSize)
        try container.encode(headingWidth, forKey: .headingWidth)
        try container.encode(headingSpacing, forKey: .headingSpacing)
        try container.encode(uppercaseHeadings, forKey: .uppercaseHeadings)
        try container.encode(headingColour, forKey: .headingColour)
    }

    /// Every stored field under its property's name, filed by the Appearance page that covers it: the poster switches in
    /// `cards.posterArtwork`, and the layout and the Mac's hover, which no page's fields hold, on their own.
    func encodeBySection(to encoder: Encoder) throws {
        var bySection: [String: [Field]] = [:]
        var root = encoder.container(keyedBy: SectionKey.self)
        for field in Self.fields {
            guard let section = field.section, section != .hover else {
                if let value = field.value(self) { try root.encode(value, forKey: SectionKey(field.name)) }
                continue
            }
            bySection[section.rawValue, default: []].append(field)
        }
        for (section, fields) in bySection {
            var page = root.nestedContainer(keyedBy: SectionKey.self, forKey: SectionKey(section))
            for field in fields where !field.isPosterArtwork {
                if let value = field.value(self) { try page.encode(value, forKey: SectionKey(field.name)) }
            }
            let posters = fields.filter(\.isPosterArtwork)
            guard !posters.isEmpty else { continue }
            var artwork = page.nestedContainer(keyedBy: SectionKey.self, forKey: SectionKey("posterArtwork"))
            for field in posters {
                if let value = field.value(self) { try artwork.encode(value, forKey: SectionKey(field.name)) }
            }
        }
    }

    private struct SectionKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private enum CodingKeys: String, CodingKey {
        case accent, customAccent, background, customBackground, tintStrength, playStyle, buttonFinish
        case reading, interfaceText, headingText
        case textSize, font, boldText, italicText, fontWidth, letterSpacing, lineSpacing, headingFont, interfaceFont, headingWeight, headingSize,
             headingWidth, headingSpacing, uppercaseHeadings, headingColour
        case cornerOverrides, includesCircularButtons
        case shelfSpacing, sideMargin, showsShelfDividers, shelfDividerThickness, shelfDividerOpacity, shelfDividerFullWidth
        case titleDividersFollowHome, showsTitleDividers, titleDividerThickness, titleDividerOpacity, titleDividerFullWidth
        case cardSize, cornerScale, spacing, phoneGridColumns, showsPosterTitles, captionLines, showsCaptionDetails, uppercaseCaptions,
             outline, outlinesButtons, artworkTone, progressColour, progressThickness, showsTimeLeft
        case usesHeroPosters, showsPosterRatings, showsColouredRatingLogos, showsBestDiscOnPosters, posterMarkPlacement
        case phoneLandscapeGridColumns
        case layout
        case heroAutoAdvance, showsPageDots, continueWatchingLimit
        case hidesSpoilers, spoilerStills, spoilerSynopses, spoilerTitles, expandsSynopsis, blursBackground, showsReviews, showsCast,
             showsInformation, showsFranchise, showsRelated, showsWatchAnywhere, sectionOrder, titleSectionOrder, showsTitlePageTabBar
        case startTab, zoomTransitions, animationSpeed, phoneTabTitles, minimisesTabBar, showsContinueBar
        case hover
        /// The fixed steps saved before the sliders, read once and never written.
        case legacyCardScale = "cardScale", legacyCorners = "corners", legacyDensity = "density", legacyArtworkOutline = "artworkOutline"
    }

    static let legacyCardScales: [String: Double] = ["small": 0.82, "standard": 1, "large": 1.2, "huge": 1.42]
    static let legacyCornerScales: [String: Double] = ["square": 0, "subtle": 0.5, "standard": 1, "round": 1.8]
    static let legacySpacingScales: [String: Double] = ["compact": 0.66, "standard": 1, "roomy": 1.35]

    /// Field by field, so that equality never falls to `RawRepresentable`'s, which would compare the JSON text.
    public static func == (lhs: AppearancePreferences, rhs: AppearancePreferences) -> Bool {
        fields.allSatisfy { $0.equal(lhs, rhs) }
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

    /// This look with the poster switches taken from `current`. A saved, pasted or copied look sets the colour, text, cards and the rest,
    /// never the poster switches, which were not part of a look before they moved here.
    public func keepingPosterArtwork(of current: AppearancePreferences) -> AppearancePreferences {
        var look = self
        for field in Self.fields where field.isPosterArtwork { field.copy(&look, current) }
        return look
    }

    /// Whether everything but the poster artwork is at its default, so Settings can list the poster switches apart from the look.
    public var isDefaultExceptPosterArtwork: Bool { keepingPosterArtwork(of: AppearancePreferences()).isDefault }

    /// The parts of Settings → Appearance, each with a page of its own and its own Restore Defaults.
    public enum Section: String, Sendable, CaseIterable, Identifiable {
        case colour, text, cards, corners, home, titlePages, motion, hover

        public var id: String { rawValue }
    }

    /// This look with one section back at its defaults and the rest as it is.
    public func restoringDefaults(of section: Section) -> AppearancePreferences {
        let defaults = AppearancePreferences()
        var result = self
        for field in Self.fields where field.section == section { field.copy(&result, defaults) }
        return result
    }

    public func isDefault(_ section: Section) -> Bool { restoringDefaults(of: section) == self }

    /// What a card's height depends on besides its own shape, size and width: a shelf or grid that measured its cards measures again when
    /// this changes.
    public var layoutKey: String {
        let numbers = [cardScale, spacingScale, cornerScale, effectiveShelfSpacingScale, sideMarginScale, shelfDividerThickness,
                       shelfDividerOpacity].map { String(format: "%.3f", $0) }
        let text = [reading.layoutKey, interface.layoutKey, headings.layoutKey]
        let captions = ["\(showsPosterTitles)", "\(captionLines)", "\(showsCaptionDetails)", "\(uppercaseCaptions)", "\(phoneGridColumns)",
                        "\(phoneLandscapeGridColumns)", "\(showsShelfDividers)", "\(shelfDividerFullWidth)"]
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

    /// Set once the poster switches have moved from `PlaybackSettings`' keys into the saved look.
    static let posterArtworkMigratedKey = "settings.posterArtworkMovedToAppearance"

    /// Moves the poster switches saved under `PlaybackSettings`' keys into the saved look, once. Launch runs it before anything reads the
    /// look, so a listener's poster choices carry over, and the other settings in a saved look stay as they are.
    public static func migratePosterArtwork(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: posterArtworkMigratedKey) else { return }
        let legacy = DefaultsSettingsStore.Keys.self
        let keys = [legacy.showsPosterRatings, legacy.showsColouredRatingLogos, legacy.usesHeroPosters, legacy.showsBestDiscOnPosters,
                    legacy.posterMarkPlacement]
        if keys.contains(where: { defaults.object(forKey: $0) != nil }) {
            let fallback = AppearancePreferences()
            var look = saved(in: defaults)
            look.showsPosterRatings = defaults.object(forKey: legacy.showsPosterRatings) as? Bool ?? fallback.showsPosterRatings
            look.showsColouredRatingLogos = defaults.object(forKey: legacy.showsColouredRatingLogos) as? Bool ?? fallback.showsColouredRatingLogos
            look.usesHeroPosters = defaults.bool(forKey: legacy.usesHeroPosters)
            look.showsBestDiscOnPosters = defaults.object(forKey: legacy.showsBestDiscOnPosters) as? Bool ?? fallback.showsBestDiscOnPosters
            look.posterMarkPlacement = defaults.string(forKey: legacy.posterMarkPlacement).flatMap(PosterMarkPlacement.init(rawValue:))
                ?? fallback.posterMarkPlacement
            defaults.set(look.rawValue, forKey: defaultsKey)
            for key in keys { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: posterArtworkMigratedKey)
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

private extension KeyedDecodingContainer {
    /// The value saved under `key`, or `fallback` when it is missing or unreadable.
    func read<Value: Decodable>(_ key: Key, _ fallback: Value) -> Value {
        (try? decode(Value.self, forKey: key)) ?? fallback
    }

    /// The value of a fixed step that was saved by name under `key`.
    func legacyStep(_ key: Key, _ steps: [String: Double]) -> Double? {
        (try? decode(String.self, forKey: key)).flatMap { steps[$0] }
    }
}
