#if canImport(UIKit)
import SwiftUI
import UIKit

/// Design tokens. Screens take their spacing, radii and colours from here so every screen lines up on the same grid.
/// Sizes that differ between a phone and a Mac window (page margin, poster width, shelf spacing) live in `LayoutMetrics`.
enum Theme {
    /// All controls derived from Play share this tint on iPhone and Mac. See docs/DESIGN_SPEC.md.
    @MainActor
    static func playControlColour(hex: String?) -> Color? {
        PlayColourStore.colour(hex: hex)?.opacity(0.38)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        /// Small containers: episode stills, progress tracks.
        static let small: CGFloat = 10
        /// Poster artwork.
        static let poster: CGFloat = 10
        /// Wide artwork: Up Next cards, landscape cards, category tiles.
        static let card: CGFloat = 12
        /// Grouped surfaces and panels (the system's inset-grouped corner).
        static let surface: CGFloat = 20
    }

    /// Horizontal inset of screen content on a phone. Zero: content runs edge to edge. Adaptive screens read `LayoutMetrics.pageMargin`.
    static let screenPadding: CGFloat = 0
    /// The height of the system navigation bar, and the diameter of the round glass button it holds (the title page's back button). A round
    /// button beside a screen's content is drawn at this size so it lines up with the bar's own.
    static let barButtonDiameter: CGFloat = 44
    /// Vertical gap between rows on a phone browse screen. Adaptive screens read `LayoutMetrics.shelfSpacing`.
    static let rowSpacing: CGFloat = 28
    /// Gap between cards in a row or a grid on a phone. Adaptive screens read `LayoutMetrics.cardSpacing`.
    static let cardSpacing: CGFloat = 12

