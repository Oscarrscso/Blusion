#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI
import UIKit

extension StreamPickerView {
    // MARK: failures and empty states

    @ViewBuilder
    var failures: some View {
        if !model.listing.failures.isEmpty {
            InlineErrorView(failureText) { Task { await model.retry() } }
                .accessibilityIdentifier("streams.failures")
                .padding(.horizontal, streamMargin)
        }
    }

    private var failureText: String {
        model.listing.failures.map { "\($0.addon.name): \($0.error.shortDescription)" }.joined(separator: "\n")
    }

    @ViewBuilder
    var emptyState: some View {
        if model.nobodyCanAnswer {
            EmptyStateView("No stream addons", systemImage: "puzzlepiece.extension",
                           message: "Add a stream addon in Settings to watch this title.",
                           actionTitle: "Open Addons", action: { router.showAddons() })
                .padding(.horizontal, streamMargin)
                .accessibilityIdentifier("streams.nobody")
        } else if model.isOffline {
            OfflineBanner()
                .padding(.horizontal, streamMargin)
        } else if model.showsNothingFound {
            EmptyStateView("No streams found", systemImage: "film.stack", message: "Your addons have nothing for this title.")
                .padding(.horizontal, streamMargin)
                .accessibilityIdentifier("streams.none")
        }
    }

    @ViewBuilder
    var loadingRows: some View {
        if model.isLoading && model.listing.isEmpty {
            #if targetEnvironment(macCatalyst)
            StreamRowsSkeleton(heights: Self.lastStreamCardHeights[isLandscape] ?? [:], columns: Self.macCardColumns)
                .padding(.horizontal, streamMargin)
            #else
            StreamRowsSkeleton(heights: Self.lastStreamCardHeights[isLandscape] ?? [:])
                .padding(.horizontal, streamMargin)
            #endif
        }
    }

    // MARK: streams

    /// `recommended` is the stream Auto Pick would start; it alone carries the Best match mark.
    func groups(recommended: RankedStream?) -> some View {
        // Each card's place counted across every visible section from the top, so the entrance runs down the whole list. A stream id
        // repeated in a later section keeps its first place.
        let order = Dictionary(visibleSections.flatMap(\.streams).enumerated().map { ($1.id, $0) },
                               uniquingKeysWith: { first, _ in first })
        return ForEach(visibleSections) { section in
            Section {
                #if targetEnvironment(macCatalyst)
                // The cards fill the page in columns, read across and then down; the arrow keys still step through them in that order.
                LazyVGrid(columns: Self.macCardColumns, alignment: .leading, spacing: Theme.Spacing.m) {
                    streamCards(in: section, recommended: recommended, order: order)
                }
                .padding(.horizontal, streamMargin)
                #else
                streamCards(in: section, recommended: recommended, order: order)
                #endif
            } header: {
                // One addon chosen: the filter above already names it.
                if chosenAddon == nil, model.addonSections.count > 1 { sectionTitle(section).padding(.horizontal, streamMargin) }
            }
        }
    }

    private func streamCards(in section: StreamPickerViewModel.AddonSection, recommended: RankedStream?,
                             order: [RankedStream.ID: Int]) -> some View {
        ForEach(section.streams) { item in
            let isRecommended = item.id == recommended?.id
            let card = keyboardMarked(streamButton(item, isRecommended: isRecommended, order: order[item.id] ?? 0,
                                                   isKeyboardFocused: isKeyboardRow(section.addon.id, item.id)),
                                      in: section.addon.id, stream: item.id, hasEdge: isRecommended || StreamLook(item.quality) != .plain)
            #if targetEnvironment(macCatalyst)
            card
            #else
            card.padding(.horizontal, streamMargin)
            #endif
        }
    }

    /// Whether the arrow keys are on this row. Never on iPhone, which has none.
    private func isKeyboardRow(_ addon: UUID, _ stream: RankedStream.ID) -> Bool {
        #if targetEnvironment(macCatalyst)
        keyboardRow == KeyboardRow(addon: addon, stream: stream)
        #else
        false
        #endif
    }

