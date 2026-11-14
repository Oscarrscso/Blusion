#if canImport(UIKit)
import SwiftUI
import UIKit

/// Settings → Appearance, drawn. The root applies the app-wide parts once (`appliesAppearance()`): the accent as the tint, the text size,
/// the font's design, width, weight, slant and spacing, the animation speed, and the preferences themselves in the environment. Pages read
/// the background from there, headings take `headingStyle()`, and cards, shelves and grids read their sizes, spacing, corners and columns
/// from `LayoutMetrics`, which folds the preferences in. Settings → Appearance's preview applies the same look to itself
/// (`appearanceLook(_:)`), so it can show a look before it is saved.
extension AppearancePreferences.RGB {
    var colour: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    var uiColour: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    /// The sRGB of a colour from the colour picker, kept within 0…1.
    init(_ colour: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(colour).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue))
    }

    /// A filled circle of this colour with a faint ring, which keeps the colour inside a menu (SwiftUI draws plain symbols in the text
    /// colour there) and keeps a near-black colour visible on a dark menu.
    var swatch: Image {
        let size = CGSize(width: 20, height: 20)
        let colour = uiColour
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            colour.setFill()
            context.cgContext.fillEllipse(in: circle)
            UIColor(white: 1, alpha: 0.35).setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: circle)
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
}

extension AppearancePreferences {
    /// The look as a swatch, for the preset menu and saved looks: its background with its accent at the centre, ringed like `swatch`.
    var lookSwatch: Image {
        let size = CGSize(width: 20, height: 20)
        let background = backgroundRGB.uiColour
        let accent = accentRGB.uiColour
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            background.setFill()
            context.cgContext.fillEllipse(in: circle)
            accent.setFill()
            context.cgContext.fillEllipse(in: circle.insetBy(dx: 4.5, dy: 4.5))
            UIColor(white: 1, alpha: 0.35).setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: circle)
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
}

extension AppearancePreferences {
    /// The tint, or nil to keep the asset catalogue's accent, which Blusion is.
    var accentColour: Color? {
        accent == .blusion ? nil : accentRGB.colour
    }

    /// Where the app draws a selected item in a colour of its own (the landscape tab buttons): the accent, or the app's own light blue.
    var selectionColour: Color {
        accentColour ?? Color(red: 0.50, green: 0.59, blue: 1)
    }

    /// The colour behind every page, which hero artwork fades into.
    var pageBackground: Color {
        background == .black ? Theme.background : backgroundRGB.colour
    }

    /// `pageBackground` as sRGB, for pages drawn outside SwiftUI (the reviews' web pages).
    var pageBackgroundRGB: AppearancePreferences.RGB {
        background == .black ? AppearancePreferences.RGB(red: 0, green: 0, blue: 0) : backgroundRGB
    }

    /// A background's colour, for its menu and the preview.
    func backgroundSwatch(_ background: Background) -> AppearancePreferences.RGB {
        var look = self
        look.background = background
        return look.backgroundRGB
    }

    /// The text sizes the app may use: the whole range when it follows the system, otherwise the one size chosen.
    var dynamicTypeRange: ClosedRange<DynamicTypeSize> { dynamicTypeRange(for: textSize) }

    func dynamicTypeRange(for size: TextSize) -> ClosedRange<DynamicTypeSize> {
        let chosen: DynamicTypeSize
        switch size {
        case .system: return DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5
        case .xSmall: chosen = .xSmall
        case .small: chosen = .small
        case .medium: chosen = .medium
        case .large: chosen = .large
        case .xLarge: chosen = .xLarge
        case .xxLarge: chosen = .xxLarge
        case .xxxLarge: chosen = .xxxLarge
        case .accessibility1: chosen = .accessibility1
        case .accessibility2: chosen = .accessibility2
        case .accessibility3: chosen = .accessibility3
        case .accessibility4: chosen = .accessibility4
        case .accessibility5: chosen = .accessibility5
        }
        return chosen...chosen
    }

    var fontDesign: Font.Design? { Self.systemDesign(font) }

    static func systemDesign(_ font: FontStyle) -> Font.Design? {
        switch font {
        case .standard: nil
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: nil
        }
    }

    static func design(_ font: FontStyle) -> Font.Design? { systemDesign(font) }

    func face(for role: TextRole) -> FontStyle { resolvedText(for: role).font }

    /// The token's own weight, unless this role has been given one. Reading's Bold keeps it too: the root's `bold()` makes that text
    /// bold, as the Bold Text switch did.
    func fontWeight(for role: TextRole, token: Font.Weight) -> Font.Weight {
        switch role {
        case .display: resolvedText(for: .display).weight.fontWeight
        case .reading: Self.readingWeight(reading.weight, token: token)
        case .interface: interface.followsWeight ? Self.readingWeight(reading.weight, token: token) : interface.weight.fontWeight
        }
    }

