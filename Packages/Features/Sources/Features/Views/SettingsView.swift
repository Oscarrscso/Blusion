#if canImport(UIKit)
import Network
import SwiftUI
import StremioKit
import UIKit
import UniformTypeIdentifiers

/// The Settings root: one row per area, each with a one-line summary of its current state. The areas are pages of their own below,
/// all reading and writing the one `SettingsViewModel` the root owns.
struct SettingsView: View {
    @Environment(\.layoutMetrics) private var metrics
    @State private var model: SettingsViewModel
    @State private var syncFolderName: String?
    @State private var traktConnected: Bool?
    @State private var downloadsBytes: Int64?
    @AppStorage(LazyLoadLookahead.defaultsKey) private var lookaheadLevel = LazyLoadLookahead.defaultLevel
    /// Performance's other choices, read so its row's summary follows them.
    @AppStorage(OptimisationSettings.homePreloadKey) private var optimisationHome = OptimisationSettings.homePreloadMatchesLazyLoad
    @AppStorage(OptimisationSettings.pictureMemoryKey) private var optimisationMemory = OptimisationSettings.defaultPictureMemory
    @AppStorage(OptimisationSettings.downloadSlotsKey) private var optimisationSlots = OptimisationSettings.defaultDownloadSlots
    @AppStorage(OptimisationSettings.prefetchesStreamsKey) private var optimisationPrefetch = true
    @AppStorage(OptimisationSettings.readiesFirstStreamKey) private var optimisationReadies = true
    @AppStorage(OptimisationSettings.savesPowerKey) private var optimisationSavesPower = true
    @AppStorage(ImageCachePolicy.diskMegabytesKey) private var imageCacheMegabytes = ImageCachePolicy.defaultDiskMegabytes
    @AppStorage(AppearancePreferences.defaultsKey) private var appearance = AppearancePreferences()
    private let services: AppServices
    let fallbackEngineLinked: Bool
    let aetherEngineLinked: Bool
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape
    @Environment(LandscapeTabBarState.self) private var landscapeTabs: LandscapeTabBarState?
    @Environment(AppRouter.self) private var router
    /// Ghost mode, kept between launches (see `GhostMode`). Pulling the page down past the lock distance switches it, as the player's
    /// drag down locks 2× (`GhostModePullRules`).
    @AppStorage(GhostMode.defaultsKey) private var ghostIsOn = false
    /// How far the page is pulled down past its top, in points.
    @State private var pull: CGFloat = 0
    #if targetEnvironment(macCatalyst)
    /// The page opened from the chosen page, shown to its right (see `SettingsDetailColumns`).
    @State private var sidePage = SettingsSidePage()
    #endif
    /// How far the pull has got toward a toggle, 0...1, which the ring round the ghost draws (`GhostModePullRules.progress`).
    @State private var holdProgress: CGFloat = 0
    /// True after this overscroll has already toggled, so crossing the lock mark again before the list settles does not flip twice.
    @State private var didToggleThisPull = false

    init(services: AppServices) {
        _model = State(initialValue: SettingsViewModel(services: services))
        self.services = services
        fallbackEngineLinked = services.fallbackEngineLinked
        aetherEngineLinked = services.aetherEngineLinked
    }

