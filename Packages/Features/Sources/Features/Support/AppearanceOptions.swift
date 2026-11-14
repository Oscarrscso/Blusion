import Foundation

/// The choices Settings → Appearance offers, each with the value it stands for.
extension AppearancePreferences {
    /// sRGB, 0…1.
    public struct RGB: Sendable, Equatable, Codable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
        }

        func scaled(by factor: Double) -> RGB { RGB(red: red * factor, green: green * factor, blue: blue * factor) }
    }

    // MARK: - Colour

    /// The tint of buttons, switches, the selected tab and links.
    public enum Accent: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        /// The app's own accent, from the asset catalogue.
        case blusion
        case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, white
        /// Colours mixed for the presets: Netflix's red, Plex's amber, Arthouse's olive, Disney+'s royal blue and Prime Video's sky blue.
        case crimson, amber, olive, royal, sky
        /// `AppearancePreferences.customAccent`.
        case custom

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .blusion: "Blusion"
            case .custom: "Custom"
            default: rawValue.capitalized
            }
        }

        /// The preset's colour; nil for the custom accent, which is saved beside it.
        public var rgb: RGB? {
            switch self {
            case .blusion: RGB(red: 0.42, green: 0.51, blue: 1)
            case .blue: RGB(red: 0.04, green: 0.52, blue: 1)
            case .indigo: RGB(red: 0.37, green: 0.36, blue: 0.90)
            case .purple: RGB(red: 0.75, green: 0.35, blue: 0.95)
            case .pink: RGB(red: 1, green: 0.22, blue: 0.37)
            case .red: RGB(red: 1, green: 0.27, blue: 0.23)
            case .orange: RGB(red: 1, green: 0.62, blue: 0.04)
            case .yellow: RGB(red: 1, green: 0.84, blue: 0.04)
            case .green: RGB(red: 0.19, green: 0.82, blue: 0.35)
            case .mint: RGB(red: 0.39, green: 0.90, blue: 0.89)
            case .teal: RGB(red: 0.25, green: 0.78, blue: 0.88)
            case .cyan: RGB(red: 0.39, green: 0.82, blue: 1)
            case .white: RGB(red: 0.92, green: 0.92, blue: 0.94)
            case .crimson: RGB(red: 0.898, green: 0.035, blue: 0.078)
            case .amber: RGB(red: 0.898, green: 0.627, blue: 0.05)
            case .olive: RGB(red: 0.741, green: 0.733, blue: 0.553)
            case .royal: RGB(red: 0, green: 0.388, blue: 0.898)
            case .sky: RGB(red: 0, green: 0.659, blue: 0.882)
            case .custom: nil
            }
        }
    }

    /// The colour behind every page, and the colour hero artwork fades into.
    public enum Background: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case black, graphite, charcoal, slate, steel, ink, navy, midnight, plum, forest, cocoa
        /// A very dark shade of the accent, as dark as `tintStrength` says.
        case tinted
        /// `AppearancePreferences.customBackground`.
        case custom

        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }

        /// The fixed backgrounds' colour; nil for Tinted and Custom, which come from other fields.
        public var rgb: RGB? {
            switch self {
            case .black: RGB(red: 0, green: 0, blue: 0)
            case .graphite: RGB(red: 0.078, green: 0.078, blue: 0.078)
            case .charcoal: RGB(red: 0.11, green: 0.12, blue: 0.13)
            case .slate: RGB(red: 0.055, green: 0.067, blue: 0.085)
            case .steel: RGB(red: 0.078, green: 0.094, blue: 0.11)
            case .ink: RGB(red: 0.059, green: 0.09, blue: 0.118)
            case .navy: RGB(red: 0.102, green: 0.114, blue: 0.161)
            case .midnight: RGB(red: 0.02, green: 0.035, blue: 0.085)
            case .plum: RGB(red: 0.075, green: 0.03, blue: 0.08)
            case .forest: RGB(red: 0.025, green: 0.06, blue: 0.04)
            case .cocoa: RGB(red: 0.08, green: 0.055, blue: 0.035)
            case .tinted, .custom: nil
            }
        }
    }

    // MARK: - Text

    /// Where a piece of text sits. Display is shelf and section headings, interface is controls and metadata, reading is prose.
    public enum TextRole: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case reading, interface, display

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .reading: "Body text"
            case .interface: "Buttons & labels"
            case .display: "Titles & headings"
            }
        }
    }

    /// One kind of text: its size, face, width, weight, slant, spacing, colour and case. Interface and headings leave a choice unset
    /// (`follows…`) to use reading's until the listener sets that choice on its own.
    public struct TextStyle: Sendable, Equatable, Codable {
        public var textSize: TextSize = .system
        public var followsTextSize = false
        public var font: FontStyle = .standard
        public var followsFont = false
        public var width: FontWidth = .standard
        public var followsWidth = false
        public var weight: HeadingWeight = .regular
        public var followsWeight = false
        public var italic = false
        public var followsItalic = false
        public var letterSpacing: LetterSpacing = .standard
        public var followsLetterSpacing = false
        public var lineSpacing: LineSpacing = .standard
        public var followsLineSpacing = false
        public var colour: HeadingColour = .primary
        public var capitals = false
        public var scale: HeadingSize = .standard
        public var followsScale = false

        public init() {}

        /// Every choice follows reading, until the listener sets one.
        public static func followingReading() -> TextStyle {
            var style = TextStyle()
            style.followsTextSize = true
            style.followsFont = true
            style.followsWidth = true
            style.followsWeight = true
            style.followsItalic = true
            style.followsLetterSpacing = true
            style.followsLineSpacing = true
            style.followsScale = true
            return style
        }

        /// Headings follow the reading face, width, spacing, slant and text size, and keep a bold Title 2 of their own.
        public static func headings() -> TextStyle {
            var style = followingReading()
            style.followsWeight = false
            style.weight = .bold
            style.followsScale = false
            return style
        }

        /// True when this style has no choice of its own besides colour and capitals, which stay at their defaults.
        public var followsReading: Bool {
            followsTextSize && followsFont && followsWidth && followsWeight && followsItalic
                && followsLetterSpacing && followsLineSpacing && followsScale
                && colour == .primary && !capitals
        }

        /// What a layout depends on, so a shelf measures its cards again when the type changes.
        public var layoutKey: String {
            [textSize.rawValue, "\(followsTextSize)", font.rawValue, "\(followsFont)", width.rawValue, "\(followsWidth)",
             weight.rawValue, "\(followsWeight)", "\(italic)", "\(followsItalic)", letterSpacing.rawValue, "\(followsLetterSpacing)",
             lineSpacing.rawValue, "\(followsLineSpacing)", colour.rawValue, "\(capitals)", scale.rawValue, "\(followsScale)"]
                .joined(separator: ",")
        }
    }

    /// A fixed text size for the whole app, or the system's own. The accessibility sizes go past the largest ordinary size.
    public enum TextSize: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case system, xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
        case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .system: "System"
            case .xSmall: "Extra Small"
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .xLarge: "Extra Large"
            case .xxLarge: "Huge"
            case .xxxLarge: "Largest"
            case .accessibility1: "Accessibility 1"
            case .accessibility2: "Accessibility 2"
            case .accessibility3: "Accessibility 3"
            case .accessibility4: "Accessibility 4"
            case .accessibility5: "Accessibility 5"
            }
        }
    }

    /// A typeface. The first four are system designs; the rest are faces that ship with iOS, used for reading, interface, or display.
    public enum FontStyle: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case standard, rounded, serif, monospaced
        case avenir, avenirNext, futura, gillSans, helveticaNeue
        case baskerville, charter, georgia, palatino, iowan, hoefler
        case didot, bodoni, optima, typewriter

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .standard: "Default"
            case .serif: "New York"
            case .monospaced: "Mono"
            case .avenir: "Avenir"
            case .avenirNext: "Avenir Next"
            case .futura: "Futura"
            case .gillSans: "Gill Sans"
            case .helveticaNeue: "Helvetica Neue"
            case .baskerville: "Baskerville"
            case .charter: "Charter"
            case .georgia: "Georgia"
            case .palatino: "Palatino"
            case .iowan: "Iowan Old Style"
            case .hoefler: "Hoefler Text"
            case .didot: "Didot"
            case .bodoni: "Bodoni"
            case .optima: "Optima"
            case .typewriter: "Typewriter"
            default: rawValue.capitalized
            }
        }

        /// The font family, for a face that is not a system design.
        public var familyName: String? {
            switch self {
            case .avenir: "Avenir"
            case .avenirNext: "Avenir Next"
            case .futura: "Futura"
            case .gillSans: "Gill Sans"
            case .helveticaNeue: "Helvetica Neue"
            case .baskerville: "Baskerville"
            case .charter: "Charter"
            case .georgia: "Georgia"
            case .palatino: "Palatino"
            case .iowan: "Iowan Old Style"
            case .hoefler: "Hoefler Text"
            case .didot: "Didot"
            case .bodoni: "Bodoni 72"
            case .optima: "Optima"
            case .typewriter: "American Typewriter"
            default: nil
            }
        }
    }

    /// How wide the system font's letters are.
    public enum FontWidth: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case compressed, condensed, standard, expanded

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }
    }

    /// Extra space between letters, in points.
    public enum LetterSpacing: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case tight, standard, wide, wider

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }

        public var points: Double {
            switch self {
            case .tight: -0.5
            case .standard: 0
            case .wide: 0.8
            case .wider: 2
            }
        }
    }

    /// Extra space between the lines of text that wraps, in points.
    public enum LineSpacing: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case standard, relaxed, airy

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }

        public var points: Double {
            switch self {
            case .standard: 0
            case .relaxed: 3
            case .airy: 7
            }
        }
    }

    /// A reading face, or the reading face itself. Headings and interface text each have one.
    public enum HeadingFont: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case matchText, standard, rounded, serif, monospaced
        case avenir, avenirNext, futura, gillSans, helveticaNeue
        case baskerville, charter, georgia, palatino, iowan, hoefler
        case didot, bodoni, optima, typewriter

        public var id: String { rawValue }

        public var label: String {
            if self == .matchText { return "Same as body text" }
            return font?.label ?? rawValue.capitalized
        }

        /// The face, or nil to follow the reading text.
        public var font: FontStyle? { FontStyle(rawValue: rawValue) }
    }

    public enum HeadingWeight: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case regular, medium, semibold, bold, heavy, black

        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }
    }

    /// How wide headings' letters are: the text's own, or one of their own. Only the default font has widths.
    public enum HeadingWidth: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case matchText, compressed, condensed, standard, expanded

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .matchText: "Same as Text"
            case .standard: "Default"
            default: rawValue.capitalized
            }
        }

        /// The width, or nil to follow the text's.
        public var width: FontWidth? {
            switch self {
            case .matchText: nil
            case .compressed: .compressed
            case .condensed: .condensed
            case .standard: .standard
            case .expanded: .expanded
            }
        }
    }

    /// Extra space between headings' letters: the text's own, or their own.
    public enum HeadingSpacing: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case matchText, tight, standard, wide, wider

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .matchText: "Same as Text"
            case .standard: "Default"
            default: rawValue.capitalized
            }
        }

        /// The spacing, or nil to follow the text's.
        public var spacing: LetterSpacing? {
            switch self {
            case .matchText: nil
            case .tight: .tight
            case .standard: .standard
            case .wide: .wide
            case .wider: .wider
            }
        }
    }

    /// The heading's text style: Title 3, Title 2 (the app's own), Title, Large Title.
    public enum HeadingSize: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case small, standard, large, huge

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }
    }

    // MARK: - Cards

    public enum CornerGroup: String, Sendable, Codable, CaseIterable, Identifiable {
        case artwork, playButton, actionButtons, filters, reviews, panels, playerControls, settingsRows

        public var id: String { rawValue }
        /// What the group rounds, in the words the listener sees it by.
        public var label: String {
            switch self {
            case .artwork: "Posters, Cards & Photos"
            case .playButton: "Play Button"
            case .actionButtons: "Other Buttons"
            case .filters: "Pickers, Chips & Badges"
            case .reviews: "Review Cards"
            case .panels: "Stream Cards & Panels"
            case .playerControls: "Player Controls"
            case .settingsRows: "Settings Rows"
            }
        }
    }

    /// The hairline just inside every poster, card and still.
    public enum Outline: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case off, faint, standard, strong

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }

        /// The hairline's white, as an opacity. The default is `Theme.artworkBorder`'s.
        public var opacity: Double {
            switch self {
            case .off: 0
            case .faint: 0.1
            case .standard: 0.26
            case .strong: 0.5
            }
        }

        /// The hairline's width in pixels.
        public var pixels: Double { self == .strong ? 2 : 1 }
    }

    /// The colour of the artwork on posters, cards, tiles and stills. Full-screen hero artwork keeps its own.
    public enum ArtworkTone: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case natural, vivid, muted, dim, mono

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .natural: "Natural"
            case .mono: "Black & White"
            default: rawValue.capitalized
            }
        }

        public var saturation: Double {
            switch self {
            case .natural, .dim: 1
            case .vivid: 1.35
            case .muted: 0.55
            case .mono: 0
            }
        }

        public var brightness: Double { self == .dim ? -0.14 : 0 }
        public var contrast: Double { self == .vivid || self == .mono ? 1.06 : 1 }
    }

    /// The colour of the progress line on Continue cards.
    public enum ProgressColour: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case white, accent

        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }
    }

    public enum ProgressThickness: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case thin, standard, thick

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }

        public var points: Double {
            switch self {
            case .thin: 2
            case .standard: 3
            case .thick: 5
            }
        }
    }

    // MARK: - Layout

    /// How the app's pages are laid out: its own pages, or the editorial ones (on iPhone for now): a pill bar in place of the tab bar, a
    /// typeset Search with its results on the accent, and title pages set over their full-screen picture. Only presets set it: Arthouse
    /// the editorial pages, every other preset the standard ones.
    public enum Layout: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case standard, editorial

        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }
    }

    // MARK: - Buttons and headings

    /// How Play is filled: tinted glass in the title's artwork colour (the app's own), solid white with dark text, or the accent, solid.
    public enum PlayStyle: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case artwork, white, accent

        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }
    }

    /// What the buttons are made of: Liquid Glass, flat fills for a look whose app draws no glass (shown as Flat), or no fill at all
    /// (shown as Plain: every button, Play included, is its label alone). The saved values keep their first names.
    public enum ButtonFinish: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case glass, solid, flat

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .glass: "Glass"
            case .solid: "Flat"
            case .flat: "Plain"
            }
        }
    }

    /// The colour of shelf and section headings.
    public enum HeadingColour: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case primary, secondary, accent

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .primary: "Default"
            case .secondary: "Grey"
            case .accent: "Accent"
            }
        }
    }

    // MARK: - Title pages, navigation and motion

    public enum TitleSection: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case episodes, reviews, cast, information, franchise, related, watchAnywhere

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .episodes: "Episodes"
            case .reviews: "Reviews"
            case .cast: "Cast & Crew"
            case .information: "Information"
            case .franchise: "Collection"
            case .related: "More Like This"
            case .watchAnywhere: "Watch Anywhere"
            }
        }
    }

    /// The order of the two sections under a title's episodes.
    public enum SectionOrder: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case reviewsFirst, castFirst

        public var id: String { rawValue }
        public var label: String { self == .reviewsFirst ? "Reviews First" : "Cast First" }
    }

    /// The tab the app opens on when nothing else asks for one.
    public enum StartTab: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case home, discover, library, search

        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }

        public var tab: LaunchRoute.Tab {
            switch self {
            case .home: .home
            case .discover: .discover
            case .library: .library
            case .search: .search
            }
        }
    }

    /// How fast the app's own animations run: SwiftUI's, every one of them, scaled at the root. Off draws each change at once.
    /// System pushes, sheets and the keyboard keep the system's timing.
    public enum AnimationSpeed: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case off, slower, standard, faster, fastest

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }

        /// The speed multiplier; zero is Off.
        public var factor: Double {
            switch self {
            case .off: 0
            case .slower: 0.5
            case .standard: 1
            case .faster: 1.6
            case .fastest: 2.5
            }
        }
    }

    /// How long the Mac's hover feedback takes to light and fade, as a share of its own timing. Instant draws it at once.
    public enum HoverSpeed: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case instant, fast, standard, slow

        public var id: String { rawValue }
        public var label: String { self == .standard ? "Default" : rawValue.capitalized }

        /// The duration multiplier; zero is Instant.
        public var factor: Double {
            switch self {
            case .instant: 0
            case .fast: 0.5
            case .standard: 1
            case .slow: 2
            }
        }
    }

    /// The Mac's hover feedback: what lights, grows and lifts under the pointer (see `PointerInteraction.swift`). The defaults are the
    /// look the app always had. The iPhone has no pointer to hover, so nothing here reaches it.
    public struct Hover: Sendable, Equatable, Codable {
        public var isEnabled = true
        /// How much brighter a button or glass control draws under the pointer (`brightnessRange`).
        public var brightness: Double = 0.15
        /// How much a button or glass control grows under the pointer, as a share of its size (`growRange`).
        public var grow: Double = 0.025
        /// The white fill a glass control and a navigation segment take under the pointer (`fillRange`).
        public var glassFill: Double = 0.18
        public var showsRim = true
        /// The rim drawn round a glass control and a navigation segment under the pointer (`rimRange`).
        public var rimStrength: Double = 0.35
        /// How much a card the pointer follows grows under it, as a share of its size (`cardLiftRange`).
        public var cardLift: Double = 0.04
        public var cardShadow = true
        public var showsGlow = true
        /// The glow that follows the pointer across a card (`glowRange`).
        public var glowStrength: Double = 0.04
        public var speed: HoverSpeed = .standard
        /// The system's own hover highlight alongside the app's.
        public var systemHighlight = true

        public static let brightnessRange: ClosedRange<Double> = 0...0.4
        public static let growRange: ClosedRange<Double> = 0...0.1
        public static let fillRange: ClosedRange<Double> = 0...0.5
        public static let rimRange: ClosedRange<Double> = 0...1
        public static let cardLiftRange: ClosedRange<Double> = 0...0.12
        public static let glowRange: ClosedRange<Double> = 0...0.2

        public init() {}

        // The values the modifiers draw with: zero when hover feedback is off.

        public var buttonBrightness: Double { isEnabled ? brightness : 0 }
        public var buttonScale: Double { isEnabled ? 1 + grow : 1 }
        public var glassFillOpacity: Double { isEnabled ? glassFill : 0 }
        public var glassRimOpacity: Double { isEnabled && showsRim ? rimStrength : 0 }
        /// A navigation segment's fill and rim, a little quieter than a glass control's (0.16 and 0.3 by default).
        public var segmentFillOpacity: Double { glassFillOpacity * (0.16 / 0.18) }
        public var segmentRimOpacity: Double { glassRimOpacity * (0.3 / 0.35) }
        /// A card's highlight (0.08 by default; 0.012 for a card with the pointer glow), in step with the glass fill.
        public var cardFillOpacity: Double { glassFillOpacity * (0.08 / 0.18) }
        public var trackedCardFillOpacity: Double { glassFillOpacity * (0.012 / 0.18) }
        public var cardScale: Double { isEnabled ? 1 + cardLift : 1 }
        public var castsShadow: Bool { isEnabled && cardShadow }
        public var glowOpacity: Double { isEnabled && showsGlow ? glowStrength : 0 }
        public var usesSystemHighlight: Bool { isEnabled && systemHighlight }
        /// `duration` at this speed, or nil (no animation) for Instant.
        public func duration(_ duration: Double) -> Double? { speed.factor == 0 ? nil : duration * speed.factor }

        public init(from decoder: Decoder) throws {
            self.init()
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func read<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
                (try? container.decode(Value.self, forKey: key)) ?? fallback
            }
            func clamp(_ key: CodingKeys, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
                let value = read(key, fallback)
                return value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
            }
            isEnabled = read(.isEnabled, isEnabled)
            brightness = clamp(.brightness, brightness, Self.brightnessRange)
            grow = clamp(.grow, grow, Self.growRange)
            glassFill = clamp(.glassFill, glassFill, Self.fillRange)
            showsRim = read(.showsRim, showsRim)
            rimStrength = clamp(.rimStrength, rimStrength, Self.rimRange)
            cardLift = clamp(.cardLift, cardLift, Self.cardLiftRange)
            cardShadow = read(.cardShadow, cardShadow)
            showsGlow = read(.showsGlow, showsGlow)
            glowStrength = clamp(.glowStrength, glowStrength, Self.glowRange)
            speed = read(.speed, speed)
            systemHighlight = read(.systemHighlight, systemHighlight)
        }

        private enum CodingKeys: String, CodingKey {
            case isEnabled, brightness, grow, glassFill, showsRim, rimStrength, cardLift, cardShadow, showsGlow, glowStrength, speed,
                 systemHighlight
        }
    }
}
