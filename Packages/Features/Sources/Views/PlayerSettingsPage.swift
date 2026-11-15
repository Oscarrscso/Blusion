#if canImport(UIKit)
import PlayerKit
import StremioKit
import SwiftUI
import UIKit

/// Settings → Player: which player plays and, for the built-in one, its fallback engine, then its defaults for subtitles, audio, picture
/// and controls. Changes made in the player land here too.
struct PlayerSettingsPage: View {
    let model: SettingsViewModel
    var aetherEngineLinked = false
    enum Detail: String, CaseIterable { case subtitles = "Subtitles", picture = "Picture", controls = "Controls" }
    var detail: Detail? = nil
    @State private var infuseInstalled = true
    @Environment(\.scenePhase) private var scenePhase

    private var player: PlayerPreferences { model.settings.player }

    private func binding<Value>(_ keyPath: WritableKeyPath<PlayerPreferences, Value>) -> Binding<Value> {
        Binding(get: { model.settings.player[keyPath: keyPath] }, set: { value in
            Haptics.play(.choices)
            Task { await model.updatePlayer { $0[keyPath: keyPath] = value } }
        })
    }

    var body: some View {
        SettingsList {
            if let detail {
                switch detail {
                case .subtitles: subtitlesContent
                case .picture: pictureSection
                case .controls: controlsSection
                }
            } else {
                engineSection
                commonDefaults
                Section {
                    ForEach(Detail.allCases, id: \.self) { page in
                        SettingsSubpageLink(id: "player.\(page.rawValue)") {
                            PlayerSettingsPage(model: model, aetherEngineLinked: aetherEngineLinked, detail: page)
                        } label: {
                            LabeledContent(page.rawValue, value: detailSummary(page))
                        }
                        .accessibilityIdentifier("settings.player.\(page.rawValue.lowercased())")
                    }
                }
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage(detail?.rawValue ?? "Player")
        // Checked again on return to the app: Get Infuse leaves it for the App Store.
        .task(id: scenePhase) {
            guard detail == nil, scenePhase == .active, let url = URL(string: "infuse://") else { return }
            infuseInstalled = UIApplication.shared.canOpenURL(url)
        }
    }

    @ViewBuilder
    private var subtitlesContent: some View {
        SettingsSection("Subtitles") {
            Picker("Language", selection: Binding(get: { model.settings.subtitleLanguage }, set: { value in
                Haptics.play(.choices)
                Task { await model.setSubtitleLanguage(value) }
            })) {
                ForEach(SettingsViewModel.languageOptions) {
                    Text($0.value == nil && player.subtitleMode == .forcedOnly ? "Audio language" : $0.label).tag($0.value)
                }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.subtitleLanguage")
            .disabled(player.subtitleMode == .off)
            Picker("Show", selection: binding(\.subtitleMode)) {
                ForEach(SubtitleMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.subtitleMode")
            Toggle("Prefer SDH", isOn: binding(\.prefersSDH))
                .accessibilityIdentifier("settings.player.sdh")
            SettingsSubpageLink(id: "player.openSubtitles") { OpenSubtitlesSettingsPage(model: model) } label: {
                LabeledContent("OpenSubtitles", value: model.openSubtitlesSummary)
            }
            .accessibilityIdentifier("settings.player.openSubtitles")
        }

        SettingsSection("Subtitle Style") {
            LabeledContent("Size") {
                CornerSlider(value: Binding(get: { player.subtitleStyle.scale }, set: { value in
                    Task { await model.updatePlayer { $0.subtitleStyle.scale = value } }
                }), in: SubtitleStyle.scaleRange, step: 0.1, onEditingChanged: { editing in
                    if !editing { Haptics.play(.sliders) }
                })
                    .frame(maxWidth: 220)
                    .accessibilityValue("\(Int(player.subtitleStyle.scale * 100)) percent")
            }
            Picker("Colour", selection: binding(\.subtitleStyle.colour)) {
                ForEach(SubtitleColour.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .settingsHover()
            Picker("Background", selection: binding(\.subtitleStyle.background)) {
                ForEach(SubtitleBackground.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .settingsHover()
            LabeledContent("Position") {
                CornerSlider(value: Binding(get: { player.subtitleStyle.bottomMargin }, set: { value in
                    Task { await model.updatePlayer { $0.subtitleStyle.bottomMargin = value } }
                }), in: SubtitleStyle.positionRange, step: 1, onEditingChanged: { editing in
                    if !editing { Haptics.play(.sliders) }
                })
                    .frame(maxWidth: 220)
                    .accessibilityValue("\(Int(player.subtitleStyle.bottomMargin)) percent from the bottom")
            }
            Toggle("Apply to styled (ASS) subtitles", isOn: binding(\.subtitleStyle.overridesFileStyles))
            Stepper("HDR brightness: \(player.subtitleStyle.hdrPeakNits) nits", value: binding(\.subtitleStyle.hdrPeakNits),
                    in: SubtitleStyle.hdrPeakRange, step: 20)
                .settingsHover()
                .accessibilityIdentifier("settings.player.subtitleHDR")
        }
    }

    private var commonDefaults: some View {
        SettingsSection("Defaults") {
            // Nothing saved reads as English, the language the player picks then.
            Picker("Audio language", selection: Binding<String?>(get: { player.audioLanguage ?? PlayerPreferences.defaultAudioLanguage }, set: { value in
                Haptics.play(.choices)
                Task { await model.updatePlayer { $0.audioLanguage = value } }
            })) {
                ForEach(SettingsViewModel.audioLanguageOptions) { Text($0.label).tag($0.value) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.audioLanguage")
            if aetherEngineLinked, model.settings.fallbackEngineEnabled, player.advancedEngine == .aether {
                Toggle("Spatial audio for TrueHD and DTS:X", isOn: binding(\.rendersObjectAudio))
                    .accessibilityIdentifier("settings.aether.objectAudio")
            }
            Picker("Starting speed", selection: binding(\.playbackSpeed)) {
                ForEach(PlayerPreferences.playbackSpeedOptions, id: \.self) { Text(Self.speedLabel($0)).tag($0) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.speed")
        }
    }

    private var controlsSection: some View {
        SettingsSection("Controls") {
            Picker("Skip back", selection: binding(\.skipBackSeconds)) {
                ForEach(PlayerPreferences.skipIntervalOptions, id: \.self) { Text(Self.secondsLabel($0)).tag($0) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.skipBack")
            Picker("Skip forward", selection: binding(\.skipForwardSeconds)) {
                ForEach(PlayerPreferences.skipIntervalOptions, id: \.self) { Text(Self.secondsLabel($0)).tag($0) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.skipForward")
            Toggle("Double-tap to skip", isOn: binding(\.doubleTapSkips))
                .accessibilityIdentifier("settings.player.doubleTapSkips")
            Picker("Hide controls", selection: binding(\.controlsHideSeconds)) {
                ForEach(PlayerPreferences.controlsHideOptions, id: \.self) { seconds in
                    Text(seconds == 0 ? "Never" : "After \(Self.secondsLabel(seconds))").tag(seconds)
                }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.hideControls")
            Toggle("Skip Intro & Credits buttons", isOn: binding(\.showsSkipButtons))
            Toggle("Skip intros automatically", isOn: binding(\.skipsIntrosAutomatically))
                .disabled(!player.showsSkipButtons)
            #if !targetEnvironment(macCatalyst)
            // Brightness has no app control on the Mac, and its keyboard already sets the volume.
            Toggle("Swipe for brightness", isOn: binding(\.swipeGestures))
            #endif
        }
    }

    private func detailSummary(_ page: Detail) -> String {
        switch page {
        case .subtitles: model.subtitleSummary
        case .picture: player.zoomMode.onThisDevice.label
        case .controls: "\(player.skipBackSeconds)s back · \(player.skipForwardSeconds)s forward"
        }
    }

    /// Which player plays, and the engine the built-in player falls back on for what AVPlayer cannot play.
    private var engineSection: some View {
        Section {
            Picker("Play with", selection: Binding(get: { model.settings.playerPreference }, set: { value in
                Haptics.play(.choices)
                Task { await model.setPlayerPreference(value) }
            })) {
                ForEach(PlayerPreference.allCases) { Text($0.title).tag($0) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player")
            if model.settings.playerPreference.externalPlayer != nil && !infuseInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Infuse isn’t installed on this device.").appFont(.small).foregroundStyle(.secondary)
                    if let url = ExternalPlayer.infuse.appStoreURL { Link("Get Infuse", destination: url).settingsLinkHover() }
                }
                .accessibilityIdentifier("settings.player.missing")
            }
            if model.fallbackEngineLinked {
                Toggle("Fallback player", isOn: Binding(get: { model.settings.fallbackEngineEnabled }, set: { value in
                    Haptics.play(.choices)
                    Task { await model.setFallbackEngineEnabled(value) }
                }))
                .accessibilityIdentifier("settings.fallbackToggle")
                if aetherEngineLinked, model.settings.fallbackEngineEnabled {
                    Picker("Fallback engine", selection: binding(\.advancedEngine)) {
                        Text("AetherEngine").tag(AdvancedEngine.aether)
                        Text("mpv").tag(AdvancedEngine.mpv)
                    }
                    .settingsHover()
                    .accessibilityIdentifier("settings.fallbackEngine")
                }
            }
        }
    }

    /// "10 seconds", "1 minute".
    static func secondsLabel(_ seconds: Int) -> String {
        seconds == 60 ? "1 minute" : "\(seconds) seconds"
    }

    /// "1×", "1.25×", "0.5×".
    static func speedLabel(_ speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    /// The picture's defaults, then upscaling: whether this device can run AI upscaling, and what it did on the last video played with it.
    private var pictureSection: some View {
        SettingsSection("Picture") {
            if aetherEngineLinked, model.settings.fallbackEngineEnabled, player.advancedEngine == .aether {
                Toggle("Compose Dolby Vision FEL", isOn: binding(\.composesDolbyVisionFEL))
                    .accessibilityIdentifier("settings.aether.fel")
            }
            Picker("Zoom", selection: Binding(get: { player.zoomMode.onThisDevice }, set: { value in
                Haptics.play(.choices)
                Task { await model.updatePlayer { $0.zoomMode = value.onThisDevice } }
            })) {
                ForEach(VideoZoomMode.available) { Text($0.label).tag($0) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.zoomMode")
            Toggle("Dolby Vision", isOn: binding(\.processing.dolbyVision))
                .accessibilityIdentifier("settings.player.dolbyVision")
            Picker("HDR", selection: binding(\.processing.hdrOutput)) {
                ForEach(HDROutputMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .settingsHover()
            // Full range on every engine; mpv's in-player slider sets how far it lifts HDR (AVPlayer and AetherEngine have no levels).
            Toggle("Full HDR brightness", isOn: Binding(get: { player.processing.hdrBrightness > 0 }, set: { on in
                Haptics.play(.choices)
                Task { await model.updatePlayer { $0.processing.hdrBrightness = on ? 1 : 0 } }
            }))
            .accessibilityIdentifier("settings.player.hdrBrightness")
            Picker("Tone mapping", selection: binding(\.processing.toneMapping)) {
                ForEach(ToneMappingCurve.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .settingsHover()
            Picker("Deinterlacing", selection: binding(\.processing.deinterlace)) {
                ForEach(DeinterlaceMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .settingsHover()
            Toggle("Ambient mode", isOn: binding(\.ambientMode))
            Picker("Upscaling", selection: binding(\.processing.upscaling)) {
                ForEach(UpscalingMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .settingsHover()
            .accessibilityIdentifier("settings.player.upscaling")
            if player.processing.upscaling == .ai {
                LabeledContent(Self.deviceName) {
                    Text(SuperResolutionRenderer.isSupportedOnThisDevice ? "AI scaler available" : "No AI scaler")
                        .foregroundStyle(SuperResolutionRenderer.isSupportedOnThisDevice ? Color.secondary : Color.orange)
                }
                .accessibilityIdentifier("settings.player.upscaling.device")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last video")
                        Spacer()
                        if lastReportDate > 0 {
                            Text(Date(timeIntervalSince1970: lastReportDate), format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(lastReport.isEmpty ? "Nothing played with AI upscaling yet." : lastReport)
                        .appFont(.small)
                        .foregroundStyle(lastReport.hasPrefix("Ran") ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.player.upscaling.last")
            }
        }
    }

    @AppStorage(UpscalingReport.summaryKey) private var lastReport = ""
    @AppStorage(UpscalingReport.dateKey) private var lastReportDate: Double = 0

    private static var deviceName: String {
        #if targetEnvironment(macCatalyst)
        "This Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This iPhone"
        #endif
    }
}
/// Settings → Player → OpenSubtitles: the account subtitle searches use.
private struct OpenSubtitlesSettingsPage: View {
    let model: SettingsViewModel

    var body: some View {
        SettingsList {
            Section {
                LabeledContent("Status", value: model.openSubtitlesSummary)
                    .accessibilityIdentifier("settings.opensubtitles.status")
                SecureField("API key", text: Binding(get: { model.openSubtitlesAPIKeyText }, set: { model.openSubtitlesAPIKeyText = $0 }))
                    .textContentType(.password)
                    .accessibilityIdentifier("settings.opensubtitles.key")
                TextField("Username (optional)", text: Binding(get: { model.openSubtitlesUsernameText }, set: { model.openSubtitlesUsernameText = $0 }))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.opensubtitles.username")
                SecureField("Password (optional)", text: Binding(get: { model.openSubtitlesPasswordText }, set: { model.openSubtitlesPasswordText = $0 }))
                    .textContentType(.password)
                    .accessibilityIdentifier("settings.opensubtitles.password")
            }
            Section {
                Button("Save") { Task { await model.commitOpenSubtitles() } }
                    .accessibilityIdentifier("settings.opensubtitles.save")
                Button("Sign In") { Task { await model.signInToOpenSubtitles() } }
                    .disabled(!model.canSignInToOpenSubtitles)
                    .accessibilityIdentifier("settings.opensubtitles.signIn")
                if model.isSigningInToOpenSubtitles { ProgressView() }
                if let message = model.lastMessage {
                    Text(message).appFont(.small).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.opensubtitles.message")
                }
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .settingsPage("OpenSubtitles")
        .disabled(model.isSigningInToOpenSubtitles)
        .onAppear { model.clearMessage() }
    }
}
#endif
