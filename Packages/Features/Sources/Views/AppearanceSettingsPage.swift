#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The choices Appearance lays out as a menu or a segmented control: every case, by its label.
protocol AppearanceOption: CaseIterable, Identifiable, Hashable where AllCases: RandomAccessCollection {
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
var isPhone: Bool {
    #if targetEnvironment(macCatalyst)
    return false
    #else
    return UIDevice.current.userInterfaceIdiom == .phone
    #endif
}

func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

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
    @State private var defaultExportFailed = false
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
        appearance = pasted.keepingPosterArtwork(of: appearance)
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
                .settingsHover()
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
                SettingsSubpageLink(id: "appearance.Cards") { AppearanceCardsPage() } label: {
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
            SettingsSection("My Looks") {
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
                    .settingsLinkHover()
                    .accessibilityIdentifier("settings.appearance.paste")
            }
            Section {
                Button("Reset Appearance", role: .destructive) { confirmsReset = true }
                    .disabled(appearance.isDefault)
                    .accessibilityIdentifier("settings.appearance.reset")
            }
            // TEMP: remove once the exported look is baked into AppearancePreferences defaults.
            SettingsSection("Dev") {
                Button("Export Look for Default") {
                    exportLookForDefault()
                }
                .accessibilityIdentifier("settings.appearance.exportDefault")
                if let url = defaultExportURL {
                    ShareLink(item: url, preview: SharePreview("blusion-appearance-default.json")) {
                        Text("Share Export File")
                    }
                    .settingsLinkHover()
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
        .alert(defaultExportFailed ? "Export Failed" : "Exported", isPresented: $showsDefaultExport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(defaultExportMessage)
        }
    }

    /// Writes the active appearance and haptic settings to the clipboard and export file.
    private func exportLookForDefault() {
        Haptics.play(.buttons)
        let text: String
        do {
            text = try AppearanceDefaultExport.makeJSON(appearance: appearance, haptics: Haptics.configuration)
        } catch {
            defaultExportURL = nil
            defaultExportFailed = true
            defaultExportMessage = error.localizedDescription
            showsDefaultExport = true
            return
        }
        defaultExportFailed = false
        UIPasteboard.general.string = text

        let fileName = "blusion-appearance-default.json"
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        defaultExportURL = (try? text.write(to: temp, atomically: true, encoding: .utf8)) != nil ? temp : nil

        var places = ["Copied to clipboard"]
        #if targetEnvironment(macCatalyst)
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            let desktopURL = desktop.appendingPathComponent(fileName)
            if (try? text.write(to: desktopURL, atomically: true, encoding: .utf8)) != nil {
                places.append("Desktop/\(fileName)")
            }
        }
        let repoURL = URL(fileURLWithPath: "/Users/neiland/Blusion/docs/\(fileName)")
        if (try? text.write(to: repoURL, atomically: true, encoding: .utf8)) != nil {
            places.append("docs/\(fileName)")
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
        let isOn = look.appearance.keepingPosterArtwork(of: appearance) == appearance
        return Button {
            guard !isOn else { return }
            Haptics.play(.choices)
            appearance = look.appearance.keepingPosterArtwork(of: appearance)
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
struct AppearanceSectionPage<Content: View>: View {
    let title: String
    let section: AppearancePreferences.Section
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
                }
                .disabled(appearance.isDefault(section))
                .accessibilityIdentifier("settings.appearance.\(section.rawValue).restore")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .settingsPage(title)
    }
}
#endif
