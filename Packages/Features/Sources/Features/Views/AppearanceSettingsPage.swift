#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The choices Appearance lays out as a menu or a segmented control: every case, by its label.
private protocol AppearanceOption: CaseIterable, Identifiable, Hashable where AllCases: RandomAccessCollection {
    var label: String { get }
}

extension AppearancePreferences.Background: AppearanceOption {}
extension AppearancePreferences.TextSize: AppearanceOption {}
extension AppearancePreferences.FontStyle: AppearanceOption {}
extension AppearancePreferences.FontWidth: AppearanceOption {}
extension AppearancePreferences.LetterSpacing: AppearanceOption {}
extension AppearancePreferences.LineSpacing: AppearanceOption {}
extension AppearancePreferences.HeadingWeight: AppearanceOption {}
extension AppearancePreferences.HeadingSize: AppearanceOption {}
extension AppearancePreferences.Outline: AppearanceOption {}
extension AppearancePreferences.ArtworkTone: AppearanceOption {}
extension AppearancePreferences.ProgressColour: AppearanceOption {}
extension AppearancePreferences.ProgressThickness: AppearanceOption {}
extension AppearancePreferences.SectionOrder: AppearanceOption {}
extension AppearancePreferences.StartTab: AppearanceOption {}
extension AppearancePreferences.AnimationSpeed: AppearanceOption {}
extension AppearancePreferences.HoverSpeed: AppearanceOption {}
extension AppearancePreferences.PlayStyle: AppearanceOption {}
extension AppearancePreferences.ButtonFinish: AppearanceOption {}
extension AppearancePreferences.HeadingColour: AppearanceOption {}

/// The choices only a phone has: a phone has separate portrait and landscape title column counts (a wide window fits as many as the card size
/// allows), and only the iPhone has a tab bar with labels to show, a bar that shrinks and the Continue Watching bar above it.
@MainActor
private var isPhone: Bool {
    #if targetEnvironment(macCatalyst)
    return false
    #else
    return UIDevice.current.userInterfaceIdiom == .phone
    #endif
}

private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

/// Settings → Appearance, on iPhone and Mac: the presets, one row per part of the look that opens its page and reads what it is set to,
/// the listener's own saved looks (with Copy and Paste, to move a look to another device), and Reset. Every choice is saved as it is made
/// and the whole app follows at once (see `AppearancePreferences`).
struct AppearanceSettingsPage: View {
    let model: SettingsViewModel
    @AppStorage(AppearancePreferences.defaultsKey) private var appearance = AppearancePreferences()
    @AppStorage(AppearanceLooks.defaultsKey) private var looks = AppearanceLooks()
    @State private var confirmsReset = false
    @State private var namesLook = false
    @State private var lookName = ""
    /// Temp Dev export: confirmation after writing the current look for baking into code defaults.
    @State private var showsDefaultExport = false
    @State private var defaultExportMessage = ""
    @State private var defaultExportURL: URL?

    /// The preset the look is now, or nil for a look of the listener's own. Choosing one applies it.
    private var preset: Binding<AppearancePreferences.Preset?> {
        Binding(get: { appearance.preset }, set: { chosen in
            guard let chosen, chosen != appearance.preset else { return }
            Haptics.play(.choices)
            appearance = chosen.applied(to: appearance)
        })
    }

    /// Takes a look copied from this page, on this device or another. Anything else on the clipboard is left alone.
    private func paste(_ strings: [String]) {
        guard let pasted = strings.lazy.compactMap({ AppearancePreferences(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) })
            .first else { return }
        Haptics.play(.buttons)
        appearance = pasted
    }

