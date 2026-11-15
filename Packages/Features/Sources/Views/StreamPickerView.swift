#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI
import UIKit

/// The player readied for a stream before its screen opens (see `PlayerViewModel.prepare`), and the stream it is for.
struct PreparedPlayer {
    let player: PlayerViewModel
    let itemID: RankedStream.ID
}

/// The stream a picker is readying in the foreground, its play button a spinner, or the one whose readying failed.
enum StreamPreparation {
    case idle
    /// Its player opens once the film is ready to play.
    case readying(itemID: RankedStream.ID, beganAt: Date)
    case failed(Failure)

    struct Failure {
        let itemID: RankedStream.ID
        let progress: PlaybackPreparation
        let beganAt: Date
        let endedAt: Date
    }

    var isReadying: Bool {
        if case .readying = self { return true }
        return false
    }

    func failure(for itemID: RankedStream.ID) -> Failure? {
        if case .failed(let failure) = self, failure.itemID == itemID { return failure }
        return nil
    }
}

/// One title's streams. The header says what is being picked. The best stream is
/// the one main action, and each addon's streams follow as rows of their own. Links to web pages come last. A stream plays in Blusion or,
/// when the viewer chose that player, opens in another app.
struct StreamPickerView: View {
    @State var model: StreamPickerViewModel
    @State var plan: PlaybackPlan?
    @State var expandedDetails: RankedStream?
    @State var isNotesExpanded = false
    @State var autoPickTask: Task<Void, Never>?
    @State var hasSelectedManually = false
    @State var isOpeningPlayer = false
    /// The first stream listed starts loading here in the background as soon as it arrives, so playing it is quick; another stream
    /// tapped replaces it.
    @State var prepared: PreparedPlayer?
    @State var backgroundLoadTask: Task<Void, Never>?
    @State var streamPreparation = StreamPreparation.idle
    /// True while the stream Auto Pick chose is being readied, so Auto Pick's button spins until the player opens.
    @State var preparingViaAutoPick = false
    /// The ready player the open player screen took over.
    @State var presentedPlayer: PlayerViewModel?
    /// The first stream's background load has been started, once per picker.
    @State var hasStartedBackgroundLoad = false
    /// The Auto Pick button's height and the switch's own size, as laid out: the switch is scaled to the button's height.
    @State var autoPickButtonHeight: CGFloat = 0
    /// The Auto Pick height last measured by any picker, for a picker that has not measured its own yet (see `episodeStepButton`).
    static var lastAutoPickHeight: CGFloat?
    /// Keep the last recommendation text and collapsed card heights while the next picker loads.
    static var lastAutoPickInfo: String?
    /// Held apart for each orientation, since a card's height follows the width it has.
    static var lastStreamCardHeights: [Bool: [Int: CGFloat]] = [:]
    @State var autoPickSwitchSize: CGSize = .zero
    /// The heading's natural size, so its title, rating and logo can shrink together between the fixed chevrons.
    /// The sharpness the chips narrow the list to; nil shows every stream.
    @State var resolutionFilter: Band?
    /// Keep the last visible resolution bar while the next picker's streams load.
    static var lastResolutionBands: [Band] = [.uhd, .fullHD, .hd]
    /// The one addon whose streams are listed, or nil for every addon's.
    @State var addonFilter: UUID?
    /// Keep the last available addons while the next picker's streams load.
    static var lastAvailableAddons: [AddonSummary] = []
    /// A stream whose format Blusion can't play: the alert offers another player, or the next stream.
    @State var unsupported: RankedStream?
    /// A hand-off whose player app is not installed: the alert offers its App Store page, or playing the stream in Blusion.
    @State var missing: MissingPlayer?
    /// The streams saved to another player's library from this picker, whose bookmarks are filled.
    @State var savedStreams: Set<RankedStream.ID> = []
    @State var pendingSaves: [String: RankedStream.ID] = [:]
    /// True when ghost mode stopped a stream that only opens in another app.
    @State var ghostBlocked = false
    /// The stream cards that have already come in, so a card scrolled away and back does not animate again.
    @State var entranceLog = StreamCardEntranceLog()
    let services: AppServices
    /// True when the title page shows these streams in place of its details: no scroll view, backdrop, title or header of its own, since
    /// the page above it has them.
    let isEmbedded: Bool
    /// The episode's score, shown right after its season and episode in the heading, with the IMDb mark as its card has it. Nil for a
    /// film, or while the score is not known.
    let episodeScore: DetailViewModel.EpisodeScore?
    /// Embedded on a series' page: the episodes before and after this one, which the header's switcher steps to. Nil keeps the heading text.
    let episodeSwitcher: EpisodeSwitcher?
    /// The title page's tint, shared by Play and the episode arrows.
    let playColourHex: String?
    /// False draws nothing yet: the picker is on the page and loading, and the page shows it once `onReady` has been called.
    private let isRevealed: Bool
    /// Embedded only: takes the streams away and shows the title's details again, as Escape does on Mac. Back leaves the title's page, so
    /// it is not a way back to the details.
    let onClose: (() -> Void)?
    /// Called once every addon has answered, with whether any actual stream cards can be shown.
    private let onReady: ((Bool) -> Void)?
    /// Embedded on Mac: scrolls the title page to a row the keyboard is on. The page's scroll view holds the rows, not the picker.
    private let scrollToRow: ((AnyHashable) -> Void)?
    /// True for a picker that is never shown: Home's Continue Watching starts a card's stream through one.
    let isHeadless: Bool
    /// Told once the automatic start on opening (Auto Pick's switch on) has started a stream (true), or has nothing to start (false).
    let onAutomaticStart: ((Bool) -> Void)?
    /// Told when a stream has been handed to another player app and the system opened it.
    let onOpenedInPlayer: ((ExternalPlayer) -> Void)?
    /// True for a picker that starts the best stream on opening whatever Auto Pick's switch says: a poster held to play it.
    private let forcesAutomaticStart: Bool
    /// A one-off player chosen from the title's Play context menu.
    let preferredAutomaticPlayer: ExternalPlayer?
    /// False shows the choices and starts nothing, whatever Auto Pick's switch says: Play's Stream Selector, and recovery, which must not
    /// retry at once the stream that just failed.
    private let allowsAutomaticStart: Bool
    /// A quality chosen for this play from a hold menu (Highest Quality, Data Saver). Nil follows Settings.
    let quality: PlayQuality?
    /// Auto Pick is still choosing or preparing; keep the selector hidden throughout.
    @State var awaitsAutomaticStart = false
    @Environment(\.openURL) var openURL
    @Environment(AppRouter.self) var router
    @Environment(\.layoutMetrics) var metrics
    @Environment(\.isLandscape) var isLandscape
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape
    #if targetEnvironment(macCatalyst)
    /// Closes a pushed picker, for Escape: the same as its back button.
    @Environment(\.dismiss) private var dismiss
    /// The row the arrow keys are on. Nil until the list takes the keyboard.
    @State var keyboardRow: KeyboardRow?
    /// The list holds the keyboard from the moment it shows, so the arrow keys work without a click first.
    @FocusState private var listHasFocus: Bool
    #endif
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `isPhoneLandscape` is also true on an iPad turned sideways, so the device is checked as well.
    private var isPhoneInLandscapeOnPhone: Bool { isPhoneLandscape && UIDevice.current.userInterfaceIdiom == .phone }
    /// A slight inset from each edge. The screens' page margin is zero, so the stream rows would otherwise run to the screen's edge.
    var streamMargin: CGFloat { metrics.contentMargin }