    /// The addon's name over its streams, with how many it gave: "Torrentio · 12".
    private func sectionTitle(_ section: StreamPickerViewModel.AddonSection) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(section.addon.name)
                .appFont(.headline)
            Text("\(section.streams.count)")
                .appFont(.captionStrong)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.surfaceStrong, in: ScaledCapsule(scale: metrics.cornerScale(for: .panels)))
        }
        .padding(.top, Theme.Spacing.s)
        .padding(.leading, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Links to web pages: a quiet group at the bottom, since they leave the app rather than play. Its cards are the stream cards, so the
    /// group has no background of its own.
    @ViewBuilder
    var links: some View {
        if !model.links.isEmpty {
            PageRevealReader { reveal in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        // Opened, the notes come into view, as a rating's reviews do.
                        Haptics.play(.buttons)
                        withAnimation(.snappy(duration: 0.25)) { isNotesExpanded.toggle() }
                        if isNotesExpanded { reveal?.show(Self.notesRevealID) }
                    } label: {
                        Text("Notes from your addons")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.hoverPlain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(isNotesExpanded ? "Expanded" : "Collapsed")
                    if isNotesExpanded {
                        VStack(spacing: Theme.Spacing.m) {
                            ForEach(model.links) { item in streamButton(item, isRecommended: false, order: 8) }
                        }
                        .padding(.top, Theme.Spacing.s)
                    }
                }
                .id(Self.notesRevealID)
            }
            .appFont(style: .subheadline, weight: .medium, role: .interface)
            .padding(.horizontal, streamMargin)
        }
    }

    private static let notesRevealID = "streams.notes"

    /// One stream as a card on the title page's surface: the top plays it, the technical details fold away underneath. `order` is the
    /// card's place in the list, which sets when its entrance animation starts. `isKeyboardFocused` (Mac) draws its edge bolder.
    private func streamButton(_ item: RankedStream, isRecommended: Bool, order: Int, isKeyboardFocused: Bool = false) -> some View {
        let look = StreamLook(item.quality)
        let isPreparing = activePreparationItemID == item.id
        let failure = streamPreparation.failure(for: item.id)
        let preparation = isPreparing ? prepared?.player.preparationProgress : failure?.progress
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                // A swipe that travelled across the card ends as a touch-up here too. It plays nothing.
                guard !SwipeRecord.latest.isSwipe(at: ContinuousClock.now) else { return }
                select(item)
            } label: {
                // A stream Blusion plays has its one play button; saving it to another player is in its menu. A stream another app
                // plays keeps the bookmark and download under its mark.
                StreamRow(item: item, isBest: isRecommended, isRemux: item.quality.isRemux,
                          savesToPlayer: savesUnderMark(item),
                          downloadsToPlayer: savesUnderMark(item),
                          downloadsNatively: true,
                          isPreparing: isPreparing,
                          preparation: preparation,
                          preparationBeganAt: isPreparing ? readyingBeganAt : failure?.beganAt,
                          preparationEndedAt: failure?.endedAt)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard order < 3, height > 0, preparation == nil else { return }
                        // Include the collapsed footer, regardless of whether this card's details are currently expanded.
                        Self.lastStreamCardHeights[isLandscape, default: [:]][order] = height + 1 + Theme.Spacing.m * 2
                            + UIFont.preferredFont(forTextStyle: .footnote).lineHeight.rounded(.up)
                    }
            }
            // On a Mac one hover effect: the card's own highlight, without the system's on top of it. iPad keeps both, as before.
            .buttonStyle(PressableCardStyle(lifts: false, addsSystemHighlight: StreamCardMetrics.addsSystemHighlight, showsFocus: false))
            .contextMenu { contextActions(for: item) }
            .overlayPreferenceValue(StreamNativeDownloadSlotKey.self) { slot in
                if let slot {
                    GeometryReader { proxy in
                        NativeDownloadButton(manager: services.downloads, item: services.downloads?.item(forStream: item.id),
                                             isLoading: services.downloads?.enqueueing.contains(item.id) == true,
                                             isAvailable: services.downloads?.item(forStream: item.id) != nil
                                                 || DownloadEligibility.container(for: item, config: model.listing.config) != nil,
                                             size: item.route.isPlayable ? StreamCardMetrics.playButtonSize : StreamCardMetrics.markSize,
                                             matchesStream: true) {
                            Task { await services.downloads?.enqueue(item, request: model.request) }
                        }
                        .position(x: proxy[slot].midX, y: proxy[slot].midY)
                        .accessibilityIdentifier("stream.nativeDownload.button")
                    }
                }
            }
            .task { await services.downloads?.bindStream(item, request: model.request) }
            .accessibilityIdentifier("stream.row.\(item.title)")
            .accessibilityHint(hint(for: item))
            // A card that opens in another player has a bookmark under its mark, set in the room the card keeps for it.
            .overlayPreferenceValue(StreamSaveSlotKey.self) { slot in
                if let slot, savesUnderMark(item), let player = model.savingPlayer(for: item) {
                    GeometryReader { proxy in
                        StreamSaveButton(player: player, isSaved: savedStreams.contains(item.id)) { save(item, to: player) }
                            .position(x: proxy[slot].midX, y: proxy[slot].midY)
                            .accessibilityIdentifier("stream.save.\(item.title)")
                    }
                }
            }
            .overlayPreferenceValue(StreamDownloadSlotKey.self) { slot in
                if let slot, savesUnderMark(item), let player = model.savingPlayer(for: item) {
                    GeometryReader { proxy in
                        StreamSaveButton(player: player, isSaved: false, isDownload: true) {
                            save(item, to: player, download: true)
                        }
                        .position(x: proxy[slot].midX, y: proxy[slot].midY)
                        .accessibilityIdentifier("stream.download.\(item.title)")
                    }
                }
            }
            StreamTechnicalDetails(item: item)
        }
        .cardSurface(cornerRadius: StreamCardMetrics.cornerRadius)
        .streamLookGlow(look)
        .clipShape(RoundedRectangle(cornerRadius: StreamCardMetrics.cornerRadius * metrics.cornerScale(for: .panels), style: .continuous))
        .overlay {
            if isRecommended {
                RoundedRectangle(cornerRadius: StreamCardMetrics.cornerRadius * metrics.cornerScale(for: .panels), style: .continuous)
                    .strokeBorder(Theme.brandGradient, lineWidth: isKeyboardFocused ? 3 : 1.5)
                    .brightness(isKeyboardFocused ? 0.3 : 0)
                    .allowsHitTesting(false)
            }
        }
        // The Best match keeps its brand edge; the card's service or disc edge shows on every other stream.
        .streamLookEdge(isRecommended ? .plain : look, isEmphasised: isKeyboardFocused)
        .streamCardEntrance(id: AnyHashable(item.id), order: order, log: entranceLog)
    }

    @ViewBuilder
    private func contextActions(for item: RankedStream) -> some View {
        if DownloadEligibility.container(for: item, config: model.listing.config) != nil, services.downloads != nil {
            Button("Download", systemImage: "arrow.down.circle") {
                Haptics.play(.buttons)
                Task { await services.downloads?.enqueue(item, request: model.request) }
            }.accessibilityIdentifier("stream.nativeDownload")
        }
        if item.stream.description != nil {
            Button("Show Details", systemImage: "info.circle") { expandedDetails = item }
        }
        ForEach(model.alternativePlayers(for: item), id: \.self) { player in
            Button("Open in \(player.displayName)", systemImage: "arrow.up.forward.app") { openIn(player, item) }
        }
        if item.route.handoffTarget != nil, model.inAppChoice(for: item) != nil {
            Button("Play in Blusion", systemImage: "play.circle") { playInBlusion(item) }
        }
        // The bookmark and download a stream Blusion plays no longer carry on its card.
        if item.route.isPlayable, let player = model.savingPlayer(for: item) {
            Button(savedStreams.contains(item.id) ? "Saved to \(player.displayName)" : "Save to \(player.displayName)",
                   systemImage: savedStreams.contains(item.id) ? "bookmark.fill" : "bookmark") { save(item, to: player) }
                .disabled(savedStreams.contains(item.id))
            Button("Download in \(player.displayName)", systemImage: "arrow.down") { save(item, to: player, download: true) }
        }
    }

    /// Whether the card carries the bookmark and download under its mark: only a stream another player app plays.
    private func savesUnderMark(_ item: RankedStream) -> Bool {
        !item.route.isPlayable && model.savingPlayer(for: item) != nil
    }

    @ViewBuilder
    var hiddenHint: some View {
        if !model.listing.hidden.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(model.listing.hidden) { note in
                    Label(note.text, systemImage: "eye.slash")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, streamMargin)
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
}
#endif
