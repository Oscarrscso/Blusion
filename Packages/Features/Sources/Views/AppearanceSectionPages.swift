#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

// MARK: - The parts

struct AppearanceColourPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Colour", section: .colour) { controls in
            Section { controls.preview([.playRow]) }
            Section {
                Picker("Accent", selection: controls.choice(\.accent)) {
                    ForEach(AppearancePreferences.Accent.allCases) { accent in
                        Label { Text(accent.label) } icon: { (accent.rgb ?? controls.current.customAccent).swatch }
                            .tag(accent)
                    }
                }
                .settingsHover()
                .accessibilityIdentifier("settings.appearance.accent")
                if controls.current.accent == .custom {
                    ColorPicker("Custom accent", selection: controls.colour(\.customAccent), supportsOpacity: false)
                        .settingsHover()
                        .accessibilityIdentifier("settings.appearance.customAccent")
                }
                Picker("Background", selection: controls.choice(\.background)) {
                    ForEach(AppearancePreferences.Background.allCases) { background in
                        Label { Text(background.label) } icon: { controls.current.backgroundSwatch(background).swatch }
                            .tag(background)
                    }
                }
                .settingsHover()
                .accessibilityIdentifier("settings.appearance.background")
                if controls.current.background == .custom {
                    ColorPicker("Custom background", selection: controls.colour(\.customBackground), supportsOpacity: false)
                        .settingsHover()
                        .accessibilityIdentifier("settings.appearance.customBackground")
                }
                if controls.current.background == .tinted {
                    controls.slider("Tint strength", \.tintStrength, in: AppearancePreferences.tintStrengthRange, step: 0.01,
                                    low: "circle.lefthalf.filled", high: "circle.fill", id: "tintStrength")
                }
            }
            SettingsSection("Buttons") {
                controls.segmented("Play button", \.playStyle, id: "playStyle")
                controls.segmented("Finish", \.buttonFinish, id: "buttonFinish")
            }
        }
    }
}

struct AppearanceTextPage: View {
    @State private var expandedRoles: Set<AppearancePreferences.TextRole> = []
    var body: some View {
        AppearanceSectionPage(title: "Text", section: .text) { controls in
            Section {
                controls.menu("App text size", \.textSize, id: "text.reading.textSize")
            }
            Section {
                ForEach(AppearancePreferences.TextRole.allCases) { role in
                    DisclosureGroup(isExpanded: Binding(get: { expandedRoles.contains(role) }, set: { expanded in
                        if expanded { expandedRoles.insert(role) } else { expandedRoles.remove(role) }
                    })) {
                        TextRoleOptions(role: role, controls: controls)
                    } label: {
                        LabeledContent(role.label, value: controls.current.textRoleSummary(role))
                            .settingsHover()
                    }
                    .accessibilityIdentifier("settings.appearance.text.\(role.rawValue)")
                    if expandedRoles.contains(role) {
                        controls.preview([sample(for: role)], contentPadding: Theme.Spacing.m)
                    }
                }
            }
        }
    }

    private func sample(for role: AppearancePreferences.TextRole) -> AppearanceSample {
        switch role {
        case .reading: .synopsis
        case .interface: .filters
        case .display: .heading
        }
    }
}

private struct TextRoleOptions: View {
    let role: AppearancePreferences.TextRole
    let controls: AppearanceControls

    var body: some View {
        // Older looks may have an independent Dynamic Type size. Keep it editable until linked again.
        if role != .reading, !controls.current.storedText(for: role).followsTextSize {
            controls.textMenu("Text size override", role, \.textSize, follow: \.followsTextSize, id: "textSize")
        }
        controls.textMenu("Relative size", role, \.scale, follow: \.followsScale, id: "size")
        controls.textMenu("Font", role, \.font, follow: \.followsFont, id: "font")
        if controls.current.face(for: role) == .standard {
            controls.textMenu("Width", role, \.width, follow: \.followsWidth, id: "width")
        }
        controls.textMenu("Weight", role, \.weight, follow: \.followsWeight, id: "weight")
        if role == .reading {
            controls.textToggle("Italic", role, \.italic, id: "italic")
        } else {
            controls.textSlant(role)
        }
        controls.textMenu("Letter spacing", role, \.letterSpacing, follow: \.followsLetterSpacing, id: "letterSpacing")
        controls.textMenu("Line spacing", role, \.lineSpacing, follow: \.followsLineSpacing, id: "lineSpacing")
        controls.textMenu("Colour", role, \.colour, id: "colour")
        controls.textToggle("All caps", role, \.capitals, id: "caps")
    }
}