    var body: some View {
        #if targetEnvironment(macCatalyst)
        // As on iPad: the list beside the page chosen in it, and what that page pushes on a stack of its own.
        @Bindable var router = router
        NavigationSplitView(columnVisibility: .constant(.all)) {
            list
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 400)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailColumns(sidePage: sidePage) {
                NavigationStack(path: $router.settingsPath) {
                    if let selection = router.settingsSelection {
                        page(selection)
                    } else {
                        Color.clear.screenBackground()
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: router.settingsSelection) {
            router.settingsPath = NavigationPath()
            sidePage.close()
            // The list stays on screen beside the page, so its summaries catch up when another page is chosen.
            Task { await refreshSummaries() }
        }
        #else
        list.navigationDestination(for: SettingsDestination.self) { page($0) }
            // A section's row opened from the list, as on a button (the Haptics page's Buttons).
            .onChange(of: router.settingsPath.count) { old, new in
                if old == 0, new == 1 { Haptics.play(.buttons) }
            }
        #endif
    }

    private var list: some View {
        @Bindable var router = router
        return SettingsList(selection: Self.selectsBesideList ? $router.settingsSelection : nil) {
            if ghostIsOn {
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        Text("👻").appFont(style: .title2, weight: .regular, role: .display).accessibilityHidden(true)
                        Text("Ghost mode is on").appFont(.mediumStrong)
                        Spacer(minLength: 0)
                        Button("Turn Off") { setGhost(false) }
                            .buttonStyle(.glassCapsule)
                            .accessibilityIdentifier("settings.ghost.off")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.ghost")
                    .listRowBackground(SettingsRowBackground())
                }
            }
            Section("Sources") {
                link(.addons) {
                    SettingsRow(title: "Addons", summary: "\(model.installedAddonCount) installed", systemImage: "puzzlepiece.extension")
                }
                .accessibilityIdentifier("settings.addons")
                link(.server) {
                    SettingsRow(title: "Streaming Server", summary: serverSummary, systemImage: "server.rack")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Streaming Server, \(serverSummary)")
                .accessibilityIdentifier("settings.section.server")
            }
            Section("Playback") {
                link(.streams) {
                    SettingsRow(title: "Streams", summary: streamsSummary, systemImage: "play.square.stack")
                }
                .accessibilityIdentifier("settings.section.playback")
                link(.player) {
                    SettingsRow(title: "Player", summary: playerSummary, systemImage: "play.rectangle")
                }
                .accessibilityIdentifier("settings.section.player")
                link(.downloads) {
                    SettingsRow(title: "Downloads", summary: downloadsSummary, systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("settings.section.downloads")
            }
            Section("Customise") {
                link(.appearance) {
                    SettingsRow(title: "Appearance", summary: appearanceSummary, systemImage: "paintpalette")
                }
                .accessibilityIdentifier("settings.section.appearance")
                link(.widgets) {
                    SettingsRow(title: "Widgets", systemImage: "rectangle.3.group")
                }
                .accessibilityIdentifier("settings.widgets")
                // A Mac has no haptic hardware, so the page would be sliders it cannot demonstrate.
                #if !targetEnvironment(macCatalyst)
                link(.haptics) {
                    SettingsRow(title: "Haptics", summary: hapticsSummary, systemImage: "hand.tap")
                }
                .accessibilityIdentifier("settings.section.haptics")
                #endif
            }
            Section("Accounts & Sync") {
                link(.trakt) {
                    SettingsRow(title: "Trakt", summary: traktSummary, systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("settings.trakt")
                link(.ratings) {
                    SettingsRow(title: "Ratings", summary: ratingsSummary, systemImage: "star.bubble")
                }
                .accessibilityIdentifier("settings.section.reviews")
                if services.sharedFolder != nil {
                    link(.syncFolder) {
                        SettingsRow(title: "Widget Sync", summary: syncFolderName ?? "Off", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("settings.section.syncFolder")
                }
            }
            Section("Advanced") {
                link(.performance) {
                    SettingsRow(title: "Performance", summary: performanceSummary, systemImage: "gauge.with.dots.needle.67percent")
                }
                .accessibilityIdentifier("settings.section.optimisation")
                link(.data) {
                    SettingsRow(title: "Clear Data", systemImage: "trash")
                }
                .accessibilityIdentifier("settings.section.data")
            }
            Section {
                link(.about) {
                    SettingsRow(title: "About", summary: "Version \(SettingsViewModel.appVersion)", systemImage: "info.circle")
                }
                .accessibilityIdentifier("settings.section.about")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .readableColumn()
        .trackLandscapeTabScroll()
        .screenBackground()
        .navigationTitle("Settings")
        .macRootNavigation()
        .pageTabBar(hidden: isPhoneInLandscape)
        .navigationBarTitleDisplayMode(.inline)
        // On iPhone, each return to the list: a page pushed from it may have changed what a summary reads.
        .onAppear { Task { await refreshSummaries() } }
        // The review services changed while Settings was open.
        .onChange(of: services.posterRatings.reviewServicesRevision) { model.refreshOMDbUsage() }
        .accessibilityIdentifier("settings.form")
        // The pull past the top fills the ghost's ring by distance, then toggles once it crosses the lock mark — the same approach as
        // locking 2× by dragging down in the player (`GhostModePullRules` / `SpeedHoldRules`).
        .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, value in
            pull = value
            holdProgress = GhostModePullRules.progress(pull: value)
            if GhostModePullRules.locks(pull: value) {
                guard !didToggleThisPull else { return }
                didToggleThisPull = true
                setGhost(!ghostIsOn)
            } else if value < GhostModePullRules.armPull {
                didToggleThisPull = false
            }
        }
        .overlay(alignment: .top) { ghostPullIndicator }
    }

    /// Mac shows the chosen page beside the list; iPhone pushes it.
    private static var selectsBesideList: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// A row that opens `destination`. Beside the list, the chosen row is lit.
    private func link<Label: View>(_ destination: SettingsDestination, @ViewBuilder label: () -> Label) -> some View {
        Group {
            #if targetEnvironment(macCatalyst)
            Button {
                Haptics.play(.buttons)
                router.settingsSelection = destination
            } label: {
                rowLabel(label)
            }
            .buttonStyle(.plain)
            #else
            // The Buttons haptic plays as the list opens a page (see `body`), so no extra gesture competes with the link's tap.
            NavigationLink(value: destination) {
                rowLabel(label)
            }
            #endif
        }
        .listRowBackground(SettingsRowBackground(isSelected: Self.selectsBesideList && router.settingsSelection == destination))
    }

    private func rowLabel<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        label()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .pointerInteraction(cornerRadius: Theme.Radius.surface * metrics.cornerScale(for: .settingsRows), showsFocus: false)
    }

    @ViewBuilder
    private func page(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .addons: AddonsView(services: services)
        case .server: ServerSettingsPage(model: model)
        case .streams: StreamsSettingsPage(model: model, services: services)
        case .player: PlayerSettingsPage(model: model, aetherEngineLinked: aetherEngineLinked)
        case .downloads: DownloadSettingsPage(services: services)
        case .appearance: AppearanceSettingsPage(model: model)
        case .widgets: WidgetsManagerView(services: services, startsHidden: true)
        case .haptics:
            #if targetEnvironment(macCatalyst)
            EmptyView()
            #else
            HapticsSettingsPage(model: model)
            #endif
        case .trakt: TraktAccountView(services: services, settings: model)
        case .ratings: RatingsSettingsPage(model: model, services: services)
        case .syncFolder:
            if let folder = services.sharedFolder { SyncFolderSettingsPage(folder: folder, services: services) }
        case .performance: PerformanceSettingsPage()
        case .data: DataSettingsPage(model: model)
        case .about: AboutSettingsPage(fallbackEngineLinked: fallbackEngineLinked, aetherEngineLinked: aetherEngineLinked)
        }
    }

    private var isPhoneInLandscape: Bool { isPhoneLandscape && UIDevice.current.userInterfaceIdiom == .phone }

    /// The summaries that read state other than the settings model's: Trakt's sign-in, the downloads on disk and the sync folder.
    private func refreshSummaries() async {
        await model.load()
        syncFolderName = services.sharedFolder?.folderName
        downloadsBytes = services.downloads?.storageBytes
        traktConnected = await services.traktAccount.isSignedIn()
    }

    private func setGhost(_ isOn: Bool) {
        // A button's tap, not a switch's: Ghost mode changes what every screen shows, so it lands like a change of screen.
        Haptics.play(.buttons)
        // Write through both the preference and the stores' reader, so a held pull applies even if AppStorage lags a frame.
        GhostMode.isOn = isOn
        withAnimation(.snappy(duration: 0.3)) { ghostIsOn = isOn }
    }

    /// Shown while the page is pulled down: a ghost in a ring that fills with pull distance, and what crossing the lock does.
    @ViewBuilder
    private var ghostPullIndicator: some View {
        if pull > 24 {
            HStack(spacing: Theme.Spacing.s) {
                Text("👻")
                    .appFont(style: .title3, weight: .regular, role: .display)
                    .padding(8)
                    .background {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                        Circle().trim(from: 0, to: holdProgress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                Text(holdProgress >= 1 ? (ghostIsOn ? "Ghost mode on" : "Ghost mode off")
                     : holdProgress > 0
                     ? (ghostIsOn ? "Keep pulling to leave ghost mode" : "Keep pulling for ghost mode")
                     : (ghostIsOn ? "Pull further to leave ghost mode" : "Pull further for ghost mode"))
                    .appFont(.smallStrong)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .glassEffect(.regular, in: ScaledCapsule(scale: metrics.cornerScale(for: .settingsRows)))
            .opacity(min(1, (pull - 24) / 30))
            .padding(.top, Theme.Spacing.s)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Whether Auto Pick starts on its own, the quality asked for, and the source Auto Pick prefers when it is not balanced.
    private var streamsSummary: String {
        let settings = model.settings
        let quality = settings.dataSaverLevel == .ultra ? "Ultra Saver" : settings.dataSaver ? "Data Saver"
            : SettingsViewModel.resolutionOptions.first { $0.value == settings.preferredResolution }?.label ?? "Best available"
        var parts = [settings.autoPlayBestStream ? "Auto Pick" : "Manual", quality]
        if settings.autoPlayBestStream, settings.autoPickSource != .balanced { parts.append(settings.autoPickSource.title) }
        return parts.joined(separator: " · ")
    }

    /// Which player plays, and the subtitles it starts with.
    private var playerSummary: String {
        let player = switch model.settings.playerPreference {
        case .builtIn: "Blusion"
        case .infuse: "Infuse"
        case .infuseWhenNeeded: "Blusion, then Infuse"
        }
        return "\(player) · \(model.subtitleSummary)"
    }

    private var serverSummary: String { model.settings.serverURL.map(Redactor.displayHost) ?? "Not set" }

    private var downloadsSummary: String {
        guard let downloadsBytes else { return "" }
        return downloadsBytes > 0 ? ByteCountFormatter.string(fromByteCount: downloadsBytes, countStyle: .file) : "None"
    }

    private var traktSummary: String {
        if ghostIsOn { return "Paused by Ghost Mode" }
        return traktConnected.map { $0 ? "Connected" : "Not connected" } ?? ""
    }

    /// The preset in use, or what differs from the app's own look (accent, background, cards, text), then the poster switches that are on.
    private var appearanceSummary: String {
        var on: [String] = []
        if let preset = appearance.preset, preset != .original { return preset.label }
        if appearance.accent != .blusion { on.append(appearance.accent.label) }
        if appearance.background != .black { on.append(appearance.background.label) }
        if appearance.cardScale != 1 { on.append("\(Int((appearance.cardScale * 100).rounded()))% cards") }
        if appearance.textSize != .system { on.append("\(appearance.textSize.label) text") }
        if appearance.font != .standard { on.append(appearance.font.label) }
        if !on.isEmpty || !appearance.isDefault {
            return on.isEmpty ? "Custom" : on.joined(separator: ", ")
        }
        if model.settings.usesHeroPosters { on.append("Hero artwork on posters") }
        if model.settings.showsPosterRatings { on.append("Ratings on posters") }
        if model.settings.showsColouredRatingLogos { on.append("Coloured logos") }
        if model.settings.showsBestDiscOnPosters { on.append("Disc and streamer marks") }
        return on.isEmpty ? "Default" : on.joined(separator: ", ")
    }

    /// The Haptics row shows whether anything has been tuned: the overall strength when it is not 100%, and how many places are off.
    private var hapticsSummary: String {
        let haptics = model.settings.haptics
        guard haptics.isOn else { return "Off" }
        let places = HapticPreferences.Place.allCases
        var parts: [String] = []
        if haptics.overall != HapticPreferences.Default.overallStrength {
            parts.append("\(Int((haptics.overall * 100).rounded()))% overall")
        }
        let off = places.filter { !haptics.plays($0) }.count
        if off > 0 { parts.append("\(off) of \(places.count) off") }
        guard parts.isEmpty else { return parts.joined(separator: " · ") }
        return places.allSatisfy(haptics.isDefault) ? "Default" : "Custom"
    }

    private var ratingsSummary: String {
        var saved: [String] = []
        if model.settings.omdbAPIKey != nil { saved.append("OMDb") }
        if model.settings.tmdbReadToken != nil { saved.append("TMDB") }
        var text = saved.isEmpty ? "IMDb only" : saved.joined(separator: ", ")
        if model.settings.omdbAPIKey != nil {
            text += " · \(model.omdbRequestsToday.formatted()) of \(SettingsViewModel.omdbDailyLimit.formatted()) today"
        }
        return text
    }
}

extension SettingsView {
    /// How far lists load ahead, then whether anything else on the page has been changed.
    private var performanceSummary: String {
        let level = "Load ahead: \(lazyLoadLabel(lookaheadLevel))"
        let isDefault = optimisationHome == OptimisationSettings.homePreloadMatchesLazyLoad
            && optimisationMemory == OptimisationSettings.defaultPictureMemory && optimisationSlots == OptimisationSettings.defaultDownloadSlots
            && optimisationPrefetch && optimisationReadies && optimisationSavesPower
            && imageCacheMegabytes == ImageCachePolicy.defaultDiskMegabytes
        return isDefault ? level : "\(level) · Custom"
    }
}

func lazyLoadLabel(_ level: Int) -> String {
    LazyLoadLookahead.levels[min(max(level, 1), LazyLoadLookahead.levels.count) - 1].label
}

/// One row of the Settings root, in the format of the Widgets page: a symbol, a title and a one-line summary. Also the Haptics page's
/// rows, one per place.
struct SettingsRow: View {
    let title: String
    /// What the area is set to now. A row with no state of its own to report has none.
    var summary: String?
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let summary {
                    Text(summary).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

/// A native list with app-owned row backgrounds, so its corners can be adjusted independently.
struct SettingsList<Content: View>: View {
    /// Mac Settings' choice of page. With one, each row draws its own background, so the chosen row can be lit (see `SettingsView`).
    var selection: Binding<SettingsDestination?>? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if let selection {
                List(selection: selection) {
                    content()
                        .listRowSeparator(.hidden)
                }
            } else {
                List {
                    content()
                        .listRowBackground(SettingsRowBackground())
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.grouped)
        .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
        .listRowSpacing(4)
    }
}

struct SettingsRowBackground: View {
    /// The page shown beside the list (Mac Settings).
    var isSelected = false
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.surface * metrics.cornerScale(for: .settingsRows), style: .continuous)
            .fill(isSelected ? AnyShapeStyle(TintShapeStyle().opacity(0.35)) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

/// The look every Settings page shares with the Widgets page.
extension View {
    func settingsPage(_ title: String) -> some View {
        listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .readableColumn()
            .screenBackground()
            .navigationTitle(title)
            .macBackNavigation()
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