    /// The TV app's page: pure black, edge to edge. Appearance's Background can choose another (`AppearancePreferences.pageBackground`).
    static let background = Color.black
    /// A raised surface on the black page (grouped panels, placeholders): the system's dark secondary grouped grey.
    static let surface = Color.white.opacity(0.11)
    static let surfaceStrong = Color.white.opacity(0.18)
    /// The least width of a card's hairline, in points: zero, so plain, glass and material cards draw the artwork's one-pixel line.
    static let cardHairlineWidth: CGFloat = 0
    static let separator = Color.white.opacity(0.12)
    /// The faint line between a title page's sections: fainter than `separator`, so it parts them without drawing the eye.
    static let sectionLine = Color.white.opacity(0.06)
    static let artworkBorder = Color.white.opacity(AppearancePreferences.Outline.standard.opacity)
    /// The grey of the metadata line under a title's name, on Home's spotlight and on the title page alike. A fixed colour rather than a
    /// hierarchical style, so the line never takes a tint from the view around it.
    static let metaText = Color(white: 0.58)
    /// White type over artwork, glass and the player, in three strengths below full white: a second line, a quieter label, a note.
    static let dimText = Color.white.opacity(0.75)
    static let dimmerText = Color.white.opacity(0.7)
    static let faintText = Color.white.opacity(0.6)
    /// Flat grey shown where artwork is still loading. Opaque, so a card never shows what is behind it.
    static let placeholder = Color(white: 0.11)
    static let brandStart = Color(red: 0.12, green: 0.30, blue: 0.86)
    static let brandEnd = Color(red: 0.48, green: 0.17, blue: 1.0)
    static let brandGradient = LinearGradient(colors: [brandStart, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The app's shared timings. A view with a motion of its own keeps its own curve; these are the ones most views share.
    enum Motion {
        /// A control or panel changing state: a tint arriving, a section opening.
        static let standard = Animation.smooth(duration: 0.3)
        /// The same, for a smaller change.
        static let quick = Animation.smooth(duration: 0.25)
        /// A control snapping to a new place or size.
        static let snap = Animation.snappy(duration: 0.35)
        /// Something fading in or out.
        static let fade = Animation.easeOut(duration: 0.2)
        /// A state toggling back and forth.
        static let toggle = Animation.easeInOut(duration: 0.2)
    }

    /// The app's type. Every style is a system text style, so Dynamic Type and Appearance's text settings reach it.
    ///
    /// A view names a role below when one fits what it draws (a card's title, a meta line), and otherwise a step of the scale. It does
    /// not write `.font(.footnote)` or `.font(.subheadline.weight(.semibold))` itself, so a size or weight is retuned here, once.
    /// A further trait chains on: `Theme.Typography.small.monospacedDigit()`.
    enum Typography {
        // MARK: Scale
        // Five sizes, each plain and strong (semibold), and the headline. Roles are built from these.

        /// Reading text in a panel or a list row.
        static let large = Font.body
        static let largeStrong = Font.body.weight(.semibold)
        /// The name of a row or a panel, and a button's label.
        static let headline = Font.headline
        /// The app's everyday text: copy, a control's label, a row's value.
        static let medium = Font.subheadline
        static let mediumStrong = Font.subheadline.weight(.semibold)
        /// Secondary lines: metadata, notes, a status.
        static let small = Font.footnote
        static let smallStrong = Font.footnote.weight(.semibold)
        /// The line under something, and small symbols.
        static let caption = Font.caption
        static let captionStrong = Font.caption.weight(.semibold)
        /// The smallest type: badges and eyebrows.
        static let micro = Font.caption2
        static let microStrong = Font.caption2.weight(.semibold)

        // MARK: Roles

        /// A shelf header: "Continue Watching", "Season 2". Headings draw through `headingStyle()`, which Appearance can restyle.
        static let shelfTitle = Font.title2.bold()
        /// The title under a card, and a row title.
        static let cardTitle = smallStrong
        /// The grey line under a card title: "S2, E5 · 21 min left".
        static let cardSubtitle = caption
        /// The small grey caps above an episode title: "EPISODE 5". Apply `.textCase(.uppercase)` too.
        static let eyebrow = microStrong
        /// A screen's large title ("Search", "Library") when it draws its own.
        static let largeTitle = Font.largeTitle.bold()
        /// The name of a title on its own page when there is no logo artwork.
        static let heroTitle = Font.system(.largeTitle, design: .default, weight: .bold)
        /// The single grey line under a title's name: "Drama · 2008 · 2 hr 32 min".
        static let metaLine = small
        /// Body copy such as a synopsis.
        static let body = medium
        /// A label inside a button.
        static let button = headline

        /// One step of type, so a view can ask for it by role (display, interface, or reading) instead of a fixed face.
        enum Token {
            case large, largeStrong, headline, medium, mediumStrong, small, smallStrong
            case caption, captionStrong, micro, microStrong
            case shelfTitle, cardTitle, cardSubtitle, eyebrow, largeTitle, heroTitle, metaLine, body, button

            var role: AppearancePreferences.TextRole {
                switch self {
                case .large, .largeStrong, .body: .reading
                case .shelfTitle, .largeTitle, .heroTitle: .display
                default: .interface
                }
            }

            var style: Font.TextStyle {
                switch self {
                case .large, .largeStrong: .body
                case .headline, .button: .headline
                case .medium, .mediumStrong, .body: .subheadline
                case .small, .smallStrong, .metaLine: .footnote
                case .caption, .captionStrong, .cardTitle, .cardSubtitle: .caption
                case .micro, .microStrong, .eyebrow: .caption2
                case .shelfTitle: .title2
                case .largeTitle, .heroTitle: .largeTitle
                }
            }

            var weight: Font.Weight {
                switch self {
                case .large, .medium, .small, .caption, .micro, .cardSubtitle, .metaLine, .body: .regular
                case .largeStrong, .headline, .mediumStrong, .smallStrong, .captionStrong, .microStrong, .cardTitle, .eyebrow, .button: .semibold
                case .shelfTitle, .largeTitle, .heroTitle: .bold
                }
            }
        }
    }
}

extension View {
    /// Type from Settings → Appearance: the token's role picks the display, interface, or reading face.
    func appFont(_ token: Theme.Typography.Token, monospacedDigits: Bool = false, weight: Font.Weight? = nil,
                 role: AppearancePreferences.TextRole? = nil) -> some View {
        modifier(AppFontModifier(token: token, monospacedDigits: monospacedDigits, weight: weight, role: role))
    }

    /// The same faces, for a text style that has no token. The first argument is labeled so it never collides with a token.
    func appFont(style: Font.TextStyle, weight: Font.Weight = .regular, role: AppearancePreferences.TextRole = .interface,
                 monospacedDigits: Bool = false) -> some View {
        modifier(StyleAppFontModifier(style: style, weight: weight, role: role, monospacedDigits: monospacedDigits))
    }

    /// A fixed size on artwork, in the interface face, still following the text-size setting through `relativeTo`.
    func appFont(size: CGFloat, weight: Font.Weight = .regular, role: AppearancePreferences.TextRole = .interface,
                 relativeTo style: Font.TextStyle = .caption2) -> some View {
        modifier(FixedAppFontModifier(size: size, weight: weight, role: role, style: style))
    }
}

private struct StyleAppFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight
    let role: AppearancePreferences.TextRole
    var monospacedDigits = false
    @Environment(\.appAppearance) private var appearance

    func body(content: Content) -> some View {
        content
            .font(monospacedDigits ? base.monospacedDigit() : base)
            .roleTextChrome(role)
    }

    private var base: Font {
        let resolved = appearance.resolvedText(for: role)
        let sized = appearance.shifted(style, by: resolved.scale)
        return appearance.font(style: sized, weight: appearance.fontWeight(for: role, token: weight), role: role)
    }
}

private struct AppFontModifier: ViewModifier {
    let token: Theme.Typography.Token
    var monospacedDigits = false
    var weight: Font.Weight?
    var role: AppearancePreferences.TextRole?
    @Environment(\.appAppearance) private var appearance

