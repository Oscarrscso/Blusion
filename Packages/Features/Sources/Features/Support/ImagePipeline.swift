#if canImport(UIKit)
import Foundation
import ImageIO
import os
import UIKit

/// Loads, downsamples and caches artwork for `ArtworkImage`. Images are decoded at the size they are shown, not at the size
/// of the file, so a long row of posters keeps a few megabytes decoded rather than hundreds.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession
    /// The downloaded files on disk, kept until the size limit (`ImageCachePolicy`) pushes the least recently used out. `URLCache` is
    /// thread-safe, so its size and usage are read and set without hopping onto the actor.
    private nonisolated(unsafe) let files: URLCache
    /// Pictures being checked for a newer copy now, so one is checked once at a time, and at most `refreshLimit` at once.
    private var refreshing: Set<String> = []
    private static let refreshLimit = 3
    /// `NSCache` is thread-safe, which is what lets `cachedImage` answer without hopping onto the actor.
    private nonisolated(unsafe) let decoded = NSCache<NSString, UIImage>()
    /// What the cache cannot be asked: the sizes each address has been decoded at, and the addresses that answered "not found". Behind a
    /// lock, so views can read it without hopping onto the actor.
    private struct Known {
        /// `NSCache` does not say what it evicts, so a size listed here may be gone; `cachedImageAtAnySize` forgets those as it meets them.
        var sizes: [String: Set<Int>] = [:]
        var missing: Set<String> = []
    }
    private let known = OSAllocatedUnfairLock(initialState: Known())
    /// Both lists are emptied when they pass this many addresses, so a long session cannot grow them without end.
    private static let knownLimit = 4000
    /// Downloads and decodes still running, keyed like the cache, so two views asking for one poster share one request.
    private struct Pending {
        let task: Task<UIImage, Error>
        var consumers: Set<UUID>
        /// The download's place in the slot queue. An urgent caller that joins it moves it past the limit.
        let slot: UUID
    }
    private var inFlight: [String: Pending] = [:]
    private var activeDownloads = 0
    private var waiting: [(id: UUID, priority: TaskPriority, continuation: CheckedContinuation<Void, Error>)] = []
    /// Downloads that take a slot without waiting. An urgent caller asked for them, either before they reached the queue or while they waited.
    private var urgentSlots: Set<UUID> = []

    init() {
        let configuration = URLSessionConfiguration.default
        let saved = UserDefaults.standard.object(forKey: ImageCachePolicy.diskMegabytesKey) as? Int
        files = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: ImageCachePolicy.diskBytes(forSavedMegabytes: saved))
        configuration.urlCache = files
        // A cached copy is served without asking the server first, however old it is: a poster is not downloaded again for its age. One
        // that is due a check is checked afterwards, in the background (see `refreshIfDue`).
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        decoded.totalCostLimit = 256 * 1024 * 1024
    }

    // MARK: The cache on disk

    /// The bytes the pictures take on disk now.
    nonisolated var diskUsage: Int { files.currentDiskUsage }

    /// Sets the disk cache's size. A smaller size removes the least recently used pictures until they fit.
    nonisolated func setDiskLimit(megabytes: Int) {
        files.diskCapacity = ImageCachePolicy.diskBytes(forSavedMegabytes: megabytes)
    }

    /// Removes every picture, on disk and in memory, and forgets which addresses were missing. Views that show one keep it until they are
    /// drawn again; Play colours, which are kept per title, stay.
    func clear() {
        files.removeAllCachedResponses()
        decoded.removeAllObjects()
        known.withLock { $0 = Known() }
    }

    /// A picture that is already decoded, without waiting. A card that scrolls back into view shows its artwork in the same
    /// frame instead of flashing its placeholder.
    nonisolated func cachedImage(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        decoded.object(forKey: Self.key(url, maxPixelSize: maxPixelSize) as NSString)
    }

    /// A picture of `url` that is already decoded, at whatever size, the largest first, without waiting. For a stand-in that only has to be
    /// there in the first frame: the page a card opens shows the poster the card is showing instead of loading it again.
    nonisolated func cachedImageAtAnySize(for url: URL) -> UIImage? {
        let address = url.absoluteString
        let sizes = known.withLock { $0.sizes[address] } ?? []
        var gone: [Int] = []
        var found: UIImage?
        for size in sizes.sorted(by: >) {
            if let image = decoded.object(forKey: "\(size)|\(address)" as NSString) {
                found = image
                break
            }
            gone.append(size)
        }
        if !gone.isEmpty {
            let evicted = gone
            known.withLock { known in
                known.sizes[address]?.subtract(evicted)
                if known.sizes[address]?.isEmpty == true { known.sizes[address] = nil }
            }
        }
        return found
    }

    /// True when `url` answered "not found" earlier in this session. Such an address is not asked again, so a card whose first choice of
    /// artwork does not exist goes straight to its fallback.
    nonisolated func isKnownMissing(_ url: URL) -> Bool {
        known.withLock { $0.missing.contains(url.absoluteString) }
    }

    /// Drops the decoded picture for this URL and size from memory. A view that still shows it keeps its own reference.
    nonisolated func evict(_ url: URL, maxPixelSize: CGFloat) {
        decoded.removeObject(forKey: Self.key(url, maxPixelSize: maxPixelSize) as NSString)
    }

    /// The size is part of the key: a 44 pt thumbnail and a full-width backdrop of one title are different images.
    private static func key(_ url: URL, maxPixelSize: CGFloat) -> String {
        "\(Int(min(max(maxPixelSize.rounded(), 1), 4096)))|\(url.absoluteString)"
    }

    /// The image at `url`, decoded no larger than `maxPixelSize` on its long edge. Memory-cached; concurrent requests for
    /// the same URL and size share one download. Only http and https URLs are loaded.
    ///
    /// An `urgent` request does not wait for one of the download slots: it starts at once, past the limit, so a page the user has just
    /// opened is not held up by posters. A download already waiting for a slot is moved ahead when an urgent caller joins it.
    func image(for url: URL, maxPixelSize: CGFloat, priority: TaskPriority = .medium, urgent: Bool = false) async throws -> UIImage {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ImagePipelineError.unsupportedURL
        }
        let size = min(max(maxPixelSize.rounded(), 1), 4096)
        try Task.checkCancellation()
        let key = Self.key(url, maxPixelSize: maxPixelSize)
        if let cached = decoded.object(forKey: key as NSString) { return cached }
        if isKnownMissing(url) { throw ImagePipelineError.httpStatus(404) }
        let consumer = UUID()
        let task: Task<UIImage, Error>
        if var pending = inFlight[key] {
            pending.consumers.insert(consumer)
            inFlight[key] = pending
            task = pending.task
            if urgent { skipSlotLimit(for: pending.slot) }
        } else {
            let slot = UUID()
            if urgent { urgentSlots.insert(slot) }
            task = Task(priority: priority) {
                try await acquireDownloadSlot(id: slot, priority: priority)
                defer { releaseDownloadSlot() }
                try Task.checkCancellation()
                let fetched = try await Self.fetch(url, maxPixelSize: size, session: session, files: files)
                if fetched.isDue { await refreshIfDue(url) }
                return fetched.image
            }
            inFlight[key] = Pending(task: task, consumers: [consumer], slot: slot)
        }
        return try await withTaskCancellationHandler {
            defer { releaseConsumer(consumer, for: key) }
            let image: UIImage
            do {
                image = try await task.value
            } catch ImagePipelineError.httpStatus(404) {
                known.withLock { known in
                    if known.missing.count >= Self.knownLimit { known.missing.removeAll() }
                    known.missing.insert(url.absoluteString)
                }
                throw ImagePipelineError.httpStatus(404)
            }
            try Task.checkCancellation()
            decoded.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
            known.withLock { known in
                if known.sizes.count >= Self.knownLimit { known.sizes.removeAll() }
                known.sizes[url.absoluteString, default: []].insert(Int(size))
            }
            return image
        } onCancel: {
            Task { await self.releaseConsumer(consumer, for: key) }
        }
    }

    private func releaseConsumer(_ consumer: UUID, for key: String) {
        guard var pending = inFlight[key], pending.consumers.remove(consumer) != nil else { return }
        if pending.consumers.isEmpty {
            pending.task.cancel()
            inFlight[key] = nil
            urgentSlots.remove(pending.slot)
        } else { inFlight[key] = pending }
    }

    private func acquireDownloadSlot(id: UUID, priority: TaskPriority) async throws {
        try Task.checkCancellation()
        // Keep one of the six slots available for title logos, even when posters fill the queue.
        if urgentSlots.remove(id) != nil || activeDownloads < (priority >= .high ? 6 : 5) { activeDownloads += 1; return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let index = waiting.firstIndex { $0.priority < priority } ?? waiting.endIndex
                waiting.insert((id, priority, continuation), at: index)
            }
        } onCancel: {
            Task { await self.cancelWaitingDownload(id) }
        }
    }

    /// An urgent caller joined the download in `slot`. A download waiting for a slot takes one now, past the limit; one not yet in the
    /// queue is marked so it takes one as soon as it asks.
    private func skipSlotLimit(for slot: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == slot }) {
            activeDownloads += 1
            waiting.remove(at: index).continuation.resume()
        } else {
            urgentSlots.insert(slot)
        }
    }

    private func cancelWaitingDownload(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func releaseDownloadSlot() {
        activeDownloads -= 1
        guard let next = waiting.first, activeDownloads < (next.priority >= .high ? 6 : 5) else { return }
        activeDownloads += 1
        waiting.removeFirst().continuation.resume()
    }

    /// Runs off the actor, so a slow download or decode never blocks requests for other images. `isDue` is true when the picture came
    /// from the disk cache and has been there long enough to be checked for a newer copy.
    private nonisolated static func fetch(_ url: URL, maxPixelSize: CGFloat, session: URLSession,
                                          files: URLCache) async throws -> (image: UIImage, isDue: Bool) {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImagePipelineError.httpStatus(http.statusCode)
        }
        guard let image = decode(data, maxPixelSize: maxPixelSize) else {
            throw ImagePipelineError.undecodable
        }
        // A copy from the network is dated about now, so only one that has been on disk a while is old enough to be due.
        // One with no date is checked once, and dated then (see `revalidate`).
        let fetched = ImageCachePolicy.date(fromHeader: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date"))
        return (image, ImageCachePolicy.isDueForRefresh(url: url, fetched: fetched))
    }

    /// Checks a picture that has been on disk a while for a newer copy, in the background, once at a time. Nothing on screen changes: a
    /// newer copy is stored, and it replaces the decoded picture in memory, so the next time the picture is drawn it is the new one.
    private func refreshIfDue(_ url: URL) {
        let address = url.absoluteString
        // A few at a time, so a Home full of old posters does not send a burst of requests; one skipped now is checked the next time it
        // comes from the disk.
        guard refreshing.count < Self.refreshLimit, refreshing.insert(address).inserted else { return }
        let session = session
        let files = files
        let known = known
        // Off the actor: the request and the decoding never hold up other pictures.
        Task.detached(priority: .background) {
            var replacements: [(size: Int, image: UIImage)] = []
            if let newer = await Self.revalidate(url, session: session, files: files) {
                // The sizes decoded by now, the one being loaded when the check started included.
                for size in known.withLock({ $0.sizes[address] }) ?? [] {
                    if let image = Self.decode(newer, maxPixelSize: CGFloat(size)) { replacements.append((size, image)) }
                }
            }
            await self.finishRefresh(url, replacements: replacements)
        }
    }

    private func finishRefresh(_ url: URL, replacements: [(size: Int, image: UIImage)]) {
        let address = url.absoluteString
        refreshing.remove(address)
        for replacement in replacements {
            decoded.setObject(replacement.image, forKey: "\(replacement.size)|\(address)" as NSString, cost: Self.cost(of: replacement.image))
        }
    }

    /// Asks the server whether the stored copy is still current (If-None-Match, If-Modified-Since). Unchanged: the stored copy is kept and
    /// dated now, so it is not asked about again for a while, and nil comes back. Changed: the new copy is stored and returned. A failure
    /// leaves the stored copy as it is.
    private nonisolated static func revalidate(_ url: URL, session: URLSession, files: URLCache) async -> Data? {
        let plain = URLRequest(url: url)
        guard let stored = files.cachedResponse(for: plain), let old = stored.response as? HTTPURLResponse else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        if let tag = old.value(forHTTPHeaderField: "ETag") { request.setValue(tag, forHTTPHeaderField: "If-None-Match") }
        if let modified = old.value(forHTTPHeaderField: "Last-Modified") { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 304 || ((200..<300).contains(http.statusCode) && data == stored.data) {
            var headers: [String: String] = [:]
            for (key, value) in old.allHeaderFields {
                guard let key = key as? String, let value = value as? String, key.lowercased() != "date" else { continue }
                headers[key] = value
            }
            headers["Date"] = ImageCachePolicy.header(for: Date())
            if let renewed = HTTPURLResponse(url: url, statusCode: old.statusCode, httpVersion: "HTTP/1.1", headerFields: headers) {
                files.storeCachedResponse(CachedURLResponse(response: renewed, data: stored.data), for: plain)
            }
            return nil
        }
        guard (200..<300).contains(http.statusCode), decode(data, maxPixelSize: 64) != nil else { return nil }
        files.storeCachedResponse(CachedURLResponse(response: http, data: data), for: plain)
        return data
    }

    /// ImageIO builds the thumbnail straight from the compressed data, so the full-size bitmap is never created.
    private nonisolated static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

enum ImagePipelineError: Error, Sendable {
    case unsupportedURL
    case httpStatus(Int)
    case undecodable
}
#endif
