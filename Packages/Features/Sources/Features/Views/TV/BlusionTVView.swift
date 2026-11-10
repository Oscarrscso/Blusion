#if canImport(UIKit)
import StremioKit
import SwiftUI

struct BlusionTVRoute: Hashable {}

/// Blusion TV's guide: each channel's schedule as a shelf of the cards Continue Watching uses, from what is on now.
struct BlusionTVView: View {
    let services: AppServices
    @State private var model: BlusionTVModel
    @State private var editing: TVChannel?
    @State private var deleting: TVChannel?
    @State private var failure: String?
    @Environment(AppRouter.self) private var router
    @Environment(\.layoutMetrics) private var metrics

    init(services: AppServices) {
        self.services = services
        _model = State(initialValue: BlusionTVModel.shared(services: services))
    }

    var body: some View {
        ScrollView {
            if model.allChannels.isEmpty && model.isMakingAutoChannels {
                Spinner()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xxl)
            } else if model.allChannels.isEmpty {
                ContentUnavailableView {
                    Label("No Channels", systemImage: "tv")
                } actions: {
                    Button("New Channel") { editing = TVChannel() }.buttonStyle(.borderedProminent)
                }
                .padding(.top, Theme.Spacing.xxl)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    LazyVStack(alignment: .leading, spacing: metrics.shelfSpacing) {
                        ForEach(model.allChannels) { channel in
                            guide(channel, at: context.date)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.l)
            }
        }
        .screenBackground()
        .navigationTitle("Blusion TV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Channel", systemImage: "plus") { editing = TVChannel() }
                    .accessibilityIdentifier("tv.create")
            }
        }
        .trackLandscapeTabScroll()
        .scrollIndicators(.visible)
        .scrollIndicatorsFlash(onAppear: true)
        .task { await model.refresh() }
        .refreshable { await model.refresh(force: true) }
        .onDisappear { model.cancelTuning() }
        .modifier(TVChannelSheets(model: model, services: services, editing: $editing, deleting: $deleting, failure: $failure))
    }

    private func guide(_ channel: TVChannel, at date: Date) -> some View {
        let isAuto = model.isAuto(channel)
        return VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            HStack(spacing: Theme.Spacing.s) {
                SectionHeader(channel.name, subtitle: "\(channel.shows.count == 1 ? "1 show" : "\(channel.shows.count) shows") · \(isAuto ? "Auto" : channel.order.title)")
                    .contextMenu {
                        TVChannelMenuItems(channel: channel, isAuto: isAuto, editing: $editing, deleting: $deleting) { refresh(channel) }
                    }
                Spacer(minLength: 0)
                if model.lineups[channel.id] != nil {
                    Button {
                        play(channel)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .glassCircleButton(.small)
                    .disabled(model.tuning != nil)
                    .accessibilityLabel("Watch \(channel.name)")
                    .accessibilityIdentifier("tv.play.\(channel.id)")
                }
                Menu {
                    TVChannelMenuItems(channel: channel, isAuto: isAuto, editing: $editing, deleting: $deleting) { refresh(channel) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .glassCircleButton(.small)
                .accessibilityLabel("\(channel.name) options")
            }
            .padding(.horizontal, metrics.pageMargin)
            lineup(channel, at: date)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv.channel.\(channel.id)")
    }

    @ViewBuilder
    private func lineup(_ channel: TVChannel, at date: Date) -> some View {
        if let schedule = model.lineups[channel.id]?.schedule(at: date), !schedule.isEmpty {
            MediaRow(channel.name, hideTitle: true, items: Array(schedule.prefix(12)), id: { "\(Int($0.start.timeIntervalSince1970))" },
                     aspect: .wide, cardWidth: metrics.continueCardWidth) { index, programme in
                let isOn = index == 0
                let stamp = Int(programme.start.timeIntervalSince1970)
                Button {
                    if isOn { play(channel) } else { play(channel, at: programme.start) }
                } label: {
                    TVProgrammeCard(programme: programme, fraction: isOn ? programme.fraction(at: date) : 0,
                                    caption: isOn ? "On Now" : programme.start.formatted(date: .omitted, time: .shortened),
                                    detail: programme.show.name,
                                    isTuning: model.tuning == BlusionTVModel.Tuning(channel: channel.id, start: programme.start),
                                    startedEpisodes: model.startedEpisodes)
                }
                .buttonStyle(PressableCardStyle.poster)
                .disabled(model.tuning != nil)
                .contextMenu {
                    if isOn {
                        Button("Watch Live", systemImage: "play.fill") { play(channel) }
                        if programme.elapsed(at: date) >= 60 {
                            Button("Start Over", systemImage: "backward.end.fill") { play(channel, fromStart: true) }
                        }
                    } else {
                        Button("Watch from Here", systemImage: "play.fill") { play(channel, at: programme.start) }
                    }
                    Button("Open Show", systemImage: "info.circle") {
                        router.homePath.append(TitleDestination(preview: programme.show, sourceID: "tv/\(channel.id)/\(stamp)"))
                    }
                }
                .accessibilityIdentifier("tv.programme.\(channel.id).\(stamp)")
            }
        } else if let issue = model.issues[channel.id] {
            HStack {
                Text(issue).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.s)
                Button("Retry") { refresh(channel) }.buttonStyle(.hoverGlass)
            }
            .padding(.horizontal, metrics.pageMargin)
        } else {
            Spinner()
                .frame(maxWidth: .infinity, minHeight: metrics.continueCardWidth / CardAspect.wide.ratio)
                // A lineup the clock has run past is worked out again from now.
                .task { if model.lineups[channel.id] != nil { await model.load(channel) } }
        }
    }

    private func refresh(_ channel: TVChannel) {
        Task { await model.load(channel) }
    }

    /// Without a `start`, joins what is on now, live.
    private func play(_ channel: TVChannel, at start: Date? = nil, fromStart: Bool = false) {
        Haptics.play(.titles)
        model.tune(channel, at: start, fromStart: fromStart, play: { router.demoPlan = $0 }, fail: { failure = $0 })
    }
}

/// One programme: Continue Watching's card, with how far the broadcast has got or its episode, over two caption lines.
struct TVProgrammeCard: View {
    let programme: TVLineup.Programme
    let fraction: Double
    let caption: String
    let detail: String
    var isTuning = false
    var startedEpisodes: Set<String> = []
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.appAppearance) private var appearance

    /// Spoiler-free titles keep an episode's name back until it has been started.
    private var episodeName: String? {
        let hidden = appearance.hidesSpoilers && appearance.spoilerTitles && !startedEpisodes.contains(programme.request.identity)
        return hidden || programme.episodeTitle.isEmpty ? nil : programme.episodeTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressCard(title: programme.show.name, subtitle: programme.episodeLabel, episodeName: episodeName,
                         artwork: programme.artwork, logo: programme.logo, fraction: fraction, duration: programme.duration)
                .overlay { if isTuning { TuningVeil() } }
                .animation(.smooth(duration: 0.25), value: isTuning)
                .padding(.bottom, Theme.Spacing.xs)
            TVCardCaption(caption: caption, detail: detail)
        }
        .frame(width: metrics.continueCardWidth, alignment: .leading)
        .contentShape(.rect)
    }
}

