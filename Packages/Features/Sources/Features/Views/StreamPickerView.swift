#if canImport(SwiftUI)
import SwiftUI
import StremioKit

struct StreamPickerView: View {
    @State private var model: StreamPickerViewModel
    @State private var plan: PlaybackPlan?
    @State private var unsupported: RankedStream?
    private let services: AppServices
    @Environment(\.openURL) private var openURL

    init(request: StreamRequest, services: AppServices) {
        self.services = services
        _model = State(initialValue: StreamPickerViewModel(request: request, services: services))
    }

    var body: some View {
        List {
            statusSection
            ForEach(model.listing.groups) { group in
                Section(group.addon.name) {
                    ForEach(group.streams) { item in
                        Button { select(item) } label: { StreamRow(item: item) }
                            .accessibilityIdentifier("stream.row.\(item.title)")
                    }
                }
            }
            hiddenSection
        }
        .navigationTitle(model.request.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.listing.best != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Play best") { if let choice = model.playBest() { handle(choice) } }
                        .accessibilityIdentifier("streams.playBest")
                }
            }
        }
        .task { await model.load() }
        .fullScreenCover(item: $plan) { PlayerScreen(plan: $0, services: services) }
        .alert("This format isn't supported yet", isPresented: Binding(get: { unsupported != nil }, set: { if !$0 { unsupported = nil } }), presenting: unsupported) { item in
            if let next = model.nextPlayable(after: item), next.id != item.id {
                Button("Try the next stream") { select(next) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Blusion can't play this container or audio yet. Pick another stream.")
        }
        .accessibilityIdentifier("streams.list")
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.nobodyCanAnswer {
            ContentUnavailableView("No stream addons", systemImage: "puzzlepiece.extension",
                                   description: Text("None of your addons provides streams for this title. Install one on the Addons tab."))
                .accessibilityIdentifier("streams.nobody")
        } else if model.showsNothingFound {
            ContentUnavailableView("No streams found", systemImage: "film.stack", description: Text("Your addons have nothing for this title."))
                .accessibilityIdentifier("streams.none")
        }
        if model.isLoading && !model.nobodyCanAnswer {
            HStack(spacing: 12) {
                ProgressView()
                Text(model.listing.pending.isEmpty ? "Checking…" : "Waiting for \(model.listing.pending.map(\.name).joined(separator: ", "))…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("streams.loading")
        }
        if !model.listing.failures.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.listing.failures) { failure in ErrorChip(text: "\(failure.addon.name): \(failure.error.shortDescription)") }
                Button("Try again") { Task { await model.retry() } }
            }
            .accessibilityIdentifier("streams.failures")
        }
    }

    @ViewBuilder
    private var hiddenSection: some View {
        if !model.listing.hidden.isEmpty {
            Section {
                ForEach(model.listing.hidden) { hint in
                    Label(hint.text, systemImage: "eye.slash").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("streams.hidden")
        }
    }

    private func select(_ item: RankedStream) {
        guard let choice = model.choose(item) else { return }
        if case .unsupported = choice {
            unsupported = item   // the alert offers the next playable stream
        } else {
            handle(choice)
        }
    }

    private func handle(_ choice: StreamPickerViewModel.Choice) {
        switch choice {
        case .play(let next): plan = next
        case .openExternal(let url): openURL(url)
        case .unsupported: break   // handled in `select`, which knows the item
        }
    }
}

struct StreamRow: View {
    let item: RankedStream

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if let detail = item.stream.description?.split(whereSeparator: \.isNewline).joined(separator: " · "), !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(3)
                }
                let facts = factLabels
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if !item.alsoProvidedBy.isEmpty {
                    Text("Also from \(item.alsoProvidedBy.map(\.name).joined(separator: ", "))").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }

    private var factLabels: [String] {
        var labels: [String] = []
        if let label = item.quality.resolutionLabel { labels.append(label) }
        if item.quality.isDolbyVision { labels.append("Dolby Vision") } else if item.quality.isHDR { labels.append("HDR") }
        if let size = item.quality.sizeBytes { labels.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let container = item.container { labels.append(container.rawValue.uppercased()) }
        return labels
    }

    private var icon: String {
        switch item.route {
        case .native, .fallback: return "play.circle"
        case .external: return "arrow.up.forward.app"
        case .unsupported: return "exclamationmark.triangle"
        case .hidden: return "eye.slash"
        }
    }

    private var tint: Color {
        switch item.route {
        case .native, .fallback: return .accentColor
        case .external: return .secondary
        case .unsupported, .hidden: return .orange
        }
    }

    private var hint: String {
        switch item.route {
        case .native, .fallback: return "Plays in Blusion"
        case .external: return "Opens outside Blusion"
        case .unsupported: return "This format isn't supported yet"
        case .hidden: return ""
        }
    }
}
#endif