struct AppearanceCardsPage: View {
    @AppStorage(AppearancePreferences.defaultsKey) private var appearance = AppearancePreferences()

    var body: some View {
        AppearanceSectionPage(title: "Cards", section: .cards) { controls in
            Section { controls.preview([.continueWatching, .posters]) }
            SettingsSection("Size & Shape") {
                controls.slider("Card size", \.cardScale, in: AppearancePreferences.cardScaleRange, step: 0.05,
                                low: "rectangle.portrait", high: "rectangle.portrait", id: "cardSize")
                controls.slider("Spacing", \.spacingScale, in: AppearancePreferences.spacingScaleRange, step: 0.05,
                                low: "arrow.down.right.and.arrow.up.left", high: "arrow.up.left.and.arrow.down.right", id: "spacing")
                if isPhone {
                    controls.columnSlider("Portrait columns", \.phoneGridColumns, id: "columns")
                    controls.columnSlider("Landscape columns", \.phoneLandscapeGridColumns, id: "landscapeColumns")
                }
            }
            SettingsSection("Shelves") {
                controls.slider("Shelf spacing", read: { $0.effectiveShelfSpacingScale }, write: { $0.shelfSpacingScale = $1 },
                                in: AppearancePreferences.shelfSpacingScaleRange, step: 0.05,
                                low: "arrow.down.right.and.arrow.up.left", high: "arrow.up.left.and.arrow.down.right", id: "shelfSpacing")
                controls.slider("Side margin", \.sideMarginScale, in: AppearancePreferences.sideMarginScaleRange, step: 0.05,
                                low: "arrow.right.to.line", high: "arrow.left.and.right", id: "sideMargin")
            }
            SettingsSection("Captions") {
                controls.toggle("Titles under posters", \.showsPosterTitles, id: "posterTitles")
                controls.numbers("Title lines", \.captionLines, in: AppearancePreferences.captionLineRange, id: "titleLines")
                controls.toggle("Titles in capitals", \.uppercaseCaptions, id: "captionCaps")
                controls.toggle("Genre and year", \.showsCaptionDetails, id: "captionDetails")
            }
            SettingsSection("Artwork") {
                controls.menu("Tone", \.artworkTone, id: "tone")
                controls.segmented("Outline", \.outline, id: "outline")
                controls.toggle("Outline buttons", \.outlinesButtons, id: "buttonOutline")
                Toggle("Hero artwork on posters", isOn: controls.choice(\.usesHeroPosters))
                    .accessibilityIdentifier("settings.heroPosters")
                Toggle("Ratings on posters", isOn: controls.choice(\.showsPosterRatings))
                    .accessibilityIdentifier("settings.posterRatings")
                Toggle("Disc and streamer marks", isOn: controls.choice(\.showsBestDiscOnPosters))
                    .accessibilityIdentifier("settings.bestDiscOnPosters")
                if appearance.showsBestDiscOnPosters {
                    Picker("Mark position", selection: controls.choice(\.posterMarkPlacement)) {
                        ForEach(PosterMarkPlacement.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .settingsHover()
                    .accessibilityIdentifier("settings.posterBrandLocation")
                }
                Toggle("Coloured rating logos", isOn: controls.choice(\.showsColouredRatingLogos))
                    .accessibilityIdentifier("settings.colouredRatingLogos")
            }
            SettingsSection("Progress") {
                controls.segmented("Colour", \.progressColour, id: "progressColour")
                controls.segmented("Thickness", \.progressThickness, id: "progressThickness")
                controls.toggle("Time left", \.showsTimeLeft, id: "timeLeft")
            }
        }
    }
}

struct AppearanceCornersPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Corners", section: .corners) { controls in
            Section { controls.preview([.playRow, .posters]) }
            SettingsSection("All Corners") {
                controls.slider("Roundness", \.cornerScale, in: AppearancePreferences.cornerScaleRange, step: 0.1,
                                low: "square", high: "circle", id: "corners")
                controls.toggle("Reshape round buttons", \.includesCircularButtons, id: "circularCorners")
            }
            SettingsSection("Each Part") {
                ForEach(AppearancePreferences.CornerGroup.allCases) { group in
                    DisclosureGroup {
                        if let sample = AppearanceSample(corners: group) { controls.preview([sample]) }
                        Toggle("Same as all corners", isOn: Binding(get: {
                            controls.current.cornerOverrides[group.rawValue] == nil
                        }, set: { follows in
                            Haptics.play(.choices)
                            var look = controls.appearance.wrappedValue
                            look.cornerOverrides[group.rawValue] = follows ? nil : look.cornerScale(for: group)
                            controls.appearance.wrappedValue = look
                        }))
                        if controls.current.cornerOverrides[group.rawValue] != nil {
                            controls.slider("Roundness", read: { $0.cornerScale(for: group) },
                                            write: { $0.cornerOverrides[group.rawValue] = $1 },
                                            in: AppearancePreferences.cornerScaleRange, step: 0.1,
                                            low: "square", high: "circle", id: "corners.\(group.rawValue)")
                        }
                    } label: {
                        // A part with its own roundness shows it; one that follows All Corners says so, rather than repeating its number.
                        LabeledContent(group.label, value: controls.current.cornerOverrides[group.rawValue].map(percent) ?? "Same as All")
                            .settingsHover()
                    }
                }
            }
        }
    }
}