    private static func readingWeight(_ weight: HeadingWeight, token: Font.Weight) -> Font.Weight {
        weight == .regular || weight == .bold ? token : weight.fontWeight
    }

    /// `style`, stepped by a text style's size. Standard leaves it where it is.
    func shifted(_ style: Font.TextStyle, by scale: HeadingSize) -> Font.TextStyle {
        guard scale != .standard else { return style }
        // Body and headline share a point size. Count them as one step.
        let ladder: [Font.TextStyle] = [
            .caption2, .caption, .footnote, .subheadline, .callout, .body, .title3, .title2, .title, .largeTitle,
        ]
        let steps = switch scale {
        case .small: -1
        case .standard: 0
        case .large: 1
        case .huge: 2
        }
        guard let index = ladder.firstIndex(of: style == .headline ? .body : style) else { return style }
        return ladder[min(max(index + steps, 0), ladder.count - 1)]
    }

    /// `style` stepped the same way, for text laid out in UIKit.
    func shifted(_ style: UIFont.TextStyle, by scale: HeadingSize) -> UIFont.TextStyle {
        Self.uiTextStyle(shifted(Self.swiftTextStyle(style), by: scale))
    }

    private static func swiftTextStyle(_ style: UIFont.TextStyle) -> Font.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption1: .caption
        case .caption2: .caption2
        default: .body
        }
    }

    /// The face for `role` at a text style. A named face scales with Dynamic Type; a system design keeps the system's own.
    func font(style: Font.TextStyle, weight: Font.Weight, role: TextRole) -> Font {
        let face = face(for: role)
        if let family = face.familyName {
            let size = UIFont.preferredFont(forTextStyle: Self.uiTextStyle(style),
                                            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
            return Font.custom(family, size: size, relativeTo: style).weight(weight)
        }
        return Font.system(style, design: Self.systemDesign(face), weight: weight)
    }

    /// The same face as `font(style:weight:role:)`, for text laid out in UIKit.
    func uiFont(style: UIFont.TextStyle, weight: UIFont.Weight = .regular, role: TextRole, traits: UITraitCollection? = nil) -> UIFont {
        Self.font(face: face(for: role), style: style, weight: weight, traits: traits)
    }

    /// `face` at `style`, scaled for Dynamic Type. A missing named face falls back to the system font.
    static func font(face: FontStyle, style: UIFont.TextStyle, weight: UIFont.Weight = .regular, traits: UITraitCollection? = nil) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        let base: UIFont
        if let family = face.familyName, let named = namedFont(family: family, size: size, weight: weight) {
            base = named
        } else if let design = uiDesign(face),
                  let descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(design) {
            base = UIFont(descriptor: descriptor, size: size)
        } else {
            base = UIFont.systemFont(ofSize: size, weight: weight)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, compatibleWith: traits)
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }

    private static func uiDesign(_ face: FontStyle) -> UIFontDescriptor.SystemDesign? {
        switch face {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: nil
        }
    }

    /// The face in `family` nearest `weight`. Nil when the family is not installed.
    private static func namedFont(family: String, size: CGFloat, weight: UIFont.Weight) -> UIFont? {
        let names = UIFont.fontNames(forFamilyName: family)
        guard !names.isEmpty else { return UIFont(name: family, size: size) }
        let want = weightRank(weight)
        let chosen = names.min { lhs, rhs in
            abs(rank(of: lhs) - want) < abs(rank(of: rhs) - want)
        }
        return chosen.flatMap { UIFont(name: $0, size: size) }
    }

    private static func weightRank(_ weight: UIFont.Weight) -> Int {
        if weight < .light { return 0 }
        if weight < .regular { return 1 }
        if weight < .medium { return 2 }
        if weight < .semibold { return 3 }
        if weight < .bold { return 4 }
        if weight < .heavy { return 5 }
        return 6
    }

    private static func rank(of name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("ultralight") || lower.contains("thin") { return 0 }
        if lower.contains("light") { return 1 }
        if lower.contains("medium") { return 3 }
        if lower.contains("semibold") || lower.contains("demibold") { return 4 }
        if lower.contains("heavy") || lower.contains("black") { return 6 }
        if lower.contains("bold") { return 5 }
        return 2
    }
}

extension AppearancePreferences.HeadingWeight {
    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }

    var uiWeight: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

extension AppearancePreferences.FontWidth {
    /// A set width, including Default, so one role can leave the condensed letters of another.
    var fontWidth: Font.Width {
        switch self {
        case .compressed: .compressed
        case .condensed: .condensed
        case .standard: .standard
        case .expanded: .expanded
        }
    }