    init(request: StreamRequest, services: AppServices, isEmbedded: Bool = false, isRevealed: Bool = true, onClose: (() -> Void)? = nil,
         onReady: ((Bool) -> Void)? = nil, scrollToRow: ((AnyHashable) -> Void)? = nil, episodeScore: DetailViewModel.EpisodeScore? = nil,
         episodeSwitcher: EpisodeSwitcher? = nil, isHeadless: Bool = false, forcesAutomaticStart: Bool = false,
         onAutomaticStart: ((Bool) -> Void)? = nil, playColourHex: String? = nil, allowsAutomaticStart: Bool = true,
         preferredAutomaticPlayer: ExternalPlayer? = nil, onOpenedInPlayer: ((ExternalPlayer) -> Void)? = nil, quality: PlayQuality? = nil) {
        self.episodeScore = episodeScore
        self.quality = quality
        self.onOpenedInPlayer = onOpenedInPlayer
        self.episodeSwitcher = episodeSwitcher
        self.playColourHex = playColourHex
        self.isHeadless = isHeadless
        self.forcesAutomaticStart = forcesAutomaticStart
        self.preferredAutomaticPlayer = preferredAutomaticPlayer
        self.allowsAutomaticStart = allowsAutomaticStart
        self.onAutomaticStart = onAutomaticStart
        self.services = services
        self.isEmbedded = isEmbedded
        self.isRevealed = isRevealed
        self.onClose = onClose
        self.onReady = onReady
        self.scrollToRow = scrollToRow
        _model = State(initialValue: StreamPickerViewModel(request: request, services: services))
    }