/// The card that starts a new channel, the same size as a programme's.
struct TVNewChannelCard: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let width = metrics.continueCardWidth
        VStack(alignment: .leading, spacing: 2) {
            RoundedRectangle(cornerRadius: CardAspect.wide.cornerRadius * metrics.cornerScale(for: .artwork), style: .continuous)
                .fill(.quaternary)
                .frame(width: width, height: width / CardAspect.wide.ratio)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, Theme.Spacing.xs)
            TVCardCaption(caption: "New Channel", detail: "")
        }
        .frame(width: width, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New Channel")
    }
}

/// Two caption lines under a card. Both keep their height when empty, so every card in a shelf is the same height.
struct TVCardCaption: View {
    let caption: String
    let detail: String

    var body: some View {
        Text(caption.isEmpty ? " " : caption)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
        Text(detail.isEmpty ? " " : detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// The veil a card shows while its streams load, as Continue Watching's does.
private struct TuningVeil: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            Spinner().controlSize(.large)
        }
        .clipShape(RoundedRectangle(cornerRadius: CardAspect.wide.cornerRadius * metrics.cornerScale(for: .artwork), style: .continuous))
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading streams")
    }
}

/// A channel's own actions, for its menus on Home and in the guide.
struct TVChannelMenuItems: View {
    let channel: TVChannel
    /// Blusion's own channels are made from the shows you like, so they cannot be edited or deleted.
    var isAuto = false
    @Binding var editing: TVChannel?
    @Binding var deleting: TVChannel?
    let refresh: () -> Void

