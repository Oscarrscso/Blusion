#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

/// One title's streams. The header says what is being picked and how far along it is, the best stream is the one main action, and each
/// addon's streams follow as rows of their own. Links to web pages come last. A stream plays in Blusion or, when the viewer chose that
/// player, opens in another app.
struct StreamPickerView: View {
    @State private var model: StreamPickerViewModel
    @State private var plan: PlaybackPlan?
    @State private var expandedDetails: RankedStream?
    /// The sharpness the chips narrow the list to; nil shows every stream.
    @State private var resolutionFilter: Band?
    /// A stream whose format Blusion can't play: the alert offers another player, or the next stream.
    @State private var unsupported: RankedStream?
    /// A hand-off whose player app is not installed: the alert offers its App Store page, or playing the stream in Blusion.
    @State private var missing: MissingPlayer?
    private let services: AppServices
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics

    init(request: StreamRequest, services: AppServices) {
        self.services = services
        _model = State(initialValue: StreamPickerViewModel(request: request, services: services))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: metrics.isRegular ? .leading : .center, spacing: Theme.Spacing.l) {
                header
                playBestButton
                resolutionChips
                failures
                emptyState
                loadingRows
                groups
                links
                hiddenHint
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        // The glow is a layer of the page, not of the list: it stays put under the navigation bar while the streams scroll over it.
        .background(alignment: .top) { ambientBackdrop }
        .screenBackground()
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The title is the header's; the navigation title stays set for VoiceOver and the screen's name, but is not drawn twice.
        .navigationTitle(model.request.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .accessibilityIdentifier("streams.list")
        .task {
            // Asked once, here: routing hands streams to these players only, and the menus offer only these.
            model.setInstalledPlayers(Set(ExternalPlayer.allCases.filter(isInstalled)))
            if !model.hasLoaded {
                await model.load()
                let settings = await services.settings.load()
                if settings.autoPlayBestStream, model.listing.best != nil { playBest() }
            }
        }
        .sheet(item: $expandedDetails) { item in
            NavigationStack {
                ScrollView {
                    Text(item.stream.description ?? item.title)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Stream Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { expandedDetails = nil } } }
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $plan) { PlayerScreen(plan: $0, services: services) }
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
        .alert("\(missing?.player.displayName ?? "Player") isn't installed", isPresented: isShowingMissing, presenting: missing) { pending in
            if let url = pending.player.appStoreURL {
                Button("Get \(pending.player.displayName)") { openURL(url) }
            }
            if model.inAppChoice(for: pending.item) != nil {
                Button("Play in Blusion") { playInBlusion(pending.item) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: header

    /// The title's own artwork, stretched, blurred and faded into the page behind the header: the picker belongs to the title it opened
    /// from, the way the TV app tints a screen with its poster. It runs up under the navigation bar.
    @ViewBuilder
    private var ambientBackdrop: some View {
        if let poster = model.request.poster {
            ArtworkImage(url: poster, maxPixelSize: 240)
                .frame(height: 520)
                .scaleEffect(1.4)
                .blur(radius: 46)
                .saturation(1.25)
                .opacity(0.5)
                .overlay { BottomFade(length: 0.85) }
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Poster, then what is being picked: for an episode "S1 · E3" over its name, for a film its year. On a phone it is centred, as
    /// the title page is; in a wide window it reads from the left.
    private var header: some View {
        let leading = metrics.isRegular
        return VStack(alignment: leading ? .leading : .center, spacing: Theme.Spacing.m) {
            if let poster = model.request.poster {
                PosterImage(url: poster, title: model.request.title)
                    .frame(width: leading ? 120 : 92)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                    .padding(.top, Theme.Spacing.s)
            }
            VStack(alignment: leading ? .leading : .center, spacing: Theme.Spacing.xs) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(Theme.Typography.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(model.request.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(leading ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                status
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
        .padding(.horizontal, metrics.pageMargin)
    }

    /// "S1 · E3" for an episode, the release year for a film.
    private var eyebrow: String? {
        if let season = model.request.season, let episode = model.request.episode { return "S\(season) · E\(episode)" }
        return model.request.year
    }

    @ViewBuilder
    private var status: some View {
        if model.isLoading {
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                    .controlSize(.small)
                Text(waitingText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("streams.loading")
        } else if !model.addonSections.isEmpty {
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var waitingText: String {
        "Checking for streams…"
    }

    private var summary: String {
        let streams = model.addonSections.reduce(0) { $0 + $1.streams.count }
        let addons = model.addonSections.count
        return "\(streams) \(streams == 1 ? "stream" : "streams") from \(addons) \(addons == 1 ? "addon" : "addons")"
    }

    // MARK: the main action

    /// The white capsule that starts the best stream, and under it one grey line saying which stream that is, so the choice is
    /// never a surprise.
    @ViewBuilder
    private var playBestButton: some View {
        if let best = model.listing.best {
            VStack(spacing: Theme.Spacing.s) {
                Button { playBest() } label: {
                    Label(playBestTitle(for: best), systemImage: "play.fill")
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("streams.playBest")
                if let detail = playBestDetail(for: best) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: metrics.isRegular ? 380 : .infinity)
            .frame(maxWidth: .infinity, alignment: metrics.isRegular ? .leading : .center)
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    /// "Play Best" in Blusion, "Play Best in Infuse" for a hand-off.
    private func playBestTitle(for best: RankedStream) -> String {
        var title = "Play Best"
        if let target = best.route.handoffTarget { title += " in \(target.player.displayName)" }
        return title
    }

    /// "4K Dolby Vision · 76.5 GB": the picture and the size of the stream Play Best chose.
    private func playBestDetail(for best: RankedStream) -> String? {
        var parts: [String] = []
        let picture = pictureLabel(best)
        if !picture.isEmpty { parts.append(picture) }
        if let size = best.quality.sizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: filtering

    /// Sharpness bands the chips filter by. Anything under 720 lines is one band, "SD".
    private enum Band: Int, CaseIterable {
        case uhd = 2160, fullHD = 1080, hd = 720, sd = 480

        init(_ resolution: Int) {
            self = resolution >= 2160 ? .uhd : resolution >= 1080 ? .fullHD : resolution >= 720 ? .hd : .sd
        }

        var title: String {
            switch self {
            case .uhd: "4K"
            case .fullHD: "1080p"
            case .hd: "720p"
            case .sd: "SD"
            }
        }
    }

    private func band(of item: RankedStream) -> Band? { item.quality.resolution.map(Band.init) }

    /// The bands the streams listed so far fall in, sharpest first.
    private var availableBands: [Band] {
        let present = Set(model.addonSections.flatMap(\.streams).compactMap(band(of:)))
        return Band.allCases.filter(present.contains)
    }

    /// The sections with only the chosen band's streams. A band that has gone (a refresh found fewer streams) falls back to all.
    private var visibleSections: [StreamPickerViewModel.AddonSection] {
        guard let band = resolutionFilter, availableBands.contains(band) else { return model.addonSections }
        return model.addonSections.compactMap { section in
            let streams = section.streams.filter { self.band(of: $0) == band }
            return streams.isEmpty ? nil : StreamPickerViewModel.AddonSection(addon: section.addon, streams: streams)
        }
    }

    /// "All  4K  1080p  720p": shown once the list holds more than one sharpness, since a single band has nothing to choose between.
    @ViewBuilder
    private var resolutionChips: some View {
        if availableBands.count > 1 {
            ChipRow {
                GlassChip("All", isSelected: resolutionFilter == nil || !availableBands.contains(resolutionFilter ?? .uhd)) {
                    withAnimation(.snappy) { resolutionFilter = nil }
                }
                ForEach(availableBands, id: \.self) { band in
                    GlassChip(band.title, isSelected: resolutionFilter == band) {
                        withAnimation(.snappy) { resolutionFilter = band }
                    }
                }
            }
            .accessibilityIdentifier("streams.filter")
        }
    }

    /// "4K HDR", "1080p", "4K Dolby Vision": the picture of a stream in words. Empty when the name said nothing about it.
    private func pictureLabel(_ item: RankedStream) -> String {
        var parts: [String] = []
        if let resolution = item.quality.resolutionLabel { parts.append(resolution) }
        if item.quality.isDolbyVision {
            parts.append("Dolby Vision")
        } else if item.quality.isHDR {
            parts.append("HDR")
        }
        return parts.joined(separator: " ")
    }

    // MARK: failures and empty states

    @ViewBuilder
    private var failures: some View {
        if !model.listing.failures.isEmpty {
            InlineErrorView(failureText) { Task { await model.retry() } }
                .accessibilityIdentifier("streams.failures")
                .padding(.horizontal, metrics.pageMargin)
        }
    }

    private var failureText: String {
        model.listing.failures.map { "\($0.addon.name): \($0.error.shortDescription)" }.joined(separator: "\n")
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.nobodyCanAnswer {
            EmptyStateView("No stream addons", systemImage: "puzzlepiece.extension",
                           message: "Add a stream addon in Settings to watch this title.",
                           actionTitle: "Open Addons", action: { router.showAddons() })
                .padding(.horizontal, metrics.pageMargin)
                .accessibilityIdentifier("streams.nobody")
        } else if model.isOffline {
            OfflineBanner()
        } else if model.showsNothingFound {
            EmptyStateView("No streams found", systemImage: "film.stack", message: "Your addons have nothing for this title.")
                .padding(.horizontal, metrics.pageMargin)
                .accessibilityIdentifier("streams.none")
        }
    }

    @ViewBuilder
    private var loadingRows: some View {
        if model.isLoading && model.listing.isEmpty {
            StreamRowsSkeleton()
                .padding(.horizontal, metrics.pageMargin)
        }
    }

    // MARK: streams

    private var groups: some View {
        ForEach(visibleSections) { section in
            VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
                if model.addonSections.count > 1 { sectionTitle(section) }
                ForEach(section.streams) { item in
                    streamButton(item)
                }
            }
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    /// The addon's name over its streams, with how many it gave: "Torrentio · 12".
    private func sectionTitle(_ section: StreamPickerViewModel.AddonSection) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(section.addon.name)
                .font(.subheadline.weight(.semibold))
            Text("\(section.streams.count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.surfaceStrong, in: Capsule())
        }
        .padding(.top, Theme.Spacing.xs)
        .padding(.leading, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Links to web pages: a quiet group at the bottom, since they leave the app rather than play.
    @ViewBuilder
    private var links: some View {
        if !model.links.isEmpty {
            DisclosureGroup("Notes from your addons") {
                VStack(spacing: Theme.Spacing.s + 2) {
                    ForEach(model.links) { item in streamButton(item) }
                }
                .padding(.top, Theme.Spacing.s)
            }
            .font(.subheadline.weight(.medium))
            .padding(Theme.Spacing.m + 2)
            .cardSurface()
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    private func streamButton(_ item: RankedStream) -> some View {
        Button {
            select(item)
        } label: {
            StreamRow(item: item, isBest: item.id == model.listing.best?.id)
        }
        .buttonStyle(PressableCardStyle())
        .contextMenu { contextActions(for: item) }
        .accessibilityIdentifier("stream.row.\(item.title)")
        .accessibilityHint(hint(for: item))
    }

    @ViewBuilder
    private func contextActions(for item: RankedStream) -> some View {
        if item.stream.description != nil {
            Button("Show Details", systemImage: "info.circle") { expandedDetails = item }
        }
        ForEach(model.alternativePlayers(for: item), id: \.self) { player in
            Button("Open in \(player.displayName)", systemImage: "arrow.up.forward.app") { openIn(player, item) }
        }
        if item.route.handoffTarget != nil, model.inAppChoice(for: item) != nil {
            Button("Play in Blusion", systemImage: "play.circle") { playInBlusion(item) }
        }
    }

    @ViewBuilder
    private var hiddenHint: some View {
        if !model.listing.hidden.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(model.listing.hidden) { note in
                    Label(note.text, systemImage: "eye.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, metrics.pageMargin)
            .accessibilityIdentifier("streams.hidden")
        }
    }

    private func hint(for item: RankedStream) -> String {
        switch item.route {
        case .native, .fallback: return "Plays in Blusion"
        case .handoff(let player, _): return "Opens in \(player.displayName)"
        case .external: return "Opens outside Blusion"
        case .unsupported: return "This format isn't supported yet"
        case .hidden: return ""
        }
    }

    // MARK: choosing

    private func select(_ item: RankedStream) {
        Task {
            guard let choice = await model.choose(item) else { return }
            present(choice, for: item)
        }
    }

    private func playBest() {
        guard let best = model.listing.best else { return }
        select(best)
    }

    private func openIn(_ player: ExternalPlayer, _ item: RankedStream) {
        Task {
            guard let choice = await model.handoffChoice(for: item, player: player) else { return }
            present(choice, for: item)
        }
    }

    private func playInBlusion(_ item: RankedStream) {
        guard let choice = model.inAppChoice(for: item) else { return }
        present(choice, for: item)
    }

    private func present(_ choice: StreamPickerViewModel.Choice, for item: RankedStream) {
        switch choice {
        case .play(let next):
            plan = next
        case .openExternal(let url):
            openURL(url)
        case .openInPlayer(let player, let link):
            openURL(link) { accepted in
                if !accepted { missing = MissingPlayer(player: player, item: item) }
            }
        case .unsupported:
            unsupported = item   // the alert offers the next playable stream, or another player
        }
    }

    // MARK: players and alerts

    /// Whether the player app is on this device. Its scheme is listed in LSApplicationQueriesSchemes, which is what lets the system answer.
    /// Only asked once per opening of the picker, never while a row or a menu is drawn.
    private func isInstalled(_ player: ExternalPlayer) -> Bool {
        guard let url = URL(string: "\(player.scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private func unsupportedMessage(for item: RankedStream) -> String {
        if let player = model.alternativePlayers(for: item).first {
            return "Blusion can't play this container or audio yet. \(player.displayName) can."
        }
        return "Blusion can't play this container or audio yet. Pick another stream."
    }

    private var isShowingUnsupported: Binding<Bool> {
        Binding(get: { unsupported != nil }, set: { if !$0 { unsupported = nil } })
    }

    private var isShowingMissing: Binding<Bool> {
        Binding(get: { missing != nil }, set: { if !$0 { missing = nil } })
    }
}

/// A hand-off that could not start because its player app is not installed.
private struct MissingPlayer {
    let player: ExternalPlayer
    let item: RankedStream
}
#endif
