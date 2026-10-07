import Foundation

/// Asks every addon that can answer for streams, and probes ambiguous URLs, without ever blocking on the slowest addon.
public final class StreamService: Sendable {
    public let registry: AddonRegistry
    public let client: AddonClient
    private let sniffer: any ContainerSniffing
    /// How many ranged sniff requests run at once.
    private let sniffConcurrency: Int

    public init(registry: AddonRegistry, client: AddonClient, sniffer: (any ContainerSniffing)? = nil, sniffConcurrency: Int = 4) {
        self.registry = registry
        self.client = client
        self.sniffer = sniffer ?? RangedContainerSniffer(client: client)
        self.sniffConcurrency = max(1, sniffConcurrency)
    }

    /// Addons that will be asked, in the user's order, and the stream of their answers as each arrives.
    public func fetch(_ request: StreamRequest) async -> (asked: [AddonSummary], responses: AsyncStream<AddonResponse<[AddonStream]>>) {
        let addons = await registry.addons(for: .stream, type: request.type, id: request.id)
        let client = self.client
        let responses = FanOut.run(over: addons) { addon in
            try await client.streams(base: addon.baseURL, type: request.type, id: request.id)
        }
        return (addons.map(\.summary), responses)
    }

    /// Probes `targets` with at most `sniffConcurrency` requests in flight and yields each result as it completes.
    public func sniff(_ targets: [StreamListing.SniffTarget]) -> AsyncStream<(key: String, container: MediaContainer?)> {
        let sniffer = self.sniffer
        let limit = sniffConcurrency
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: (String, MediaContainer?).self) { group in
                    var iterator = targets.makeIterator()
                    var running = 0
                    func startNext(_ group: inout TaskGroup<(String, MediaContainer?)>) -> Bool {
                        guard let target = iterator.next() else { return false }
                        group.addTask { (target.key, await sniffer.sniff(url: target.url, headers: target.headers)) }
                        return true
                    }
                    while running < limit, startNext(&group) { running += 1 }
                    while let result = await group.next() {
                        continuation.yield((key: result.0, container: result.1))
                        if !Task.isCancelled, startNext(&group) { continue }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