    var body: some View {
        SettingsList {
            Section {
                Picker("Preset", selection: preset) {
                    if appearance.preset == nil {
                        Label { Text("Custom") } icon: { appearance.lookSwatch }
                            .tag(AppearancePreferences.Preset?.none)
                    }
                    ForEach(AppearancePreferences.Preset.allCases) { preset in
                        Label { Text(preset.label) } icon: { preset.applied(to: appearance).lookSwatch }
                            .tag(Optional(preset))
                    }
                }
                .buttonCursor()
                .accessibilityIdentifier("settings.appearance.preset")
            }
            Section {
                SettingsSubpageLink(id: "appearance.Colour") { AppearanceColourPage() } label: {
                    SettingsRow(title: "Colour", summary: appearance.colourSummary, systemImage: "paintpalette")
                }
                .accessibilityIdentifier("settings.appearance.colour")
                SettingsSubpageLink(id: "appearance.Text") { AppearanceTextPage() } label: {
                    SettingsRow(title: "Text", summary: appearance.textSummary, systemImage: "textformat")
                }
                .accessibilityIdentifier("settings.appearance.text")
                SettingsSubpageLink(id: "appearance.Cards") { AppearanceCardsPage(model: model) } label: {
                    SettingsRow(title: "Cards", summary: appearance.cardsSummary, systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
                .accessibilityIdentifier("settings.appearance.cards")
                SettingsSubpageLink(id: "appearance.Corners") { AppearanceCornersPage() } label: {
                    SettingsRow(title: "Corners", summary: cornersSummary, systemImage: "square.on.circle")
                }
                .accessibilityIdentifier("settings.appearance.corners")
                SettingsSubpageLink(id: "appearance.Home") { AppearanceHomePage() } label: {
                    SettingsRow(title: "Home", summary: appearance.homeSummary, systemImage: "play.house")
                }
                .accessibilityIdentifier("settings.appearance.home")
                SettingsSubpageLink(id: "appearance.TitlePages") { AppearanceTitlePagesPage() } label: {
                    SettingsRow(title: "Title Pages", summary: appearance.titlePagesSummary, systemImage: "film")
                }
                .accessibilityIdentifier("settings.appearance.titlePages")
                SettingsSubpageLink(id: "appearance.Motion") { AppearanceMotionPage() } label: {
                    SettingsRow(title: "Motion & Navigation", summary: appearance.motionSummary, systemImage: "wind")
                }
                .accessibilityIdentifier("settings.appearance.motion")
                #if targetEnvironment(macCatalyst)
                SettingsSubpageLink(id: "appearance.Hover") { AppearanceHoverPage() } label: {
                    SettingsRow(title: "Hover", summary: appearance.hoverSummary, systemImage: "cursorarrow.rays")
                }
                .accessibilityIdentifier("settings.appearance.hover")
                #endif
            }
            Section("My Looks") {
                ForEach(looks.looks) { look in lookRow(look) }
                Button("Save Current Look…") {
                    lookName = ""
                    namesLook = true
                }
                .accessibilityIdentifier("settings.appearance.saveLook")
                Button("Copy Appearance") {
                    Haptics.play(.buttons)
                    UIPasteboard.general.string = appearance.rawValue
                }
                .accessibilityIdentifier("settings.appearance.copy")
                PasteButton(payloadType: String.self) { strings in paste(strings) }
                    .accessibilityIdentifier("settings.appearance.paste")
            }
            Section {
                Button("Reset Appearance", role: .destructive) { confirmsReset = true }
                    .disabled(appearance.isDefault && model.isPosterArtworkDefault)
                    .accessibilityIdentifier("settings.appearance.reset")
            }
            // TEMP: remove once the exported look is baked into AppearancePreferences defaults.
            Section("Dev") {
                Button("Export Look for Default") {
                    exportLookForDefault()
                }
                .accessibilityIdentifier("settings.appearance.exportDefault")
                if let url = defaultExportURL {
                    ShareLink(item: url, preview: SharePreview("blusion-appearance-default.json")) {
                        Text("Share Export File")
                    }
                    .accessibilityIdentifier("settings.appearance.shareDefaultExport")
                }
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Appearance")
        .confirmationDialog("Reset Appearance?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Appearance", role: .destructive) {
                Haptics.play(.buttons)
                appearance = AppearancePreferences()
                Task { await model.restorePosterArtworkDefaults() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save Look", isPresented: $namesLook) {
            TextField("Name", text: $lookName)
            Button("Save") {
                Haptics.play(.buttons)
                looks.save(appearance, as: lookName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Exported", isPresented: $showsDefaultExport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(defaultExportMessage)
        }
    }

    /// Writes the current Appearance + Cards poster-artwork settings as pretty JSON (clipboard, temp file, Desktop on Mac).
    private func exportLookForDefault() {
        Haptics.play(.buttons)
        let text = AppearanceDefaultExport.makeJSON(appearance: appearance, settings: model.settings)
        UIPasteboard.general.string = text

        let fileName = "blusion-appearance-default.json"
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? text.write(to: temp, atomically: true, encoding: .utf8)
        defaultExportURL = temp

        var places = ["Copied to clipboard"]
        #if targetEnvironment(macCatalyst)
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            let desktopURL = desktop.appendingPathComponent(fileName)
            if (try? text.write(to: desktopURL, atomically: true, encoding: .utf8)) != nil {
                places.append("Desktop/\(fileName)")
            }
        }
        #endif
        defaultExportMessage = places.joined(separator: " · ")
        showsDefaultExport = true
    }

    /// The corners' scale, and how many elements have one of their own.
    private var cornersSummary: String {
        let own = appearance.cornerOverrides.count
        return percent(appearance.cornerScale) + (own > 0 ? " · \(own) custom" : "")
    }

    /// A saved look: a tap puts it on, a tick shows it is on, and a swipe or the context menu deletes it or saves the current look over it.
    private func lookRow(_ look: AppearanceLook) -> some View {
        let isOn = look.appearance == appearance
        return Button {
            guard !isOn else { return }
            Haptics.play(.choices)
            appearance = look.appearance
        } label: {
            HStack {
                Label { Text(look.name).foregroundStyle(.primary) } icon: { look.appearance.lookSwatch }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .swipeActions {
            Button("Delete", role: .destructive) { delete(look) }
        }
        .contextMenu {
            Button("Save Current Look Here", systemImage: "square.and.arrow.down") {
                Haptics.play(.buttons)
                looks.save(appearance, as: look.name)
            }
            .disabled(isOn)
            Button("Delete", systemImage: "trash", role: .destructive) { delete(look) }
        }
    }

    private func delete(_ look: AppearanceLook) {
        Haptics.play(.buttons)
        looks.looks.removeAll { $0.id == look.id }
    }
}

// MARK: - A part of Appearance

/// One part of Appearance on a page of its own: the part's choices, with a preview (`AppearanceControls.preview`) where the page wants
/// one, then Restore Defaults for this part alone.
private struct AppearanceSectionPage<Content: View>: View {
    let title: String
    let section: AppearancePreferences.Section
    var extraIsDefault = true
    var onRestore: (() -> Void)?
    @ViewBuilder let content: (AppearanceControls) -> Content
    @AppStorage(AppearancePreferences.defaultsKey) private var appearance = AppearancePreferences()
    /// A slider's value while it is dragged, shown in the page's preview and saved when the drag ends, so the whole app is not laid out
    /// again on every step of a drag.
    @State private var draft: AppearancePreferences?
    @State private var isSliding = false

    var body: some View {
        let controls = AppearanceControls(appearance: $appearance, draft: $draft, isSliding: $isSliding)
        SettingsList {
            content(controls)
            Section {
                Button("Restore Defaults") {
                    Haptics.play(.buttons)
                    appearance = appearance.restoringDefaults(of: section)
                    onRestore?()
                }
                .disabled(appearance.isDefault(section) && extraIsDefault)
                .accessibilityIdentifier("settings.appearance.\(section.rawValue).restore")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .settingsPage(title)
    }
}

/// The controls every part of Appearance builds its choices from. Pickers and switches save at once and tick (Pickers & switches);
/// sliders show their value as they move and save, with the Sliders tick, when they are let go.
@MainActor
private struct AppearanceControls {
    let appearance: Binding<AppearancePreferences>
    let draft: Binding<AppearancePreferences?>
    let isSliding: Binding<Bool>

    /// The look shown: a slider's value while it is dragged, otherwise what is saved.
    var current: AppearancePreferences { draft.wrappedValue ?? appearance.wrappedValue }

    /// The look being set, drawn on the app's own `samples`, as a row of the page.
    func preview(_ samples: [AppearanceSample], lightsOnePiece: Bool = false) -> some View {
        AppearancePreview(appearance: current, samples: samples, lightsOnePiece: lightsOnePiece)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    func choice<Value: Equatable>(_ keyPath: WritableKeyPath<AppearancePreferences, Value>) -> Binding<Value> {
        let appearance = appearance
        return Binding(get: { appearance.wrappedValue[keyPath: keyPath] }, set: { value in
            guard value != appearance.wrappedValue[keyPath: keyPath] else { return }
            Haptics.play(.choices)
            appearance.wrappedValue[keyPath: keyPath] = value
        })
    }

    func colour(_ keyPath: WritableKeyPath<AppearancePreferences, AppearancePreferences.RGB>) -> Binding<Color> {
        let appearance = appearance
        return Binding(get: { appearance.wrappedValue[keyPath: keyPath].colour }, set: { colour in
            appearance.wrappedValue[keyPath: keyPath] = AppearancePreferences.RGB(colour)
        })
    }

    func toggle(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Bool>, id: String) -> some View {
        Toggle(title, isOn: choice(keyPath))
            .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A menu of every case.
    func menu<Option: AppearanceOption>(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Option>,
                                        id: String) -> some View {
        Picker(title, selection: choice(keyPath)) {
            ForEach(Option.allCases) { option in Text(option.label).tag(option) }
        }
        .buttonCursor()
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A titled segmented control over every case.
    func segmented<Option: AppearanceOption>(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Option>,
                                             id: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
            CornerSegmentedPicker(title, options: Array(Option.allCases), selection: choice(keyPath)) {
                $0.label
            }
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A titled segmented control over numbers.
    func numbers(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Int>, in values: ClosedRange<Int>,
                 id: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
            CornerSegmentedPicker(title, options: Array(values), selection: choice(keyPath)) {
                String($0)
            }
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A titled slider with its value as a percentage beside the title and a small and a large symbol at its ends. A drag shows in the
    /// preview as it goes and is saved when it ends; VoiceOver's and the keyboard's steps, which come without a drag, are saved at once.
    func slider(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Double>, in range: ClosedRange<Double>,
                step: Double, low: String, high: String, id: String) -> some View {
        slider(title, read: { $0[keyPath: keyPath] }, write: { $0[keyPath: keyPath] = $1 },
               in: range, step: step, low: low, high: high, id: id)
    }

    func columnSlider(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Int>, id: String) -> some View {
        let appearance = appearance
        let value = Binding<Double>(get: { Double(appearance.wrappedValue[keyPath: keyPath]) }, set: { newValue in
            let columns = Int(newValue.rounded())
            guard columns != appearance.wrappedValue[keyPath: keyPath] else { return }
            Haptics.play(.sliders)
            appearance.wrappedValue[keyPath: keyPath] = columns
        })
        let range = AppearancePreferences.phoneGridColumnRange
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(title)
                Spacer()
                Text("\(current[keyPath: keyPath])").monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            CornerSlider(value: value, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .accessibilityLabel(title)
                .accessibilityValue("\(current[keyPath: keyPath])")
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    func slider(_ title: String, read: @escaping (AppearancePreferences) -> Double,
                write: @escaping (inout AppearancePreferences, Double) -> Void, in range: ClosedRange<Double>,
                step: Double, low: String, high: String, id: String) -> some View {
        let appearance = appearance
        let draft = draft
        let isSliding = isSliding
        let value = Binding<Double>(get: { read(draft.wrappedValue ?? appearance.wrappedValue) }, set: { newValue in
            if isSliding.wrappedValue {
                var look = draft.wrappedValue ?? appearance.wrappedValue
                write(&look, newValue)
                draft.wrappedValue = look
            } else if newValue != read(appearance.wrappedValue) {
                Haptics.play(.sliders)
                var look = appearance.wrappedValue
                write(&look, newValue)
                appearance.wrappedValue = look
            }
        })
        let shown = percent(read(current))
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(title)
                Spacer()
                Text(shown)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            HStack {
                Image(systemName: low).imageScale(.small).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                CornerSlider(value: value, in: range, step: step) { editing in
                    isSliding.wrappedValue = editing
                    guard !editing, let look = draft.wrappedValue else { return }
                    draft.wrappedValue = nil
                    if look != appearance.wrappedValue {
                        Haptics.play(.sliders)
                        appearance.wrappedValue = look
                    }
                }
                .accessibilityLabel(title)
                .accessibilityValue(shown)
                Image(systemName: high).imageScale(.large).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    func textMenu<Option: AppearanceOption>(_ title: String, _ role: AppearancePreferences.TextRole,
                                            _ value: WritableKeyPath<AppearancePreferences.TextStyle, Option>,
                                            follow: WritableKeyPath<AppearancePreferences.TextStyle, Bool>? = nil,
                                            id: String) -> some View {
        Picker(title, selection: textChoice(role, value, follow: follow)) {
            if role != .reading, follow != nil {
                Text("Same as body text").tag(Optional<Option>.none)
            }
            ForEach(Option.allCases) { option in Text(option.label).tag(Optional(option)) }
        }
        .buttonCursor()
        .accessibilityIdentifier(textID(role, id))
    }

    func textSlant(_ role: AppearancePreferences.TextRole) -> some View {
        Picker("Italic", selection: textChoice(role, \.italic, follow: \.followsItalic)) {
            Text("Same as body text").tag(Optional<Bool>.none)
            Text("Off").tag(Optional(false))
            Text("On").tag(Optional(true))
        }
        .buttonCursor()
        .accessibilityIdentifier(textID(role, "italic"))
    }

    func textToggle(_ title: String, _ role: AppearancePreferences.TextRole,
                    _ value: WritableKeyPath<AppearancePreferences.TextStyle, Bool>, id: String) -> some View {
        let choice = textChoice(role, value, follow: nil)
        return Toggle(title, isOn: Binding(get: { choice.wrappedValue ?? false }, set: { choice.wrappedValue = $0 }))
            .accessibilityIdentifier(textID(role, id))
    }

    private func textID(_ role: AppearancePreferences.TextRole, _ id: String) -> String {
        "settings.appearance.text.\(role.rawValue).\(id)"
    }

    /// A nil selection links this one attribute back to body text.
    private func textChoice<Value: Equatable>(_ role: AppearancePreferences.TextRole,
                                              _ value: WritableKeyPath<AppearancePreferences.TextStyle, Value>,
                                              follow: WritableKeyPath<AppearancePreferences.TextStyle, Bool>?) -> Binding<Value?> {
        let appearance = appearance
        return Binding(get: {
            let stored = appearance.wrappedValue.storedText(for: role)
            if role != .reading, let follow, stored[keyPath: follow] { return nil }
            return stored[keyPath: value]
        }, set: { newValue in
            var look = appearance.wrappedValue
            var stored = look.storedText(for: role)
            if let newValue {
                stored[keyPath: value] = newValue
            } else {
                let defaults: AppearancePreferences.TextStyle = role == .display ? .headings() : .followingReading()
                stored[keyPath: value] = defaults[keyPath: value]
            }
            if role != .reading, let follow { stored[keyPath: follow] = newValue == nil }
            guard stored != look.storedText(for: role) else { return }
            Haptics.play(.choices)
            look.setStoredText(stored, for: role)
            appearance.wrappedValue = look
        })
    }
}

// MARK: - The parts

private struct AppearanceColourPage: View {
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
                .buttonCursor()
                .accessibilityIdentifier("settings.appearance.accent")
                if controls.current.accent == .custom {
                    ColorPicker("Custom accent", selection: controls.colour(\.customAccent), supportsOpacity: false)
                        .buttonCursor()
                        .accessibilityIdentifier("settings.appearance.customAccent")
                }
                Picker("Background", selection: controls.choice(\.background)) {
                    ForEach(AppearancePreferences.Background.allCases) { background in
                        Label { Text(background.label) } icon: { controls.current.backgroundSwatch(background).swatch }
                            .tag(background)
                    }
                }
                .buttonCursor()
                .accessibilityIdentifier("settings.appearance.background")
                if controls.current.background == .custom {
                    ColorPicker("Custom background", selection: controls.colour(\.customBackground), supportsOpacity: false)
                        .buttonCursor()
                        .accessibilityIdentifier("settings.appearance.customBackground")
                }
                if controls.current.background == .tinted {
                    controls.slider("Tint strength", \.tintStrength, in: AppearancePreferences.tintStrengthRange, step: 0.01,
                                    low: "circle.lefthalf.filled", high: "circle.fill", id: "tintStrength")
                }
            }
            Section("Buttons") {
                controls.segmented("Play button", \.playStyle, id: "playStyle")
                controls.segmented("Finish", \.buttonFinish, id: "buttonFinish")
            }
        }
    }
}

private struct AppearanceTextPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Text", section: .text) { controls in
            Section {
                controls.menu("App text size", \.textSize, id: "text.reading.textSize")
            }
            Section {
                ForEach(AppearancePreferences.TextRole.allCases) { role in
                    DisclosureGroup {
                        controls.preview([sample(for: role)])
                        TextRoleOptions(role: role, controls: controls)
                    } label: {
                        LabeledContent(role.label, value: controls.current.textRoleSummary(role))
                            .buttonCursor()
                    }
                    .accessibilityIdentifier("settings.appearance.text.\(role.rawValue)")
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

private struct AppearanceCardsPage: View {
    let model: SettingsViewModel

    var body: some View {
        AppearanceSectionPage(
            title: "Cards",
            section: .cards,
            extraIsDefault: model.isPosterArtworkDefault,
            onRestore: { Task { await model.restorePosterArtworkDefaults() } }
        ) { controls in
            Section { controls.preview([.continueWatching, .posters]) }
            Section("Size & Shape") {
                controls.slider("Card size", \.cardScale, in: AppearancePreferences.cardScaleRange, step: 0.05,
                                low: "rectangle.portrait", high: "rectangle.portrait", id: "cardSize")
                controls.slider("Spacing", \.spacingScale, in: AppearancePreferences.spacingScaleRange, step: 0.05,
                                low: "arrow.down.right.and.arrow.up.left", high: "arrow.up.left.and.arrow.down.right", id: "spacing")
                if isPhone {
                    controls.columnSlider("Portrait columns", \.phoneGridColumns, id: "columns")
                    controls.columnSlider("Landscape columns", \.phoneLandscapeGridColumns, id: "landscapeColumns")
                }
            }
            Section("Shelves") {
                controls.slider("Shelf spacing", read: { $0.effectiveShelfSpacingScale }, write: { $0.shelfSpacingScale = $1 },
                                in: AppearancePreferences.shelfSpacingScaleRange, step: 0.05,
                                low: "arrow.down.right.and.arrow.up.left", high: "arrow.up.left.and.arrow.down.right", id: "shelfSpacing")
                controls.slider("Side margin", \.sideMarginScale, in: AppearancePreferences.sideMarginScaleRange, step: 0.05,
                                low: "arrow.right.to.line", high: "arrow.left.and.right", id: "sideMargin")
                controls.toggle("Lines between shelves", \.showsShelfDividers, id: "shelfDividers")
                if controls.current.showsShelfDividers {
                    controls.slider("Line thickness", \.shelfDividerThickness, in: AppearancePreferences.shelfDividerThicknessRange,
                                    step: 0.5, low: "minus", high: "minus", id: "dividerThickness")
                    controls.slider("Line strength", \.shelfDividerOpacity, in: AppearancePreferences.shelfDividerOpacityRange,
                                    step: 0.01, low: "circle.lefthalf.filled", high: "circle.fill", id: "dividerStrength")
                    controls.toggle("Line edge to edge", \.shelfDividerFullWidth, id: "dividerFullWidth")
                }
            }
            Section("Captions") {
                controls.toggle("Titles under posters", \.showsPosterTitles, id: "posterTitles")
                controls.numbers("Title lines", \.captionLines, in: AppearancePreferences.captionLineRange, id: "titleLines")
                controls.toggle("Titles in capitals", \.uppercaseCaptions, id: "captionCaps")
                controls.toggle("Genre and year", \.showsCaptionDetails, id: "captionDetails")
            }
            Section("Artwork") {
                controls.menu("Tone", \.artworkTone, id: "tone")
                controls.segmented("Outline", \.outline, id: "outline")
                controls.toggle("Outline buttons", \.outlinesButtons, id: "buttonOutline")
                Toggle("Hero artwork on posters", isOn: Binding(get: { model.settings.usesHeroPosters }, set: { value in
                    Haptics.play(.choices)
                    Task { await model.setUsesHeroPosters(value) }
                }))
                .accessibilityIdentifier("settings.heroPosters")
                Toggle("Ratings on posters", isOn: Binding(get: { model.settings.showsPosterRatings }, set: { value in
                    Haptics.play(.choices)
                    Task { await model.setShowsPosterRatings(value) }
                }))
                .accessibilityIdentifier("settings.posterRatings")
                Toggle("Disc and streamer marks", isOn: Binding(get: { model.settings.showsBestDiscOnPosters }, set: { value in
                    Haptics.play(.choices)
                    Task { await model.setShowsBestDiscOnPosters(value) }
                }))
                .accessibilityIdentifier("settings.bestDiscOnPosters")
                if model.settings.showsBestDiscOnPosters {
                    Picker("Mark position", selection: Binding(get: { model.settings.posterMarkPlacement }, set: { value in
                        Haptics.play(.choices)
                        Task { await model.setPosterMarkPlacement(value) }
                    })) {
                        ForEach(PosterMarkPlacement.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .buttonCursor()
                    .accessibilityIdentifier("settings.posterBrandLocation")
                }
                Toggle("Coloured rating logos", isOn: Binding(get: { model.settings.showsColouredRatingLogos }, set: { value in
                    Haptics.play(.choices)
                    Task { await model.setShowsColouredRatingLogos(value) }
                }))
                .accessibilityIdentifier("settings.colouredRatingLogos")
            }
            Section("Progress") {
                controls.segmented("Colour", \.progressColour, id: "progressColour")
                controls.segmented("Thickness", \.progressThickness, id: "progressThickness")
                controls.toggle("Time left", \.showsTimeLeft, id: "timeLeft")
            }
        }
    }
}

private struct AppearanceCornersPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Corners", section: .corners) { controls in
            Section { controls.preview([.playRow, .posters]) }
            Section("All Corners") {
                controls.slider("Roundness", \.cornerScale, in: AppearancePreferences.cornerScaleRange, step: 0.1,
                                low: "square", high: "circle", id: "corners")
                controls.toggle("Reshape round buttons", \.includesCircularButtons, id: "circularCorners")
            }
            Section("Each Part") {
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
                            .buttonCursor()
                    }
                }
            }
        }
    }
}

private struct AppearanceHomePage: View {
    var body: some View {
        AppearanceSectionPage(title: "Home", section: .home) { controls in
            Section {
                Picker("Turn showcase pages", selection: controls.choice(\.heroAutoAdvance)) {
                    ForEach(AppearancePreferences.heroAutoAdvanceOptions, id: \.self) { seconds in
                        Text(seconds == 0 ? "Never" : "Every \(seconds) seconds").tag(seconds)
                    }
                }
                .buttonCursor()
                .accessibilityIdentifier("settings.appearance.turnPages")
                Stepper("Continue Watching: \(controls.current.continueWatchingLimit)",
                        value: controls.choice(\.continueWatchingLimit), in: 1...100)
                    .buttonCursor()
                    .accessibilityIdentifier("settings.appearance.continueWatchingLimit")
            }
        }
    }
}

private struct AppearanceTitlePagesPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Title Pages", section: .titlePages) { controls in
            Section("Spoilers") {
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
                controls.toggle("Blurred background", \.blursBackground, id: "blurredBackground")
                if isPhone {
                    controls.toggle("Tab bar on title pages", \.showsTitlePageTabBar, id: "titlePageTabBar")
                }
            }
            Section("Section order") {
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
                            .buttonStyle(.hoverPlain)
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

private struct AppearanceMotionPage: View {
    var body: some View {
        AppearanceSectionPage(title: "Motion & Navigation", section: .motion) { controls in
            Section("Motion") {
                controls.menu("Animation speed", \.animationSpeed, id: "animationSpeed")
                controls.toggle("Zoom transitions", \.zoomTransitions, id: "zoom")
            }
            Section("Navigation") {
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
private struct AppearanceHoverPage: View {
    private typealias Hover = AppearancePreferences.Hover

    var body: some View {
        AppearanceSectionPage(title: "Hover", section: .hover) { controls in
            Section {
                controls.toggle("Hover feedback", \.hover.isEnabled, id: "hover.enabled")
            }
            if controls.current.hover.isEnabled {
                Section { controls.preview([.posters, .playRow, .filters], lightsOnePiece: true) }
                Section("Buttons") {
                    controls.slider("Brightness", \.hover.brightness, in: Hover.brightnessRange, step: 0.01,
                                    low: "sun.min", high: "sun.max", id: "hover.brightness")
                    controls.slider("Grow", \.hover.grow, in: Hover.growRange, step: 0.005,
                                    low: "circle", high: "circle", id: "hover.grow")
                    controls.toggle("System highlight", \.hover.systemHighlight, id: "hover.systemHighlight")
                }
                Section("Glass") {
                    controls.slider("Glass fill", \.hover.glassFill, in: Hover.fillRange, step: 0.01,
                                    low: "capsule", high: "capsule.fill", id: "hover.glassFill")
                    controls.toggle("Rim", \.hover.showsRim, id: "hover.rim")
                    if controls.current.hover.showsRim {
                        controls.slider("Rim strength", \.hover.rimStrength, in: Hover.rimRange, step: 0.05,
                                        low: "circle.dashed", high: "circle", id: "hover.rimStrength")
                    }
                }
                Section("Cards") {
                    controls.slider("Card lift", \.hover.cardLift, in: Hover.cardLiftRange, step: 0.005,
                                    low: "rectangle.portrait", high: "rectangle.portrait", id: "hover.cardLift")
                    controls.toggle("Card shadow", \.hover.cardShadow, id: "hover.cardShadow")
                    controls.toggle("Pointer glow", \.hover.showsGlow, id: "hover.glow")
                    if controls.current.hover.showsGlow {
                        controls.slider("Glow strength", \.hover.glowStrength, in: Hover.glowRange, step: 0.01,
                                        low: "light.min", high: "light.max", id: "hover.glowStrength")
                    }
                }
                Section("Motion") {
                    controls.segmented("Speed", \.hover.speed, id: "hover.speed")
                }
            }
        }
    }
}
#endif

// MARK: - Summaries

/// What each part of Appearance is set to, for its row on the Appearance page.
extension AppearancePreferences {
    var colourSummary: String {
        var parts = [accent.label, background.label]
        if playStyle != .artwork { parts.append("\(playStyle.label) Play") }
        if buttonFinish != .glass { parts.append("\(buttonFinish.label) buttons") }
        return parts.joined(separator: " · ")
    }

    var textSummary: String {
        var parts = [textSize == .system ? "System size" : textSize.label, font.label]
        if reading.weight != .regular { parts.append(reading.weight.label) }
        if font == .standard, fontWidth != .standard { parts.append(fontWidth.label) }
        if italicText { parts.append("Italic") }
        if reading.capitals { parts.append("Caps") }
        if !interface.followsReading { parts.append("Custom interface") }
        if headings != TextStyle.headings() { parts.append("Custom headings") }
        return parts.joined(separator: " · ")
    }

    /// What a kind of text is set to, on its row of the Text page.
    func textRoleSummary(_ role: TextRole) -> String {
        if role == .interface, interface.followsReading, reading.colour == .primary, !reading.capitals {
            return "Same as body text"
        }
        let style = resolvedText(for: role)
        var parts = [style.font.label]
        if role != .reading, !style.followsTextSize { parts.append(style.textSize.label) }
        if style.scale != .standard { parts.append(style.scale.label) }
        if style.weight != .regular { parts.append(style.weight.label) }
        if style.font == .standard, style.width != .standard { parts.append(style.width.label) }
        if style.letterSpacing != .standard { parts.append("\(style.letterSpacing.label) letters") }
        if style.lineSpacing != .standard { parts.append("\(style.lineSpacing.label) lines") }
        if style.italic { parts.append("Italic") }
        if style.capitals { parts.append("Caps") }
        if style.colour != .primary { parts.append(style.colour.label) }
        return parts.joined(separator: " · ")
    }

    var cardsSummary: String {
        "Size \(percent(cardScale)) · Spacing \(percent(spacingScale))"
    }

    var homeSummary: String {
        heroAutoAdvance > 0 ? "Showcase every \(heroAutoAdvance) s" : "Showcase stays put"
    }

    var titlePagesSummary: String {
        let sections = [showsReviews, showsCast, showsInformation, showsFranchise, showsRelated]
        let shown = sections.filter { $0 }.count + (showsWatchAnywhere ? 1 : 0)
        let total = sections.count + (showsWatchAnywhere ? 1 : 0)
        var parts = [shown == total ? "All sections" : "\(shown) of \(total) sections"]
        if !titleSectionOrder.isEmpty { parts.append("Custom order") }
        else if sectionOrder == .castFirst { parts.append("Cast first") }
        if hidesSpoilers { parts.append("No spoilers") }
        if blursBackground { parts.append("Blurred background") }
        if showsTitlePageTabBar { parts.append("Tab bar") }
        return parts.joined(separator: " · ")
    }

    var motionSummary: String {
        let speed = switch animationSpeed {
        case .standard: "Default speed"
        case .off: "No animation"
        default: "\(animationSpeed.label) animation"
        }
        return "Opens on \(startTab.label) · \(speed)"
    }

    var hoverSummary: String {
        guard hover.isEnabled else { return "Off" }
        var parts = [hover == Hover() ? "Default" : "Custom"]
        if hover.speed != .standard { parts.append(hover.speed.label) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Temp default-look export

/// Pretty JSON of the active look, one object per Appearance section (same fields as each page / Restore Defaults),
/// with Cards' poster-artwork toggles nested under `cards`. For baking into code defaults.
private enum AppearanceDefaultExport {
    struct Payload: Encodable {
        var version = 2
        /// Preset-driven layout (no Appearance page of its own).
        var layout: AppearancePreferences.Layout
        var colour: Colour
        var text: Text
        var cards: Cards
        var corners: Corners
        var home: Home
        var titlePages: TitlePages
        var motion: Motion
        var hover: AppearancePreferences.Hover
    }

    struct Colour: Encodable {
        var accent: AppearancePreferences.Accent
        var customAccent: AppearancePreferences.RGB
        var background: AppearancePreferences.Background
        var customBackground: AppearancePreferences.RGB
        var tintStrength: Double
        var playStyle: AppearancePreferences.PlayStyle
        var buttonFinish: AppearancePreferences.ButtonFinish
    }

    struct Text: Encodable {
        var reading: AppearancePreferences.TextStyle
        var interface: AppearancePreferences.TextStyle
        var headings: AppearancePreferences.TextStyle
    }

    struct Cards: Encodable {
        var cardScale: Double
        var spacingScale: Double
        var shelfSpacingScale: Double?
        var sideMarginScale: Double
        var showsShelfDividers: Bool
        var shelfDividerThickness: Double
        var shelfDividerOpacity: Double
        var shelfDividerFullWidth: Bool
        var phoneGridColumns: Int
        var phoneLandscapeGridColumns: Int
        var showsPosterTitles: Bool
        var captionLines: Int
        var showsCaptionDetails: Bool
        var uppercaseCaptions: Bool
        var outline: AppearancePreferences.Outline
        var outlinesButtons: Bool
        var artworkTone: AppearancePreferences.ArtworkTone
        var progressColour: AppearancePreferences.ProgressColour
        var progressThickness: AppearancePreferences.ProgressThickness
        var showsTimeLeft: Bool
        var posterArtwork: PosterArtwork
    }

    struct PosterArtwork: Encodable {
        var usesHeroPosters: Bool
        var showsPosterRatings: Bool
        var showsBestDiscOnPosters: Bool
        var posterMarkPlacement: PosterMarkPlacement
        var showsColouredRatingLogos: Bool
    }

    struct Corners: Encodable {
        var cornerScale: Double
        var cornerOverrides: [String: Double]
        var includesCircularButtons: Bool
    }

    struct Home: Encodable {
        var heroAutoAdvance: Int
        var showsPageDots: Bool
        var continueWatchingLimit: Int
    }

    struct TitlePages: Encodable {
        var hidesSpoilers: Bool
        var spoilerStills: Bool
        var spoilerSynopses: Bool
        var spoilerTitles: Bool
        var expandsSynopsis: Bool
        var blursBackground: Bool
        var showsReviews: Bool
        var showsCast: Bool
        var showsInformation: Bool
        var showsFranchise: Bool
        var showsRelated: Bool
        var showsWatchAnywhere: Bool
        var sectionOrder: AppearancePreferences.SectionOrder
        var titleSectionOrder: [AppearancePreferences.TitleSection]
        var showsTitlePageTabBar: Bool
    }

    struct Motion: Encodable {
        var startTab: AppearancePreferences.StartTab
        var zoomTransitions: Bool
        var animationSpeed: AppearancePreferences.AnimationSpeed
        var phoneTabTitles: Bool
        var minimisesTabBar: Bool
        var showsContinueBar: Bool
    }

    static func makeJSON(appearance: AppearancePreferences, settings: PlaybackSettings) -> String {
        let payload = Payload(
            layout: appearance.layout,
            colour: Colour(
                accent: appearance.accent,
                customAccent: appearance.customAccent,
                background: appearance.background,
                customBackground: appearance.customBackground,
                tintStrength: appearance.tintStrength,
                playStyle: appearance.playStyle,
                buttonFinish: appearance.buttonFinish
            ),
            text: Text(
                reading: appearance.reading,
                interface: appearance.interface,
                headings: appearance.headings
            ),
            cards: Cards(
                cardScale: appearance.cardScale,
                spacingScale: appearance.spacingScale,
                shelfSpacingScale: appearance.shelfSpacingScale,
                sideMarginScale: appearance.sideMarginScale,
                showsShelfDividers: appearance.showsShelfDividers,
                shelfDividerThickness: appearance.shelfDividerThickness,
                shelfDividerOpacity: appearance.shelfDividerOpacity,
                shelfDividerFullWidth: appearance.shelfDividerFullWidth,
                phoneGridColumns: appearance.phoneGridColumns,
                phoneLandscapeGridColumns: appearance.phoneLandscapeGridColumns,
                showsPosterTitles: appearance.showsPosterTitles,
                captionLines: appearance.captionLines,
                showsCaptionDetails: appearance.showsCaptionDetails,
                uppercaseCaptions: appearance.uppercaseCaptions,
                outline: appearance.outline,
                outlinesButtons: appearance.outlinesButtons,
                artworkTone: appearance.artworkTone,
                progressColour: appearance.progressColour,
                progressThickness: appearance.progressThickness,
                showsTimeLeft: appearance.showsTimeLeft,
                posterArtwork: PosterArtwork(
                    usesHeroPosters: settings.usesHeroPosters,
                    showsPosterRatings: settings.showsPosterRatings,
                    showsBestDiscOnPosters: settings.showsBestDiscOnPosters,
                    posterMarkPlacement: settings.posterMarkPlacement,
                    showsColouredRatingLogos: settings.showsColouredRatingLogos
                )
            ),
            corners: Corners(
                cornerScale: appearance.cornerScale,
                cornerOverrides: appearance.cornerOverrides,
                includesCircularButtons: appearance.includesCircularButtons
            ),
            home: Home(
                heroAutoAdvance: appearance.heroAutoAdvance,
                showsPageDots: appearance.showsPageDots,
                continueWatchingLimit: appearance.continueWatchingLimit
            ),
            titlePages: TitlePages(
                hidesSpoilers: appearance.hidesSpoilers,
                spoilerStills: appearance.spoilerStills,
                spoilerSynopses: appearance.spoilerSynopses,
                spoilerTitles: appearance.spoilerTitles,
                expandsSynopsis: appearance.expandsSynopsis,
                blursBackground: appearance.blursBackground,
                showsReviews: appearance.showsReviews,
                showsCast: appearance.showsCast,
                showsInformation: appearance.showsInformation,
                showsFranchise: appearance.showsFranchise,
                showsRelated: appearance.showsRelated,
                showsWatchAnywhere: appearance.showsWatchAnywhere,
                sectionOrder: appearance.sectionOrder,
                titleSectionOrder: appearance.titleSectionOrder,
                showsTitlePageTabBar: appearance.showsTitlePageTabBar
            ),
            motion: Motion(
                startTab: appearance.startTab,
                zoomTransitions: appearance.zoomTransitions,
                animationSpeed: appearance.animationSpeed,
                phoneTabTitles: appearance.phoneTabTitles,
                minimisesTabBar: appearance.minimisesTabBar,
                showsContinueBar: appearance.showsContinueBar
            ),
            hover: appearance.hover
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return appearance.rawValue
        }
        return text
    }
}
#endif
