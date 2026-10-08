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
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                playBestButton
                failures
                emptyState
                loadingRows
                groups
                links
                hiddenHint
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .screenBackground()
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

    private var header: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.l) {
            if let poster = model.request.poster {
                PosterImage(url: poster, title: model.request.title)
                    .frame(width: 60)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(model.request.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                status
            }
        }
        .padding(.horizontal, metrics.pageMargin)
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

    @ViewBuilder
    private var playBestButton: some View {
        if let best = model.listing.best {
            Button(playBestTitle(for: best)) { playBest() }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("streams.playBest")
                .padding(.horizontal, metrics.pageMargin)
        }
    }

    /// "Play Best · 4K HDR" in Blusion, "Play Best in Infuse · 4K HDR" for a hand-off.
    private func playBestTitle(for best: RankedStream) -> String {
        var title = "Play Best"
        if let target = best.route.handoffTarget { title += " in \(target.player.displayName)" }
        let picture = pictureLabel(best)
        return picture.isEmpty ? title : "\(title) · \(picture)"
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
        ForEach(model.addonSections) { section in
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if model.addonSections.count > 1 { SectionHeader(section.addon.name) }
                ForEach(section.streams) { item in
                    streamButton(item)
                    Divider()
                }
            }
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    /// Links to web pages: a quiet group at the bottom, since they leave the app rather than play.
    @ViewBuilder
    private var links: some View {
        if !model.links.isEmpty {
            DisclosureGroup("Notes from your addons") {
                ForEach(model.links) { item in streamButton(item) }
            }
            .font(.footnote)
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    private func streamButton(_ item: RankedStream) -> some View {
        Button {
            select(item)
        } label: {
            StreamRow(item: item)
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