    func body(content: Content) -> some View {
        content
            .font(monospacedDigits ? base.monospacedDigit() : base)
            .roleTextChrome(role ?? token.role)
    }

    private var base: Font {
        let resolvedRole = role ?? token.role
        let resolved = appearance.resolvedText(for: resolvedRole)
        let sized = appearance.shifted(token.style, by: resolved.scale)
        return appearance.font(style: sized, weight: appearance.fontWeight(for: resolvedRole, token: weight ?? token.weight),
                               role: resolvedRole)
    }
}

private struct FixedAppFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let role: AppearancePreferences.TextRole
    let style: Font.TextStyle
    @Environment(\.appAppearance) private var appearance

    func body(content: Content) -> some View {
        let face = appearance.face(for: role)
        let weight = appearance.fontWeight(for: role, token: self.weight)
        let font: Font = if let family = face.familyName {
            Font.custom(family, size: size, relativeTo: style).weight(weight)
        } else {
            Font.system(size: size, weight: weight, design: AppearancePreferences.systemDesign(face) ?? .default)
        }
        content
            .font(font)
            .roleTextChrome(role)
    }
}

/// Apply the role's overrides inside the app-wide body style. Primary colour keeps the caller's usual contrast.
private struct RoleTextChrome: ViewModifier {
    let role: AppearancePreferences.TextRole
    @Environment(\.appAppearance) private var appearance
    @Environment(\.systemTextSize) private var systemTextSize

    @ViewBuilder
    func body(content: Content) -> some View {
        let style = appearance.resolvedText(for: role)
        let overrides = role != .reading
        let shaped = content
            .applying(overrides || style.font != .standard) {
                $0.fontWidth(style.font == .standard ? style.width.fontWidth : .standard)
            }
            .applying(overrides && !style.followsWeight && appearance.reading.weight == .bold) { $0.bold(false) }
            .applying(overrides && !style.followsItalic) { $0.italic(style.italic) }
        let spaced = shaped
            .applying(overrides && !style.followsLetterSpacing) { $0.tracking(style.letterSpacing.points) }
            .applying(overrides && !style.followsLineSpacing) { $0.lineSpacing(style.lineSpacing.points) }
        let sized = spaced
            .applying(overrides && !style.followsTextSize) {
                $0.dynamicTypeSize(style.textSize == .system ? systemTextSize : appearance.dynamicTypeRange(for: style.textSize).lowerBound)
            }
            .applying(style.capitals) { $0.textCase(.uppercase) }
        switch style.colour {
        case .primary: sized
        case .secondary: sized.foregroundStyle(.secondary)
        case .accent: sized.foregroundStyle(.tint)
        }
    }
}

