#if canImport(UIKit)
import Network
import SwiftUI
import StremioKit
import UIKit
import UniformTypeIdentifiers

/// Settings → Streams: the quality asked of addons, and Auto Pick (whether it plays on its own, the source it prefers and which addons
/// it waits for).
struct StreamsSettingsPage: View {
    let model: SettingsViewModel
    let services: AppServices

    var body: some View {
        SettingsList {
            Section {
                Picker("Quality",
                       selection: Binding(get: { model.settings.preferredResolution },
                                          set: { value in Haptics.play(.choices); Task { await model.setPreferredResolution(value) } })) {
                    ForEach(SettingsViewModel.resolutionOptions) { Text($0.label).tag($0.value) }
                }
                .buttonCursor()
                .accessibilityIdentifier("settings.resolution")
                // Ultra keeps to 720p and the leanest encodes.
                Picker("Data Saver",
                       selection: Binding(get: { model.settings.dataSaverLevel },
                                          set: { level in Haptics.play(.choices); Task { await model.setDataSaverLevel(level) } })) {
                    ForEach(DataSaverLevel.allCases) { Text($0.title).tag($0) }
                }
                .buttonCursor()
                .accessibilityIdentifier("settings.dataSaver")
            }
            Section("Auto Pick") {
                Toggle("Play best stream automatically", isOn: Binding(get: { model.settings.autoPlayBestStream }, set: { value in
                    Task { await model.setAutoPlayBestStream(value) }
                }))
                .accessibilityIdentifier("settings.autoPlay")
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Prefer")
                    CornerSegmentedPicker("Prefer", options: StreamSourcePreference.allCases, selection: Binding(get: { model.settings.autoPickSource }, set: { value in
                        Haptics.play(.choices)
                        Task { await model.setAutoPickSource(value) }
                    })) {
                        $0.title
                    }
                    .accessibilityIdentifier("settings.autoPickSource")
                }
                SettingsSubpageLink(id: "streams.addonSpeed") {
                    AddonSpeedSettingsPage(services: services, onChange: { Task { await model.load() } })
                } label: {
                    LabeledContent("Waits for", value: waitSummary)
                }
                .accessibilityIdentifier("settings.section.addonSpeed")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Streams")
    }

    private var waitSummary: String {
        switch model.settings.autoPickWait {
        case .allAddons: "All addons"
        case .fastest: "Fastest addon"
        case .addon: AddonSpeedViewModel.summary(for: model.settings.autoPickWait, names: model.addonNames)
        }
    }
}

/// Settings → Performance: how far ahead lists and Home load, what is readied before Play, how much artwork is held, downloaded at once
/// and kept on disk, and Low Power Mode (see `OptimisationSettings`, `ImageCachePolicy`). Every choice applies at once.
struct PerformanceSettingsPage: View {
    @AppStorage(LazyLoadLookahead.defaultsKey) private var lookaheadLevel = LazyLoadLookahead.defaultLevel
    @AppStorage(OptimisationSettings.homePreloadKey) private var homePreload = OptimisationSettings.homePreloadMatchesLazyLoad
    @AppStorage(OptimisationSettings.prefetchesStreamsKey) private var prefetchesStreams = true
    @AppStorage(OptimisationSettings.readiesFirstStreamKey) private var readiesFirstStream = true
    @AppStorage(OptimisationSettings.pictureMemoryKey) private var pictureMemory = OptimisationSettings.defaultPictureMemory
    @AppStorage(OptimisationSettings.downloadSlotsKey) private var downloadSlots = OptimisationSettings.defaultDownloadSlots
    @AppStorage(OptimisationSettings.savesPowerKey) private var savesPower = true
    @AppStorage(ImageCachePolicy.diskMegabytesKey) private var diskMegabytes = ImageCachePolicy.defaultDiskMegabytes
    @State private var diskInUse: Int?
    @State private var confirmsClear = false