struct AppearanceHomePage: View {
    var body: some View {
        AppearanceSectionPage(title: "Home", section: .home) { controls in
            Section {
                Picker("Turn showcase pages", selection: controls.choice(\.heroAutoAdvance)) {
                    ForEach(AppearancePreferences.heroAutoAdvanceOptions, id: \.self) { seconds in
                        Text(seconds == 0 ? "Never" : "Every \(seconds) seconds").tag(seconds)
                    }
                }
                .settingsHover()
                .accessibilityIdentifier("settings.appearance.turnPages")
                Stepper("Continue Watching: \(controls.current.continueWatchingLimit)",
                        value: controls.choice(\.continueWatchingLimit), in: 1...100)
                    .settingsHover()
                    .accessibilityIdentifier("settings.appearance.continueWatchingLimit")
            }
            SettingsSection("Lines") {
                controls.toggle("Lines between shelves", \.showsShelfDividers, id: "shelfDividers")
                if controls.current.showsShelfDividers {
                    controls.slider("Line thickness", \.shelfDividerThickness, in: AppearancePreferences.shelfDividerThicknessRange,
                                    step: 0.5, low: "minus", high: "minus", id: "dividerThickness")
                    controls.slider("Line strength", \.shelfDividerOpacity, in: AppearancePreferences.shelfDividerOpacityRange,
                                    step: 0.01, low: "circle.lefthalf.filled", high: "circle.fill", id: "dividerStrength")
                    controls.toggle("Line edge to edge", \.shelfDividerFullWidth, id: "dividerFullWidth")
                }
            }
        }
    }
}

