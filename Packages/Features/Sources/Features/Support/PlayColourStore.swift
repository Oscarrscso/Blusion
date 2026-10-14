#if canImport(UIKit)
import Foundation
import StremioKit
import SwiftUI

/// The Play button colour of each title, read once from the poster its card shows and kept in memory and on disk. A title's page reads it
/// on the first frame, so the button is coloured as the page opens. A poster with no vivid colour is kept too, so it is not read again.
@MainActor
final class PlayColourStore {
    static let shared = PlayColourStore()

    /// "rrggbb" for each title identity whose poster was read, or "" for a poster with no vivid colour.
    private var entries: [String: String] = [:]
    /// Titles being read now, so cards that show the same title at once read it once.
    private var reading: Set<String> = []
    private let file: URL?

    init(file: URL? = PlayColourStore.defaultFile) {
        self.file = file
        guard let file else { return }
        Task { [weak self] in
            let saved = await Task.detached(priority: .utility) { PlayColourStore.read(file) }.value
            self?.entries.merge(saved) { current, _ in current }
        }
    }

    /// The button's colour for a title, or nil when its poster has not been read yet or has no vivid colour. It reads memory only, so it
    /// is cheap to ask on every draw; the page asks once, when it opens.
    func colour(for identity: String) -> Color? {
        guard let hex = entries[identity], let value = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// The pictures a title's card can show, first choice first: the BetterPosters picture a row may show, then the usual poster that stands in
    /// for it. The colour is read from whichever is in the image cache.
    static func pictures(for item: MetaPreview) -> [URL] {
        // A Mac card shows the landscape picture, not the poster, so its poster is often not in the image cache: the pictures the card
        // shows are read too, after the poster.
        [BetterPosters.posterURL(id: item.id, type: item.type), PosterQuality.poster(for: item), PosterQuality.landscape(item.background),
         item.background].compactMap { $0 }
    }

    /// Reads a title's colour on the spot, when its page opens before its card's read has run. A picture is used only when it is already in
    /// the image cache. The read is a few pixels, so it is done here, on the main thread, without a wait.
    func readNow(identity: String, pictures: [URL]) {
        guard entries[identity] == nil, let hex = Self.hex(from: pictures) else { return }
        entries[identity] = hex
        save()
    }

    /// Reads a title's colour from its picture, when a picture is already in the image cache because its card has shown it. The picture is
    /// read off the main thread, once per title; a title whose picture is not cached yet is read the next time its card appears.
    func read(identity: String, pictures: [URL]) async {
        guard entries[identity] == nil, !reading.contains(identity), !pictures.isEmpty else { return }
        reading.insert(identity)
        defer { reading.remove(identity) }
        guard let hex = await Task.detached(priority: .utility, operation: { PlayColourStore.hex(from: pictures) }).value else { return }
        entries[identity] = hex
        save()
    }

    /// The colour of the first cached picture as "rrggbb": "" when it has no vivid colour, nil when none of them is in the image cache yet.
    nonisolated static func hex(from pictures: [URL]) -> String? {
        guard let picture = pictures.lazy.compactMap({ ImagePipeline.shared.cachedImageAtAnySize(for: $0)?.cgImage }).first,
              let pixels = PlayColour.pixels(of: picture) else { return nil }
        guard let colour = PlayColour.pick(from: pixels) else { return "" }
        let rgb = PlayColour.rgb(colour)
        return [rgb.red, rgb.green, rgb.blue].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
    }

    private func save() {
        guard let file else { return }
        let snapshot = entries
        Task.detached(priority: .utility) { PlayColourStore.write(snapshot, to: file) }
    }

    nonisolated static func read(_ file: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return saved
    }

    nonisolated static func write(_ entries: [String: String], to file: URL) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static var defaultFile: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("play-colours.json")
    }
}
#endif