    var body: some View {
        if !isAuto { Button("Edit Channel", systemImage: "pencil") { editing = channel } }
        Button("Refresh Guide", systemImage: "arrow.clockwise", action: refresh)
        if !isAuto { Button("Delete Channel", systemImage: "trash", role: .destructive) { deleting = channel } }
    }
}

/// The channel editor, the delete confirmation and a failed tune's alert, shared by Home's widget and the guide.
struct TVChannelSheets: ViewModifier {
    let model: BlusionTVModel
    let services: AppServices
    @Binding var editing: TVChannel?
    @Binding var deleting: TVChannel?
    @Binding var failure: String?
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .sheet(item: $editing) { channel in
                TVChannelEditor(channel: channel, isNew: !model.channels.contains { $0.id == channel.id }, services: services) {
                    model.save($0)
                }
            }
            .alert("Couldn't Play Channel", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
            .confirmationDialog("Delete \(deleting?.name ?? "channel")?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                if let deleting {
                    Button("Delete Channel", role: .destructive) { model.delete(deleting) }
                }
                Button("Cancel", role: .cancel) {}
            }
            // A channel moves on to what follows once its player closes.
            .onChange(of: router.demoPlan == nil) { _, closed in
                if closed { Task { await model.refreshProgress() } }
            }
    }
}

struct TVChannelEditor: View {
    @State var channel: TVChannel
    let isNew: Bool
    let services: AppServices
    let save: (TVChannel) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Channel Name", text: $channel.name)
                        .accessibilityIdentifier("tv.channel.name")
                    Picker("Order", selection: $channel.order) {
                        ForEach(TVChannel.Order.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Shows") {
                    ForEach(channel.shows, id: \.identity) { show in
                        HStack(spacing: Theme.Spacing.m) {
                            ArtworkImage(url: show.poster, title: show.name)
                                .frame(width: 32, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Text(show.name)
                        }
                    }
                    .onDelete { channel.shows.remove(atOffsets: $0) }
                    .onMove { channel.shows.move(fromOffsets: $0, toOffset: $1) }
                    NavigationLink {
                        TVShowPicker(shows: $channel.shows, services: services)
                    } label: { Label("Add Shows", systemImage: "plus") }
                }
            }
            .navigationTitle(isNew ? "New Channel" : "Edit Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(channel); dismiss() }
                        .disabled(channel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || channel.shows.isEmpty)
                }
            }
        }
    }
}

private struct TVShowPicker: View {
    @Binding var shows: [MetaPreview]
    @State private var search: SearchViewModel
    @State private var saved: [MetaPreview] = []
    let services: AppServices

    init(shows: Binding<[MetaPreview]>, services: AppServices) {
        _shows = shows
        self.services = services
        _search = State(initialValue: SearchViewModel(services: services, usesLivePicker: false, includesAISearch: false))
    }

    private var isSearching: Bool { !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        @Bindable var search = search
        List {
            let items = isSearching ? search.results(type: "series") : saved
            ForEach(items, id: \.identity) { show in
                Button {
                    if let index = shows.firstIndex(where: { $0.identity == show.identity }) {
                        shows.remove(at: index)
                    } else {
                        shows.append(show)
                    }
                    Haptics.play(.choices)
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        ArtworkImage(url: show.poster, title: show.name).frame(width: 40, height: 60).clipped()
                        VStack(alignment: .leading) {
                            Text(show.name).foregroundStyle(.primary)
                            if let year = show.releaseInfo { Text(year).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: shows.contains(where: { $0.identity == show.identity }) ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                    .pointerFeedback()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(shows.contains(where: { $0.identity == show.identity }) ? "Remove" : "Add") \(show.name)")
            }
            if search.phase == .searching { ProgressView() }
            if items.isEmpty, search.phase != .searching {
                if isSearching {
                    ContentUnavailableView("No Shows Found", systemImage: "magnifyingglass")
                } else {
                    ContentUnavailableView("Search for Shows", systemImage: "magnifyingglass")
                }
            }
            if !search.failures.isEmpty {
                ForEach(search.failures) { Text($0.text).foregroundStyle(.secondary) }
                Button("Retry") { Task { await search.submit() } }
            }
        }
        .navigationTitle("Add Shows")
        .searchable(text: $search.query, prompt: "Search shows")
        .onChange(of: search.query) { search.queryDidChange() }
        .onSubmit(of: .search) { Task { await search.submit() } }
        .task {
            saved = await services.library.all().filter { $0.type == "series" }.map(\.preview)
        }
        .onDisappear { search.cancel() }
    }
}
#endif