private extension View {
    func roleTextChrome(_ role: AppearancePreferences.TextRole) -> some View {
        modifier(RoleTextChrome(role: role))
    }
}

extension View {
    /// The app's screen background: pure black edge to edge, like the TV app. Artwork is the only colour on screen.
    func screenBackground(reservesNavigationSpace: Bool = true) -> some View {
        modifier(ScreenBackgroundModifier(reservesNavigationSpace: reservesNavigationSpace))
    }

    /// A subtle translucent rounded surface for grouped content. Deliberately not glass: glass is for controls over media.
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.surface, group: AppearancePreferences.CornerGroup = .panels) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius, kind: .plain, group: group))
    }

    /// Glass for a card of content (a stream, a panel) with its translucent hairline. Cards share `Theme.Radius.card`.
    func glassCardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius, kind: .glass))
    }

    /// A translucent rounded surface for a panel that holds glass controls, with the same hairline as `glassCardSurface`. It is the
    /// system's material and not glass: glass chips and buttons inside a glass panel would be glass on glass.
    func translucentPanelSurface(cornerRadius: CGFloat = Theme.Radius.surface) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius, kind: .material))
    }

    /// The translucent hairline that edges a glass card or panel, drawn just inside `shape`.
    func glassHairline(_ shape: some InsettableShape) -> some View {
        overlay { CardOutline(shape: shape, minimumWidth: Theme.cardHairlineWidth) }
    }

    /// The same inset, one-pixel hairline for posters, cards and tiles. Full-screen hero artwork does not use it.
    func mediaArtwork(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(MediaArtworkModifier(cornerRadius: cornerRadius))
    }
}

/// Surfaces and their hairlines follow the same Corners setting as artwork.
private struct CardSurfaceModifier: ViewModifier {
    enum Kind { case plain, glass, material }
    let cornerRadius: CGFloat
    let kind: Kind
    var group: AppearancePreferences.CornerGroup = .panels
    @Environment(\.layoutMetrics) private var metrics

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius * metrics.cornerScale(for: group), style: .continuous)
        switch kind {
        case .plain:
            content.background(Theme.surface, in: shape)
                .overlay { CardOutline(shape: shape, minimumWidth: Theme.cardHairlineWidth) }
        case .glass:
            content.glassEffect(.regular, in: shape).glassHairline(shape)
        case .material:
            content.background(.regularMaterial, in: shape).glassHairline(shape)
        }
    }
}

/// Pills use half their height at 100%, and become square with the other corners at 0%.
struct ScaledCapsule: InsettableShape {
    var scale: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(rect.width, rect.height) / 2 * scale)
            .inset(by: insetAmount)
            .path(in: rect)
    }

    func inset(by amount: CGFloat) -> ScaledCapsule {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

struct CardOutline<S: InsettableShape>: View {
    let shape: S
    var minimumWidth: CGFloat = 0
    @Environment(\.appAppearance) private var appearance
    @Environment(\.pixelLength) private var pixelLength

    var body: some View {
        let outline = appearance.outline
        shape.strokeBorder(Color.white.opacity(outline.opacity), lineWidth: max(minimumWidth, pixelLength) * outline.pixels)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct MediaArtworkModifier: ViewModifier {
    let cornerRadius: CGFloat
    /// Appearance's corners scale every artwork's radius alike.
    @Environment(\.layoutMetrics) private var metrics
    /// Appearance's Outline sets the hairline's strength (or turns it off), and its Artwork tone the picture's colour.
    @Environment(\.appAppearance) private var appearance

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius * metrics.cornerScale(for: .artwork), style: .continuous)
        content
            .artworkTone(appearance.artworkTone)
            .clipShape(shape)
            .overlay { CardOutline(shape: shape) }
    }
}

/// A hero is clear at rest; once it scrolls, the system protects the portrait status/navigation edge.
struct HeroScrollEdgeModifier: ViewModifier {
    let scroll: DetailHeroScrollState
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.scrollEdgeEffectHidden(true, for: .top)
        #else
        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(isPhoneLandscape || scroll.offset <= 1, for: .top)
        #endif
    }
}

