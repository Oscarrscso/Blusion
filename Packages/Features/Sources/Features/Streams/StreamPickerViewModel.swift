import Foundation
import Observation
import StremioKit

/// Stream picker: results appear grouped by addon as each one answers; ambiguous URLs are probed in the background.
@MainActor
@Observable
public final class StreamPickerViewModel {
    public enum Choice: Equatable {
        case play(PlaybackPlan)
        case openExternal(URL)
        /// The format needs an engine this build doesn't have. The picker offers the next stream.
        case unsupported(next: RankedStream?)
    }

    public let request: StreamRequest
    public private(set) var listing: StreamListing
    /// True when no installed addon can answer this request at all (as opposed to "still loading" or "nothing found").
    public private(set) var nobodyCanAnswer = false
    public private(set) var settings = PlaybackSettings()
    public private(set) var hasLoaded = false

    private let services: AppServices
    private var sniffTasks: [Task<Void, Never>] = []

    public init(request: StreamRequest, services: AppServices) {
        self.request = request
        self.services = services
        self.listing = StreamListing(asking: [])
    }

    public var isLoading: Bool { !hasLoaded || listing.isLoading }
    /// Nothing found, and every addon that was asked failed because the device is offline.
    public var isOffline: Bool { hasLoaded && listing.isEmpty && Connectivity.isOffline(listing.failures.map(\.error)) }
    public var showsNothingFound: Bool { hasLoaded && !listing.isLoading && listing.isEmpty && !nobodyCanAnswer && !isOffline }

    public func load() async {
        settings = await services.settings.load()
        let (asked, responses) = await services.streams.fetch(request)
        listing = StreamListing(asking: asked, config: settings.policy(fallbackEngineLinked: services.fallbackEngineLinked),
                                preferences: settings.rankingPreferences)
        nobodyCanAnswer = asked.isEmpty
        hasLoaded = true
        guard !asked.isEmpty else { return }

        await withTaskCancellationHandler {
            var requested = Set<String>()
            for await response in responses {
                listing.apply(response)
                let targets = listing.sniffTargets.filter { requested.insert($0.key).inserted }
                if !targets.isEmpty { startSniffing(targets) }
            }
            for task in sniffTasks { await task.value }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelSniffing() }
        }
    }

    private func startSniffing(_ targets: [StreamListing.SniffTarget]) {
        let results = services.streams.sniff(targets)
        sniffTasks.append(Task { [weak self] in
            for await result in results { self?.listing.setContainer(result.container, forKey: result.key) }
        })
    }

    private func cancelSniffing() {
        sniffTasks.forEach { $0.cancel() }
    }

    /// What happens when the user taps a stream.
    public func choose(_ item: RankedStream) -> Choice? {
        switch item.route {
        case .native, .fallback:
            return PlaybackPlan.make(request: request, chosen: item, from: listing).map(Choice.play)
        case .external(let url):
            return .openExternal(url)
        case .unsupported:
            return .unsupported(next: nextPlayable(after: item))
        case .hidden:
            return nil
        }
    }

    /// The best playable stream, for a one-tap "Play best".
    public func playBest() -> Choice? {
        listing.best.flatMap(choose)
    }

    /// The first playable stream ranked after `item`; what "Try the next stream" plays.
    public func nextPlayable(after item: RankedStream) -> RankedStream? {
        guard let index = listing.items.firstIndex(where: { $0.id == item.id }) else { return listing.best }
        return listing.items[(index + 1)...].first { $0.route.isPlayable } ?? listing.best
    }

    /// For binge-watching: the stream continuing the previous episode's group, if this listing has one.
    public func bingeChoice(continuing previous: BingeContext?) -> Choice? {
        BingeSelection.pick(from: listing.items, continuing: previous).flatMap(choose)
    }

    public func retry() async {
        sniffTasks.forEach { $0.cancel() }
        sniffTasks = []
        hasLoaded = false
        await load()
    }
}