    var body: some View {
        if isEmbedded {
            behaviour(list(scrollTo: scrollToRow).accessibilityIdentifier("streams.list"))
        } else {
            // The reader wraps the picker's own scroll view, which holds the rows, so the keyboard can scroll them (Mac), and an opened
            // section comes into view.
            ScrollViewReader { proxy in
                #if targetEnvironment(macCatalyst)
                let scrollTo: ((AnyHashable) -> Void)? = { proxy.scrollTo($0, anchor: .center) }
                #else
                let scrollTo: ((AnyHashable) -> Void)? = nil
                #endif
                behaviour(page(scrollTo: scrollTo))
                    .environment(\.pageReveal, proxy.pageReveal)
            }
        }
    }

    /// The pushed picker's page: its own scroll view, with the list in it.
    private func page(scrollTo: ((AnyHashable) -> Void)?) -> some View {
        ScrollView {
            list(scrollTo: scrollTo)
        }
        .scrollIndicators(.visible, axes: .vertical)
        .scrollIndicatorsFlash(onAppear: true)
        // The last card scrolls clear of the tab bar and the mini player: the scroll content's bottom margin, not padding
        // inside it.
        .contentMargins(.bottom, Theme.Spacing.xxl, for: .scrollContent)
        // A phone in landscape has no navigation bar here: the list starts below the glass Back drawn above Home (see `RootTabView`).
        .contentMargins(.top, isPhoneInLandscapeOnPhone ? LandscapeTabBarState.backClearance : 0, for: .scrollContent)
        .trackLandscapeTabScroll()
        // The glow is a layer of the page, not of the list: it stays put under the navigation bar while the streams scroll over it.
        .background(alignment: .top) { ambientBackdrop }
        .screenBackground()
        // The title is the header's; the navigation title stays set for VoiceOver and the screen's name, but is not drawn twice.
        .downloadErrors(services.downloads)
        .navigationTitle(model.request.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .pageNavigationBar(hidden: isPhoneInLandscapeOnPhone)
        .accessibilityIdentifier("streams.list")
    }

    /// The list the page shows. On Mac it also takes the keyboard (see `keyboardNavigated`), unless it is a picker that is never shown;
    /// on iPhone it is the rows alone.
    @ViewBuilder
    private func list(scrollTo: ((AnyHashable) -> Void)?) -> some View {
        #if targetEnvironment(macCatalyst)
        if !isHeadless {
            keyboardNavigated(content, scrollTo: scrollTo)
        } else {
            content
        }
        #else
        content
        #endif
    }

    /// A row of the list, by the addon section it sits in and its stream. Two addons can offer the same stream, so it can appear in two
    /// sections; the stream alone would not say which row the keyboard is on.
    struct KeyboardRow: Hashable {
        let addon: UUID
        let stream: RankedStream.ID
    }

    /// Mac: marks the row the arrow keys are on, and gives it the id the list scrolls to. iPhone: the row as it is. A card that has an
    /// edge of its own (`hasEdge`: Best match, a service or a disc) gets no ring: its edge is drawn bolder instead (see `streamButton`),
    /// so a card never has two outlines.
    @ViewBuilder
    func keyboardMarked(_ row: some View, in addon: UUID, stream: RankedStream.ID, hasEdge: Bool) -> some View {
        #if targetEnvironment(macCatalyst)
        row
            .overlay {
                if !hasEdge, keyboardRow == KeyboardRow(addon: addon, stream: stream) {
                    RoundedRectangle(cornerRadius: StreamCardMetrics.cornerRadius * metrics.cornerScale(for: .panels), style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .id(KeyboardRow(addon: addon, stream: stream))
        #else
        row
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// Mac: the list takes the keyboard. Down and up move a highlight through the streams and scroll it into view, Return chooses the
    /// highlighted stream, and Escape closes the picker. Left and right step to the episode before or after, as the switcher's chevrons
    /// do. Only the highlight changes, so a click works as it did.
    private func keyboardNavigated<Rows: View>(_ rows: Rows, scrollTo: ((AnyHashable) -> Void)?) -> some View {
        rows
            .focusable()
            .focused($listHasFocus)
            .focusEffectDisabled()
            // A pushed picker takes the keyboard as it shows. An embedded one waits until its streams are shown, so the title page does not
            // move while it is still an empty placeholder under Play.
            .onAppear { if !isEmbedded || isRevealed { listHasFocus = true } }
            .onChange(of: isRevealed) { _, revealed in
                if revealed { listHasFocus = true }
            }
            .onKeyPress(.downArrow) { moveKeyboardSelection(by: 1) }
            .onKeyPress(.upArrow) { moveKeyboardSelection(by: -1) }
            .onKeyPress(.return) { chooseKeyboardStream() }
            .onKeyPress(.escape) { closeFromKeyboard() }
            .onKeyPress(.leftArrow) { stepEpisodeFromKeyboard(to: episodeSwitcher?.previous) }
            .onKeyPress(.rightArrow) { stepEpisodeFromKeyboard(to: episodeSwitcher?.next) }
            .onChange(of: keyboardRow) { _, row in
                guard let row, let scrollTo else { return }
                withAnimation(.snappy(duration: 0.25)) { scrollTo(AnyHashable(row)) }
            }
    }

    /// The rows in the order the list shows them, each with its stream.
    private var keyboardOrder: [(row: KeyboardRow, stream: RankedStream)] {
        visibleSections.flatMap { section in
            section.streams.map { (KeyboardRow(addon: section.addon.id, stream: $0.id), $0) }
        }
    }

    /// Moves the highlight one row up or down, in the order the list shows them. From nothing, Down takes the first row and Up the last.
    private func moveKeyboardSelection(by step: Int) -> KeyPress.Result {
        let rows = keyboardOrder
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.row == keyboardRow } ?? (step > 0 ? -1 : rows.count)
        keyboardRow = rows[min(max(current + step, 0), rows.count - 1)].row
        return .handled
    }

    /// Chooses the highlighted stream, as a tap on its row does.
    private func chooseKeyboardStream() -> KeyPress.Result {
        guard let row = keyboardRow, let item = keyboardOrder.first(where: { $0.row == row })?.stream else { return .ignored }
        select(item)
        return .handled
    }

    /// Steps to the episode before or after, as a chevron does. Ignored without a switcher, or with no episode there.
    private func stepEpisodeFromKeyboard(to request: StreamRequest?) -> KeyPress.Result {
        guard let episodeSwitcher, let request else { return .ignored }
        episodeSwitcher.step(request)
        return .handled
    }

    /// Closes the embedded picker through its own close, or a pushed picker by popping it.
    private func closeFromKeyboard() -> KeyPress.Result {
        if let onClose { onClose() } else { dismiss() }
        return .handled
    }
    #endif

    /// The picker's rows. Pushed, the first row is the picker's own header; embedded, it is the lighter header, since the page above
    /// already has the poster and the title.
    private var content: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if isRevealed && model.hasLoaded && (!model.autoPlaysBestStream || !allowsAutomaticStart) {
                // The text and Auto Pick sit one step apart, as the title's text and its Play button do, not a stack gap apart.
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    // A film's embedded header is empty until the streams load, so it takes no step above Auto Pick.
                    if isEmbedded {
                        if embeddedHeaderShowsText { embeddedHeader }
                    } else {
                        header
                    }
                    playBestButton
                }
                .headerColumn(headerWidth)
                BestEditionView(model: model, rowHeight: autoPickButtonHeight)
                    .padding(.horizontal, streamMargin)
                    .headerColumn(headerWidth)
                addonChips
                    .padding(.horizontal, streamMargin)
                    .headerColumn(headerWidth)
                resolutionChips
                    .padding(.horizontal, streamMargin)
                    .headerColumn(headerWidth)
                failures.headerColumn(headerWidth)
                emptyState.headerColumn(headerWidth)
                loadingRows
                groups(recommended: model.recommendedStream)
                links.headerColumn(headerWidth)
                hiddenHint.headerColumn(headerWidth)
            }
        }
        .frame(maxWidth: columnWidth)
        #if targetEnvironment(macCatalyst)
        // Embedded in a title page the picker keeps the page's leading edge, so its rows line up with the page's text. Pushed, it centres.
        .frame(maxWidth: .infinity, alignment: isEmbedded ? .leading : .center)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }

    /// What the picker does once it is on screen: loading, the sheets and the alerts, and cleaning up when it leaves. The same whether
    /// it is pushed or embedded.
    private func behaviour(_ view: some View) -> some View {
        view
            // A picker that is never shown has no edition to show.
            .task { if !isHeadless { await model.findBestEdition() } }
            .task {
                // Asked once, here: routing hands streams to these players only, and the menus offer only these.
                model.setInstalledPlayers(Set(ExternalPlayer.allCases.filter(isInstalled)))
                model.automaticPlayerOverride = preferredAutomaticPlayer
                model.quality = quality
                await model.loadAutoPlayPreference()
                // The previous viewing session for this title, when the app was left or killed: its own stream resumes
                // (`automaticStartCandidate`), and a stream another player played is handed its position and choices.
                await model.loadSessionResume()
                // A picker that is never shown is done once it has started a stream: shown again after the player closes, it does not load.
                if !model.hasLoaded, !isHeadless || !hasSelectedManually {
                    let settings = await services.settings.load()
                    let startsAutomatically = allowsAutomaticStart && (settings.autoPlayBestStream || forcesAutomaticStart)
                    model.startsAutomaticallyAnyway = forcesAutomaticStart
                    if startsAutomatically, !hasSelectedManually { awaitsAutomaticStart = true }
                    if startsAutomatically { await model.loadForAutomaticSelection() } else { await model.load() }
                    // The picker was left while it loaded: nothing starts, and no Auto Pick is left waiting on a load that was called off.
                    guard !Task.isCancelled else { return }
                    if startsAutomatically, !hasSelectedManually {
                        // All automatic launches take the same ranked route as normal Play:
                        // Blusion by default, Infuse only when the saved preference calls for it.
                        let candidate: RankedStream?
                        if let preferredAutomaticPlayer {
                            candidate = model.bestHandoffCandidate(for: preferredAutomaticPlayer)
                        } else {
                            candidate = model.automaticStartCandidate
                        }
                        if let candidate {
                            select(candidate, automatically: true)
                        } else {
                            finishAutomaticStart(started: false)
                        }
                    } else {
                        finishAutomaticStart(started: false)
                    }
                } else if awaitsAutomaticStart, !isHeadless {
                    // Left while Auto Pick was still choosing, after every addon had answered: its choice was called off, so the
                    // list shows on return rather than Play spinning on.
                    finishAutomaticStart(started: false)
                }
            }
            // Empty results must reach the title page even when Auto Pick keeps the selector hidden.
            .onChange(of: isReady && !awaitsAutomaticStart && (!model.autoPlaysBestStream || !allowsAutomaticStart || model.addonSections.isEmpty),
                      initial: true) { _, ready in
                guard ready else { return }
                onReady?(!model.addonSections.isEmpty)
            }
            .onDisappear {
                autoPickTask?.cancel()
                backgroundLoadTask?.cancel()
                model.cancelLoading()
                isOpeningPlayer = false
                streamPreparation = .idle
                preparingViaAutoPick = false
                // A player readied for a stream nobody played goes with the picker. One the player screen took is no longer held here.
                discardPrepared()
            }
            // The first stream listed starts loading in the background the moment it arrives, in case it is the one played.
            .onChange(of: model.addonSections.first?.streams.first?.id) { startBackgroundLoad() }
            .onChange(of: availableAddons, initial: true) { _, addons in
                if !addons.isEmpty { Self.lastAvailableAddons = addons }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { isOpeningPlayer = false }
                if phase == .background, plan == nil {
                    cancelPreparation()
                    backgroundLoadTask?.cancel()
                    discardPrepared()
                    streamPreparation = .idle
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .playbackHandoffDidFinish)) { notification in
                guard let receipt = notification.object as? PlaybackHandoffReceipt,
                      receipt.handoff.request.identity == model.request.identity else { return }
                isOpeningPlayer = false
                if let itemID = pendingSaves.removeValue(forKey: receipt.handoff.id), case .finished = receipt.result {
                    savedStreams.insert(itemID)
                }
            }
            .sheet(item: $expandedDetails) { item in
                NavigationStack {
                    ScrollView {
                        Text(item.stream.description ?? item.title)
                            .appFont(.small)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .scrollIndicators(.visible, axes: .vertical)
                    .scrollIndicatorsFlash(onAppear: true)
                    .navigationTitle("Stream Details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { expandedDetails = nil } } }
                }
                .preferredColorScheme(.dark)
            }
            .fullScreenCover(item: $plan, onDismiss: { presentedPlayer = nil }) {
                PlayerScreen(plan: $0, services: services, prepared: presentedPlayer)
            }
            .alert("Ghost mode is on", isPresented: $ghostBlocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This stream only opens in another app, which keeps its own history. Pick another stream, or turn ghost mode off in Settings.")
            }
            .alert("This format isn't supported yet", isPresented: isShowingUnsupported, presenting: unsupported) { item in
                if let player = model.alternativePlayers(for: item).first {
                    Button("Open in \(player.displayName)") { openIn(player, item) }
                }
                if let next = model.nextPlayable(after: item), next.id != item.id {
                    Button("Try the next stream") { select(next) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text(unsupportedMessage(for: item))
            }
            .alert("\(missing?.player.displayName ?? "Player") isn't installed", isPresented: isShowingMissing,
                   presenting: missing) { pending in
                if let url = pending.player.appStoreURL {
                    Button("Get \(pending.player.displayName)") { openURL(url) }
                }
                if model.inAppChoice(for: pending.item) != nil {
                    Button("Play in Blusion") { playInBlusion(pending.item) }
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    /// Every addon has answered (with streams, with nothing, or with a failure). Until then the title page keeps its details and Play
    /// spins. A movie's first addon often answers with many streams at once, so revealing at a stream count dropped a movie's details
    /// at once while its other addons were still loading; waiting for every addon treats movies and episodes alike.
    private var isReady: Bool { model.hasLoaded && !model.listing.isLoading }

    #if targetEnvironment(macCatalyst)
    #endif
}

/// The episodes either side of a picker's own, for the switcher in its header, and what a step does: the page loads that episode's
/// streams in place. Each is nil when there is no episode to go to.
struct EpisodeSwitcher {
    let previous: StreamRequest?
    let next: StreamRequest?
    let step: (StreamRequest) -> Void
}

/// A hand-off that could not start because its player app is not installed.
struct MissingPlayer {
    let player: ExternalPlayer
    let item: RankedStream
}

extension View {
    /// Keeps a part of the picker to the header's width on a Mac (see `StreamPickerView.headerWidth`), from the leading edge.
    @ViewBuilder
    func headerColumn(_ width: CGFloat?) -> some View {
        if let width {
            frame(maxWidth: width, alignment: .leading)
        } else {
            self
        }
    }
}
#endif