    var uiFontWidth: UIFont.Width {
        switch self {
        case .compressed: .compressed
        case .condensed: .condensed
        case .standard: .standard
        case .expanded: .expanded
        }
    }
}

extension AppearancePreferences {
    var systemFontWidth: Font.Width? {
        guard font == .standard else { return nil }
        return switch fontWidth {
        case .compressed: .compressed
        case .condensed: .condensed
        case .standard: nil
        case .expanded: .expanded
        }
    }

    /// The progress line's colour on Continue cards.
    var progressFill: Color {
        progressColour == .accent ? (accentColour ?? .accentColor) : .white
    }
}

extension CardAspect {
    /// Whether a card of this shape carries its name underneath when its caller leaves that to the shape: posters follow Appearance's
    /// Titles under posters; landscape and square cards always do.
    func showsCaption(_ appearance: AppearancePreferences) -> Bool {
        self == .poster ? appearance.showsPosterTitles : showsCaptionByDefault
    }
}

extension EnvironmentValues {
    /// Device Dynamic Type before Appearance applies the app size.
    @Entry var systemTextSize: DynamicTypeSize = .large

    /// Settings → Appearance, as the root read it (see `appliesAppearance()`).
    @Entry var appAppearance = AppearancePreferences()
}

extension View {
    /// Applies Settings → Appearance to everything inside, and keeps following it. Applied once, at the root.
    func appliesAppearance() -> some View {
        modifier(AppearanceModifier())
    }

    /// Draws everything inside with `appearance`: what the root does with the saved look, for a view (the Appearance preview) that shows
    /// a look of its own. The preview leaves out `motion`: the root's animation speed already reaches it, and twice would square it.
    func appearanceLook(_ appearance: AppearancePreferences, motion: Bool = true) -> some View {
        modifier(AppearanceLookModifier(appearance: appearance, motion: motion))
    }

    /// A shelf or section heading in Appearance's heading style: its font, size, weight, width, letter spacing and case.
    func headingStyle() -> some View {
        appFont(.shelfTitle)
    }

    /// A heading inside a section, in the same style one size down.
    func subheadingStyle() -> some View {
        appFont(style: .title3, weight: .bold, role: .display)
    }

    /// Posters, cards and stills in Appearance's artwork tone. Natural changes nothing.
    func artworkTone(_ tone: AppearancePreferences.ArtworkTone) -> some View {
        modifier(ArtworkToneModifier(tone: tone))
    }

    /// `transform` applied when `condition` holds; otherwise the view as it is, so it keeps what it inherits.
    @ViewBuilder
    func applying<Modified: View>(_ condition: Bool, _ transform: (Self) -> Modified) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private struct AppearanceModifier: ViewModifier {
    @AppStorage(AppearancePreferences.defaultsKey) private var appearance = AppearancePreferences()
    @Environment(\.dynamicTypeSize) private var systemTextSize

    func body(content: Content) -> some View {
        content.appearanceLook(appearance)
            .environment(\.systemTextSize, systemTextSize)
    }
}

private struct AppearanceLookModifier: ViewModifier {
    let appearance: AppearancePreferences
    let motion: Bool
    @Environment(\.systemTextSize) private var systemTextSize

    func body(content: Content) -> some View {
        let speed = motion ? appearance.animationSpeed.factor : 1
        content
            .tint(appearance.accentColour)
            .dynamicTypeSize(appearance.textSize == .system ? systemTextSize : appearance.dynamicTypeRange.lowerBound)
            .font(appearance.font(style: appearance.shifted(.body, by: appearance.reading.scale),
                                  weight: appearance.fontWeight(for: .reading, token: .regular), role: .reading))
            .fontDesign(appearance.fontDesign)
            .fontWidth(appearance.systemFontWidth)
            .bold(appearance.reading.weight == .bold)
            .italic(appearance.italicText)
            .tracking(appearance.letterSpacing.points)
            .lineSpacing(appearance.lineSpacing.points)
            .environment(\.appAppearance, appearance)
            // Off stops every SwiftUI animation inside, implicit ones included; another speed scales the animations changes carry.
            .transaction { transaction in
                if speed == 0 {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                } else if speed != 1 {
                    transaction.animation = transaction.animation?.speed(speed)
                }
            }
    }
}

private struct ArtworkToneModifier: ViewModifier {
    let tone: AppearancePreferences.ArtworkTone

    @ViewBuilder
    func body(content: Content) -> some View {
        if tone == .natural {
            content
        } else {
            content
                .saturation(tone.saturation)
                .brightness(tone.brightness)
                .contrast(tone.contrast)
        }
    }
}
#endif