    private var isDefault: Bool {
        lookaheadLevel == LazyLoadLookahead.defaultLevel && homePreload == OptimisationSettings.homePreloadMatchesLazyLoad
            && prefetchesStreams && readiesFirstStream && pictureMemory == OptimisationSettings.defaultPictureMemory
            && downloadSlots == OptimisationSettings.defaultDownloadSlots && savesPower
            && diskMegabytes == ImageCachePolicy.defaultDiskMegabytes
    }

    var body: some View {
        SettingsList {
            Section("Load Ahead") {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack {
                        Text("Lists")
                        Spacer()
                        Text("\(lazyLoadLabel(lookaheadLevel)) · \(LazyLoadLookahead.titles(atLevel: lookaheadLevel)) titles")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    GlassSlider(value: $lookaheadLevel, stops: LazyLoadLookahead.levels.count)
                        .accessibilityLabel("Lists")
                        .accessibilityValue(lazyLoadLabel(lookaheadLevel))
                        .accessibilityIdentifier("settings.lazyLoadLookahead")
                    HStack {
                        Text(LazyLoadLookahead.levels[0].label)
                        Spacer()
                        Text(LazyLoadLookahead.levels[LazyLoadLookahead.levels.count - 1].label)
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
                picker("Home", selection: $homePreload, options: OptimisationSettings.homePreloadOptions,
                       id: "settings.optimisation.homePreload")
            }
            Section("Streams") {
                Toggle("Look up streams when a title opens", isOn: choice($prefetchesStreams))
                    .accessibilityIdentifier("settings.optimisation.prefetchStreams")
                Toggle("Pre-buffer the top stream", isOn: choice($readiesFirstStream))
                    .accessibilityIdentifier("settings.optimisation.readyFirstStream")
            }
            Section("Artwork") {
                picker("Memory", selection: $pictureMemory, options: pictureMemoryOptions, id: "settings.optimisation.pictureMemory")
                picker("Downloads at once", selection: $downloadSlots, options: OptimisationSettings.downloadSlotOptions,
                       id: "settings.optimisation.downloadSlots")
                Picker("Disk cache", selection: Binding(get: { diskMegabytes }, set: { new in
                    Haptics.play(.choices)
                    diskMegabytes = new
                })) {
                    ForEach(ImageCachePolicy.diskSizeOptions, id: \.self) { Text(Self.sizeName($0)).tag($0) }
                }
                .buttonCursor()
                .accessibilityIdentifier("settings.imageCache.size")
                LabeledContent("Disk cache used") {
                    Text(diskInUse.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—")
                        .monospacedDigit()
                        .accessibilityLabel(diskInUse.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Measuring")
                }
                .accessibilityIdentifier("settings.imageCache.inUse")
                Button("Clear Artwork Cache", role: .destructive) { confirmsClear = true }
                    .accessibilityIdentifier("settings.imageCache.clear")
            }
            Section {
                Toggle("Save power in Low Power Mode", isOn: choice($savesPower))
                    .accessibilityIdentifier("settings.optimisation.savesPower")
            }
            Section {
                Button("Restore Defaults") {
                    Haptics.play(.buttons)
                    for key in OptimisationSettings.allKeys + [ImageCachePolicy.diskMegabytesKey] { UserDefaults.standard.removeObject(forKey: key) }
                    applyPictures()
                    applyDiskLimit()
                }
                .disabled(isDefault)
                .accessibilityIdentifier("settings.optimisation.restore")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Performance")
        .task { diskInUse = ImagePipeline.shared.diskUsage }
        .onChange(of: pictureMemory) { applyPictures() }
        .onChange(of: downloadSlots) { applyPictures() }
        .onChange(of: savesPower) { applyPictures() }
        .onChange(of: diskMegabytes) { applyDiskLimit() }
        .confirmationDialog("Clear the artwork cache?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear Artwork Cache", role: .destructive) {
                // Off the main thread: emptying a full cache takes a moment, and the page should not stall while it does.
                Task {
                    await Task.detached(priority: .userInitiated) { ImagePipeline.shared.clearDisk() }.value
                    diskInUse = ImagePipeline.shared.diskUsage
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Posters and backdrops download again as you browse.")
        }
    }

    /// Memory's choices with what each holds on this device: "Balanced · 1 GB".
    private var pictureMemoryOptions: [OptimisationSettings.Option] {
        OptimisationSettings.pictureMemoryOptions.map { option in
            let bytes = ImageCachePolicy.decodedBytes(physicalMemory: ProcessInfo.processInfo.physicalMemory, level: option.value)
            return OptimisationSettings.Option(label: "\(option.label) · \(Self.sizeName(bytes / 1024 / 1024))", value: option.value)
        }
    }

    static func sizeName(_ megabytes: Int) -> String {
        megabytes >= 1024 ? "\(megabytes / 1024) GB" : "\(megabytes) MB"
    }

    /// A switch that ticks as it is flipped, as Settings' other switches do.
    private func choice(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { new in
            Haptics.play(.choices)
            value.wrappedValue = new
        })
    }

    private func picker(_ title: LocalizedStringKey, selection: Binding<Int>, options: [OptimisationSettings.Option], id: String) -> some View {
        Picker(title, selection: Binding(get: { selection.wrappedValue }, set: { new in
            Haptics.play(.choices)
            selection.wrappedValue = new
        })) {
            ForEach(options) { Text($0.label).tag($0.value) }
        }
        .buttonCursor()
        .accessibilityIdentifier(id)
    }

    /// The picture loader takes its new memory limit and number of downloads at once now, not at the next launch.
    private func applyPictures() {
        ImagePipeline.shared.setMemoryLevel(OptimisationSettings.pictureMemory())
        Task { await ImagePipeline.shared.downloadSlotsChanged() }
    }

    private func applyDiskLimit() {
        ImagePipeline.shared.setDiskLimit(megabytes: UserDefaults.standard.object(forKey: ImageCachePolicy.diskMegabytesKey) as? Int
                                          ?? ImageCachePolicy.defaultDiskMegabytes)
        diskInUse = ImagePipeline.shared.diskUsage
    }
}

/// Settings → Ratings: OMDb's requests today (the app's own OMDb and TMDB keys are built in), and the offline IMDb scores (when they
/// were last updated, and whose they are: IMDb asks for the credit and limits the data to personal, non-commercial use).
struct RatingsSettingsPage: View {
    let model: SettingsViewModel
    let services: AppServices
    @State private var datasetStatus: IMDbDatasetStatus?

    private var used: Int { model.omdbRequestsToday }
    private var limit: Int { SettingsViewModel.omdbDailyLimit }

    var body: some View {
        SettingsList {
            Section("OMDb") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Requests today", value: "\(used.formatted()) of \(limit.formatted())")
                    ProgressView(value: Double(min(used, limit)), total: Double(limit))
                        .tint(Double(used) >= Double(limit) * 0.9 ? .orange : nil)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.omdbUsage")
            }
            Section {
                Button("Refresh Ratings") { Task { await model.refreshRatings() } }
                    .accessibilityIdentifier("settings.reviews.refresh")
                if let error = services.posterRatings.omdbError ?? services.posterRatings.reviewServiceIssue {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.small)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("settings.reviews.error")
                } else if let message = model.lastMessage {
                    Text(message)
                        .font(Theme.Typography.small)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.reviews.message")
                }
            }
            Section {
                LabeledContent("Titles", value: datasetStatus.map { $0.titleCount.formatted() } ?? IMDbDatasetSummary.text(nil))
                    .accessibilityIdentifier("settings.imdbDataset")
                if let status = datasetStatus {
                    LabeledContent("Updated", value: (status.updatedAt ?? status.checkedAt)
                        .map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "Not yet")
                    LabeledContent("Size on disk", value: status.fileSize.map { $0.formatted(.byteCount(style: .file)) } ?? "Unknown")
                }
                if let url = IMDbAttribution.termsURL { Link("IMDb Data Terms", destination: url).buttonCursor() }
            } header: {
                Text("IMDb")
            } footer: {
                // IMDb's credit and terms, which its non-commercial datasets require.
                Text("\(IMDbAttribution.notice) \(IMDbAttribution.terms)")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Ratings")
        .onAppear { model.clearMessage() }
        .task {
            model.refreshOMDbUsage()
            datasetStatus = await services.posterRatings.imdbDatasetStatus()
        }
        // A new copy of the IMDb data arrived while the page was open, or the review services changed.
        .onChange(of: services.posterRatings.reviewServicesRevision) {
            model.refreshOMDbUsage()
            Task { datasetStatus = await services.posterRatings.imdbDatasetStatus() }
        }
    }
}

struct ServerSettingsPage: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsList {
            Section {
                TextField("http://192.168.1.10:11470", text: $model.serverURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .submitLabel(.done)
                    .onSubmit { Task { await model.commitServerURL() } }
                    .accessibilityLabel("Streaming server address")
                    .accessibilityIdentifier("settings.serverURL")
                if let message = model.serverURLMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.small)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("settings.serverURL.message")
                }
                Button("Save Address") { Task { await model.commitServerURL() } }
                    .disabled(model.serverURLMessage != nil)
                    .accessibilityIdentifier("settings.serverURL.save")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Streaming Server")
    }
}

struct DataSettingsPage: View {
    let model: SettingsViewModel
    @State private var pendingScope: DataResetService.Scope?

    var body: some View {
        SettingsList {
            Section {
                ForEach(DataResetService.Scope.allCases.filter { $0 != .everything }, id: \.self) { scope in clearButton(scope) }
            }
            Section {
                clearButton(.everything)
            }
            if let message = model.lastMessage {
                Section {
                    Label(message, systemImage: "checkmark.circle")
                        .font(Theme.Typography.small)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.clearMessage")
                }
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Clear Data")
        .onAppear { model.clearMessage() }
        .confirmationDialog(pendingScope.map { "Clear \($0.title.lowercased())?" } ?? "",
                            isPresented: Binding(get: { pendingScope != nil }, set: { if !$0 { pendingScope = nil } }),
                            titleVisibility: .visible, presenting: pendingScope) { scope in
            Button("Clear \(scope.title.lowercased())", role: .destructive) { Task { await model.clear(scope) } }
                .accessibilityIdentifier("settings.confirmClear")
            Button("Cancel", role: .cancel) {}
        } message: { scope in
            Text(scope.warning)
        }
    }

    private func clearButton(_ scope: DataResetService.Scope) -> some View {
        Button(scope.title, role: .destructive) { pendingScope = scope }
            .accessibilityIdentifier("settings.clear.\(String(describing: scope))")
    }
}

/// The folder the Home layout is shared through with the user's other devices, such as one in iCloud Drive (see `SyncedWidgetStore`).
struct SyncFolderSettingsPage: View {
    let folder: SharedFolder
    let services: AppServices
    @State private var folderName: String?
    @State private var isChoosing = false
    @State private var failed = false

    var body: some View {
        SettingsList {
            Section {
                LabeledContent("Folder", value: folderName ?? "None")
                Button(folderName == nil ? "Choose Folder" : "Change Folder") { isChoosing = true }
                    .accessibilityIdentifier("settings.syncFolder.choose")
                if folderName != nil {
                    Button("Stop Syncing", role: .destructive) {
                        folder.forget()
                        folderName = nil
                    }
                    .accessibilityIdentifier("settings.syncFolder.stop")
                }
                if failed {
                    Label("That folder can't be used.", systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.small)
                        .foregroundStyle(.orange)
                }
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Widget Sync")
        .onAppear { folderName = folder.folderName }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try folder.choose(url)
                folderName = folder.folderName
                failed = false
                // The first look at the folder: its layout comes in, or this device's layout starts it.
                Task { _ = await services.widgets.takeInSharedLayout() }
            } catch {
                failed = true
            }
        }
    }
}

/// How fast each addon answers, and what Auto Pick waits for. The test runs only when asked: every request is a real lookup. The addons
/// stay in the user's own order, which also orders Home's rows.
private struct AddonSpeedSettingsPage: View {
    @Environment(\.layoutMetrics) private var metrics
    @State private var model: AddonSpeedViewModel
    /// Tells Settings the choice changed, so its row's summary follows.
    let onChange: () -> Void
    @State private var isOnline = true

    init(services: AppServices, onChange: @escaping () -> Void) {
        _model = State(initialValue: AddonSpeedViewModel(services: services))
        self.onChange = onChange
    }

    var body: some View {
        SettingsList {
            Section {
                Button {
                    Task { await model.test() }
                } label: {
                    HStack {
                        Text(model.isTesting ? "Testing…" : "Test Speed")
                        Spacer(minLength: 0)
                        if model.isTesting { Spinner().controlSize(.small) }
                    }
                }
                .disabled(model.isTesting || !isOnline)
                .accessibilityIdentifier("settings.addonSpeed.test")
                ForEach(model.rows) { row in
                    HStack(spacing: Theme.Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.addon.name)
                            Text(AddonSpeedViewModel.detail(for: row.result))
                                .font(Theme.Typography.small)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        if row.id == model.fastest {
                            Text("Fastest")
                                .font(Theme.Typography.captionStrong)
                                .padding(.horizontal, Theme.Spacing.s)
                                .padding(.vertical, 3)
                                .background(.tint.opacity(0.25), in: ScaledCapsule(scale: metrics.cornerScale(for: .settingsRows)))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.addonSpeed.row.\(row.id.uuidString)")
                }
            } footer: {
                if !isOnline { Text("You're offline. Connect to test your addons.") }
            }
            Section {
                waitChoice("All addons", .allAddons)
                waitChoice("Fastest addon", .fastest)
                ForEach(model.rows) { row in waitChoice(row.addon.name, .addon(row.id)) }
            } header: {
                Text("Auto Pick Waits For")
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Addon Speed")
        .task { await model.load() }
        .task { for await path in NWPathMonitor() { isOnline = path.status == .satisfied } }
    }

    private func waitChoice(_ title: String, _ wait: AutoPickWait) -> some View {
        Button {
            Haptics.play(.choices)
            Task { await model.choose(wait, saved: onChange) }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 0)
                if model.shownWait == wait { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .accessibilityAddTraits(model.shownWait == wait ? .isSelected : [])
        .accessibilityIdentifier("settings.addonSpeed.wait.\(wait.storedValue)")
    }
}

struct AboutSettingsPage: View {
    let fallbackEngineLinked: Bool
    var aetherEngineLinked = false

    var body: some View {
        SettingsList {
            Section {
                LabeledContent("Version", value: SettingsViewModel.appVersion)
                SettingsSubpageLink(id: "about.acknowledgements") {
                    AcknowledgementsView(fallbackEngineLinked: fallbackEngineLinked, aetherEngineLinked: aetherEngineLinked)
                } label: {
                    Text("Acknowledgements")
                }
                    .accessibilityIdentifier("settings.acknowledgements")
            } footer: {
                Text("""
                    Blusion includes no content or stream sources. Cinemeta provides catalogs and search; you can remove it in Settings › \
                    Addons. Blusion isn’t affiliated with any addon or service.
                    """)
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("About")
    }
}

struct AcknowledgementsView: View {
    let fallbackEngineLinked: Bool
    var aetherEngineLinked = false

    var body: some View {
        SettingsList {
            Section {
                ForEach(Acknowledgement.all(fallbackEngineLinked: fallbackEngineLinked, aetherEngineLinked: aetherEngineLinked)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        if item.name == "TMDB" {
                            Image("ReviewTMDB").resizable().scaledToFit()
                                .frame(width: 80, height: 35)
                                .accessibilityLabel("TMDB")
                        }
                        Text(item.name).font(Theme.Typography.headline)
                        Text(item.license).font(Theme.Typography.medium).foregroundStyle(.secondary)
                        Text(item.detail).font(Theme.Typography.small)
                        if let url = item.sourceURL { Link("Source", destination: url).font(Theme.Typography.small).buttonCursor() }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        .settingsPage("Acknowledgements")
        .accessibilityIdentifier("acknowledgements.list")
    }
}
#endif