struct AppearanceTitlePagesPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Title Pages", section: .titlePages) { controls in
            SettingsSection("Spoilers") {
                controls.toggle("Hide spoilers", \.hidesSpoilers, id: "spoilers")
                if controls.current.hidesSpoilers {
                    controls.toggle("Blur stills", \.spoilerStills, id: "spoilerStills")
                    controls.toggle("Hide synopses", \.spoilerSynopses, id: "spoilerSynopses")
                    controls.toggle("Hide episode titles", \.spoilerTitles, id: "spoilerTitles")
                }
            }
            if controls.current.hidesSpoilers {
                Section { controls.preview([.episodes]) }
            }
            Section {
                controls.toggle("Unfold synopsis", \.expandsSynopsis, id: "unfoldSynopsis")
                controls.toggle("Poster background", \.blursBackground, id: "blurredBackground")
                if isPhone {
                    controls.toggle("Tab bar on title pages", \.showsTitlePageTabBar, id: "titlePageTabBar")
                }
            }
            SettingsSection("Lines") {
                controls.toggle("Same as Home", \.titleDividersFollowHome, id: "titleDividersFollowHome")
                if !controls.current.titleDividersFollowHome {
                    controls.toggle("Lines between sections", \.showsTitleDividers, id: "titleDividers")
                    if controls.current.showsTitleDividers {
                        controls.slider("Line thickness", \.titleDividerThickness, in: AppearancePreferences.shelfDividerThicknessRange,
                                        step: 0.5, low: "minus", high: "minus", id: "titleDividerThickness")
                        controls.slider("Line strength", \.titleDividerOpacity, in: AppearancePreferences.shelfDividerOpacityRange,
                                        step: 0.01, low: "circle.lefthalf.filled", high: "circle.fill", id: "titleDividerStrength")
                        controls.toggle("Line edge to edge", \.titleDividerFullWidth, id: "titleDividerFullWidth")
                    }
                }
            }
            SettingsSection("Section order") {
                ForEach(controls.current.orderedTitleSections) { section in
                    HStack {
                        Text(section.label)
                            .foregroundStyle(controls.current.showsTitleSection(section) ? .primary : .secondary)
                        Spacer()
                        if let keyPath = visibilityKeyPath(for: section) {
                            let visible = controls.current.showsTitleSection(section)
                            Button {
                                controls.choice(keyPath).wrappedValue.toggle()
                            } label: {
                                Image(systemName: visible ? "eye" : "eye.slash")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            #if targetEnvironment(macCatalyst)
                            .buttonStyle(.settingsHover)
                            #else
                            .buttonStyle(.hoverPlain)
                            #endif
                            .accessibilityLabel("\(visible ? "Hide" : "Show") \(section.label)")
                            .accessibilityValue(visible ? "Visible" : "Hidden")
                            .accessibilityIdentifier("settings.appearance.visibility.\(section.rawValue)")
                        }
                    }
                }
                .onMove { source, destination in
                    var order = controls.current.orderedTitleSections
                    order.move(fromOffsets: source, toOffset: destination)
                    controls.choice(\.titleSectionOrder).wrappedValue = order
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private func visibilityKeyPath(for section: AppearancePreferences.TitleSection) -> WritableKeyPath<AppearancePreferences, Bool>? {
        switch section {
        case .reviews: \.showsReviews
        case .cast: \.showsCast
        case .information: \.showsInformation
        case .franchise: \.showsFranchise
        case .related: \.showsRelated
        case .watchAnywhere: \.showsWatchAnywhere
        case .episodes: nil
        }
    }
}

struct AppearanceMotionPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Motion & Navigation", section: .motion) { controls in
            SettingsSection("Motion") {
                controls.menu("Animation speed", \.animationSpeed, id: "animationSpeed")
                controls.toggle("Zoom transitions", \.zoomTransitions, id: "zoom")
            }
            SettingsSection("Navigation") {
                controls.menu("Open on", \.startTab, id: "startTab")
                if isPhone {
                    controls.toggle("Tab labels", \.phoneTabTitles, id: "tabLabels")
                    controls.toggle("Shrink tab bar on scroll", \.minimisesTabBar, id: "shrinkTabBar")
                    controls.toggle("Continue Watching bar", \.showsContinueBar, id: "continueBar")
                }
            }
        }
    }
}

#if targetEnvironment(macCatalyst)
struct AppearanceHoverPage: View {
    private typealias Hover = AppearancePreferences.Hover

    var body: some View {
        AppearanceSectionPage(title: "Hover", section: .hover) { controls in
            Section {
                controls.toggle("Hover feedback", \.hover.isEnabled, id: "hover.enabled")
            }
            if controls.current.hover.isEnabled {
                Section { controls.preview([.posters, .playRow, .filters], lightsOnePiece: true) }
                SettingsSection("Buttons") {
                    controls.slider("Brightness", \.hover.brightness, in: Hover.brightnessRange, step: 0.01,
                                    low: "sun.min", high: "sun.max", id: "hover.brightness")
                    controls.slider("Grow", \.hover.grow, in: Hover.growRange, step: 0.005,
                                    low: "circle", high: "circle", id: "hover.grow")
                    controls.toggle("System highlight", \.hover.systemHighlight, id: "hover.systemHighlight")
                }
                SettingsSection("Glass") {
                    controls.slider("Glass fill", \.hover.glassFill, in: Hover.fillRange, step: 0.01,
                                    low: "capsule", high: "capsule.fill", id: "hover.glassFill")
                    controls.toggle("Rim", \.hover.showsRim, id: "hover.rim")
                    if controls.current.hover.showsRim {
                        controls.slider("Rim strength", \.hover.rimStrength, in: Hover.rimRange, step: 0.05,
                                        low: "circle.dashed", high: "circle", id: "hover.rimStrength")
                    }
                }
                SettingsSection("Cards") {
                    controls.slider("Card lift", \.hover.cardLift, in: Hover.cardLiftRange, step: 0.005,
                                    low: "rectangle.portrait", high: "rectangle.portrait", id: "hover.cardLift")
                    controls.toggle("Card shadow", \.hover.cardShadow, id: "hover.cardShadow")
                    controls.toggle("Pointer glow", \.hover.showsGlow, id: "hover.glow")
                    if controls.current.hover.showsGlow {
                        controls.slider("Glow strength", \.hover.glowStrength, in: Hover.glowRange, step: 0.01,
                                        low: "light.min", high: "light.max", id: "hover.glowStrength")
                    }
                }
                SettingsSection("Motion") {
                    controls.segmented("Speed", \.hover.speed, id: "hover.speed")
                }
            }
        }
    }
}
#endif
#endif
