#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Home's Blusion TV widget: what is on each channel now, Blusion's own channels from the shows you like first, on Continue Watching's
/// cards, then a card for a new channel. A tap joins the
/// programme live, where the broadcast has got to; the heading opens the guide.
struct BlusionTVRow: View {
    let services: AppServices
    let title: String
    let hideTitle: Bool
    @State private var model: BlusionTVModel
    @State private var editing: TVChannel?
    @State private var deleting: TVChannel?
    @State private var failure: String?
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics

    init(services: AppServices, title: String = "Blusion TV", hideTitle: Bool = false) {
        self.services = services
        self.title = title
        self.hideTitle = hideTitle
        _model = State(initialValue: BlusionTVModel.shared(services: services))
    }

    private enum Card: Identifiable {
        case channel(TVChannel)
        case new

        var id: String {
            switch self {
            case .channel(let channel): channel.id.uuidString
            case .new: "new"
            }
        }
    }

    var body: some View {
        MediaRow(title.isEmpty ? "Blusion TV" : title, hideTitle: hideTitle, onSeeAll: openGuide,
                 items: model.allChannels.map(Card.channel) + [.new], id: \.id, aspect: .wide, cardWidth: metrics.continueCardWidth) { _, card in
            switch card {
            case .channel(let channel):
                channelCard(channel)
            case .new:
                Button {
                    Haptics.play(.buttons)
                    editing = TVChannel()
                } label: {
                    TVNewChannelCard()
                }
                .buttonStyle(PressableCardStyle.poster)
                .accessibilityIdentifier("home.tv.new")
            }
        }
        .accessibilityIdentifier("board.blusionTV")
        .task { await model.refresh() }
        .modifier(TVChannelSheets(model: model, services: services, editing: $editing, deleting: $deleting, failure: $failure))
    }

    private func channelCard(_ channel: TVChannel) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let schedule = model.lineups[channel.id]?.schedule(at: context.date) ?? []
            let now = schedule.first
            Button {
                if now != nil {
                    play(channel)
                } else {
                    Task { await model.load(channel) }
                }
            } label: {
                if let now {
                    TVProgrammeCard(programme: now, fraction: now.fraction(at: context.date), caption: channel.name,
                                    detail: nextLine(schedule), isTuning: model.tuning?.channel == channel.id,
                                    startedEpisodes: model.startedEpisodes)
                } else {
                    TVChannelPlaceholder(channel: channel, isLoading: model.loading.contains(channel.id), issue: model.issues[channel.id])
                }
            }
            .buttonStyle(PressableCardStyle.poster)
            .disabled(model.tuning != nil)
            .contextMenu {
                if let now {
                    Button("Watch Live", systemImage: "play.fill") { play(channel) }
                    if now.elapsed(at: context.date) >= 60 {
                        Button("Start Over", systemImage: "backward.end.fill") { play(channel, fromStart: true) }
                    }
                }
                Button("Open Guide", systemImage: "tv") { openGuide() }
                TVChannelMenuItems(channel: channel, isAuto: model.isAuto(channel), editing: $editing, deleting: $deleting) {
                    Task { await model.load(channel) }
                }
            }
        }
        .accessibilityIdentifier("home.tv.\(channel.id)")
    }

    /// What follows and when: the next show, or the next episode when the same show follows.
    private func nextLine(_ schedule: ArraySlice<TVLineup.Programme>) -> String {
        guard let now = schedule.first, let next = schedule.dropFirst().first else { return "" }
        let label = next.show.identity == now.show.identity ? next.episodeLabel : next.show.name
        let time = "Next at \(next.start.formatted(date: .omitted, time: .shortened))"
        return label.isEmpty ? time : "\(time) · \(label)"
    }

    private func play(_ channel: TVChannel, fromStart: Bool = false) {
        Haptics.play(.titles)
        model.tune(channel, fromStart: fromStart, play: { router.demoPlan = $0 }, fail: { failure = $0 })
    }

    private func openGuide() {
        Haptics.play(.titles)
        router.homePath.append(BlusionTVRoute())
    }
}

/// A channel whose lineup is loading or could not load: its first show's artwork, with a spinner or a retry mark.
private struct TVChannelPlaceholder: View {
    let channel: TVChannel
    let isLoading: Bool
    let issue: String?
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let show = channel.shows.first
        VStack(alignment: .leading, spacing: 2) {
            LandscapeCard(title: show?.name ?? channel.name, logo: show?.logo, artwork: show?.background ?? show?.poster) {
                if isLoading || issue != nil {
                    ZStack {
                        Color.black.opacity(0.35)
                        if isLoading {
                            Spinner()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xs)
            TVCardCaption(caption: channel.name, detail: isLoading ? "" : issue ?? "")
        }
        .frame(width: metrics.continueCardWidth, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([channel.name, isLoading ? "Loading" : issue].compactMap { $0 }.joined(separator: ", "))
    }
}
#endif