private struct ScreenBackgroundModifier: ViewModifier {
    let reservesNavigationSpace: Bool
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape
    @Environment(\.appAppearance) private var appearance

    /// On iPhone every page's top edge gets the system's soft scroll-edge blur, and hero pages (Home's spotlight, Detail) hide it so it never
    /// shows over their artwork at rest. Mac keeps the top edge clear so no fixed band follows the scrolling page.
    @ViewBuilder
    func body(content: Content) -> some View {
        // Keep the same view hierarchy through rotation so scrolling and artwork tasks survive.
        content.background { appearance.pageBackground.ignoresSafeArea() }
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(isPhoneLandscape || Self.isMacCatalyst, for: .top)
            .scrollEdgeEffectHidden(isPhoneLandscape && UIDevice.current.userInterfaceIdiom == .phone, for: .bottom)
            .pageTopBar(hidden: isPhoneLandscape)
            .macPageScroll(reservesNavigationSpace: reservesNavigationSpace)
    }

    /// Mac builds keep the top bar clear (see `pageTopBar`), with no soft edge.
    private static var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
}

extension View {
    /// The shared top edge for root browsing grids. In phone landscape the page uses the space normally reserved for a navigation bar,
    /// then restores the app's standard margin so Library, Discover and category grids start on the same line.
    /// `underLargeTitle`: the system's large title stands over the page (See All), with room of its own under its baseline, so the
    /// content starts closer and the gap under the title's letters matches the one between Back and their top.
    func browsePageTopMargin(underLargeTitle: Bool = false) -> some View {
        modifier(BrowsePageTopMarginModifier(underLargeTitle: underLargeTitle))
    }

    /// A page's navigation background. Mac keeps it transparent while retaining native Back, Search and toolbar controls.
    /// iPhone hides the background when `hidden`, and uses the system's normal background otherwise.
    func pageTopBar(hidden: Bool) -> some View {
        modifier(PageTopBarModifier(hidden: hidden))
    }
}

private struct BrowsePageTopMarginModifier: ViewModifier {
    let underLargeTitle: Bool
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // The shared Mac scroll modifier reserves the navigation space for every page.
        content
        #else
        let usesLandscapeEdge = isPhoneLandscape && UIDevice.current.userInterfaceIdiom == .phone
        content
            .ignoresSafeArea(.container, edges: usesLandscapeEdge ? .top : [])
            // A phone on its side shows no large title.
            .contentMargins(.top, underLargeTitle && !isPhoneLandscape ? Theme.Spacing.xs : Theme.Spacing.l, for: .scrollContent)
        #endif
    }
}

private struct PageTopBarModifier: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        #else
        content.toolbarBackgroundVisibility(hidden ? .hidden : .automatic, for: .navigationBar)
        #endif
    }
}

/// A fade from clear to the page's background (black unless Appearance chose another), eased so there is no visible edge where it
/// starts. Hero artwork and the backdrops of title pages end in one. `length` is the share of the height the fade covers, measured from
/// the bottom. On a title page with a Blurred background, it fades into that instead (see `pageBackdrop`).
struct BottomFade: View {
    var length: Double = 0.55
    var strength: Double = 1
    @Environment(\.appAppearance) private var appearance
    @Environment(\.pageBackdrop) private var backdrop

    var body: some View {
        ZStack {
            if let backdrop {
                Image(uiImage: backdrop)
                    .resizable()
                    .mask { gradient(.black) }
                    .transition(.opacity)
            } else {
                gradient(appearance.pageBackground)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func gradient(_ colour: Color) -> LinearGradient {
        let start = max(0, 1 - length)
        return LinearGradient(stops: [
            .init(color: colour.opacity(0), location: start),
            .init(color: colour.opacity(0.10 * strength), location: start + (1 - start) * 0.18),
            .init(color: colour.opacity(0.32 * strength), location: start + (1 - start) * 0.40),
            .init(color: colour.opacity(0.62 * strength), location: start + (1 - start) * 0.65),
            .init(color: colour.opacity(0.88 * strength), location: start + (1 - start) * 0.85),
            .init(color: colour.opacity(strength), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}
#endif
