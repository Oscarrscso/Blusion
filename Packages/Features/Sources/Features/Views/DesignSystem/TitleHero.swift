#if canImport(UIKit)
import SwiftUI

/// The portrait hero's numbers, shared by Home's spotlight and the title page so that opening a title from one looks the same on the
/// other: the same picture size, fade, logo and placement. Both screens read them; change one here and both move together.
enum TitleHero {
    /// The share of the picture's height that the bottom fade covers.
    static let fadeLength = 0.42
    static let fadeStrength = 1.0
    /// How far the bottom fade runs past the picture's bottom edge, so no row of picture pixels shows under it while the page moves.
    static let fadeOverscan: CGFloat = 2
    /// The tallest logo, bottom-aligned above the bottom gap.
    static let logoMaxHeight: CGFloat = 150
    /// The gap between the bottom of the logo and the bottom of the picture.
    static let logoBottomGap = Theme.Spacing.xl
    /// The longest edge the picture is decoded to. Smaller than full screen, so the neighbouring pages keep it in the image cache.
    static let portraitPixelSize: CGFloat = 2048
    static let imageAlignment = Alignment.top
    /// The poster stands in unblurred, so it matches the picture that replaces it.
    static let placeholderBlur: CGFloat = 0
    /// The band under the picture on Home that holds the metadata line. The title page has no band; its picture is the same height.
    static let captionBelow: CGFloat = 72

    // MARK: Landscape title page (iPhone only; the Mac keeps its original sizes)
    /// The share of the content width (after the gap) the landscape picture takes.
    static var landscapeArtworkShare: CGFloat {
        #if targetEnvironment(macCatalyst)
        0.48
        #else
        0.55
        #endif
    }
    /// The tallest and widest the landscape logo can be.
    static var landscapeLogoMaxHeight: CGFloat {
        #if targetEnvironment(macCatalyst)
        56
        #else
        100
        #endif
    }
    static var landscapeLogoMaxWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        220
        #else
        300
        #endif
    }
    /// The one gap between Play and every button beside it in landscape: the portrait gap.
    static let actionGap = Theme.Spacing.s

    /// The height of the portrait picture on a screen `width` wide.
    static func height(width: CGFloat, metrics: LayoutMetrics) -> CGFloat {
        min(width * 1.5, metrics.heroMaxHeight)
    }
}

/// What one hero image is doing: still loading, decoded and ready, or there is none (no URL once the lookup has finished, or it failed).
enum HeroSlot {
    case pending
    case ready(UIImage)
    case none
    var isPending: Bool { if case .pending = self { return true } else { return false } }
}

/// Loads the hero picture and the logo together and answers from the image cache, so a decoded one is there in the first frame.
/// It also holds what it has shown, so the shared cache evicting a large picture never sends a shown hero back to loading, and every
/// logo lives in a process-wide store, so a title's logo is there in the first frame for the rest of the session.
@MainActor @Observable
final class HeroLoader {
    /// Longest edge the logo is decoded to, on Home and on the title page.
    static let logoPixelSize: CGFloat = 800
    /// Logos are small, so this many are kept for the whole session; the oldest go first.
    private static let logoLimit = 80
    private static var logos: [String: UIImage] = [:]
    private static var logoOrder: [String] = []

    private var failed: Set<String> = []
    private var revision = 0
    /// The pictures this loader has resolved, held strongly so they outlive the shared cache's eviction. Not observed: `revision` is.
    @ObservationIgnored private var held: [String: UIImage] = [:]

    nonisolated private static func key(_ url: URL, _ size: CGFloat) -> String { "\(Int(size))|\(url.absoluteString)" }

    /// The logo of `url` if one has been loaded this session.
    static func storedLogo(_ url: URL) -> UIImage? { logos[key(url, logoPixelSize)] }

    private static func storeLogo(_ image: UIImage, for url: URL) {
        let key = key(url, logoPixelSize)
        if logos.updateValue(image, forKey: key) != nil { logoOrder.removeAll { $0 == key } }
        logoOrder.append(key)
        while logoOrder.count > logoLimit { logos[logoOrder.removeFirst()] = nil }
    }

    /// Loads a logo into the process-wide store without any loader, so it is ready before its page is built. Ignores failures.
    static func warmLogo(_ url: URL, priority: TaskPriority) async {
        if storedLogo(url) != nil { return }
        if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: logoPixelSize) { storeLogo(cached, for: url); return }
        guard let image = try? await ImagePipeline.shared.image(for: url, maxPixelSize: logoPixelSize, priority: priority),
              !Task.isCancelled else { return }
        storeLogo(image, for: url)
    }

    /// Remembers an image that has been resolved: logos in the shared store, pictures in this loader.
    private func remember(_ image: UIImage, url: URL, size: CGFloat) {
        if size == Self.logoPixelSize { Self.storeLogo(image, for: url) } else { held[Self.key(url, size)] = image }
    }

    /// Drops the pictures this loader holds except those in `kept`, so a page that has left the load window stops pinning memory.
    /// Logos are never dropped.
    func release(keeping kept: [(URL, CGFloat)]) {
        guard !held.isEmpty else { return }
        let keys = Set(kept.map { Self.key($0.0, $0.1) })
        held = held.filter { keys.contains($0.key) }
    }

    /// A slot's state. A nil URL is pending until `lookupFinished`, then there is none.
    func slot(url: URL?, maxPixelSize: CGFloat, lookupFinished: Bool) -> HeroSlot {
        _ = revision
        guard let url else { return lookupFinished ? .none : .pending }
        if maxPixelSize == Self.logoPixelSize, let logo = Self.storedLogo(url) { return .ready(logo) }
        if let image = held[Self.key(url, maxPixelSize)] { return .ready(image) }
        if let image = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            remember(image, url: url, size: maxPixelSize)
            return .ready(image)
        }
        return failed.contains(Self.key(url, maxPixelSize)) ? .none : .pending
    }

    /// The one reveal condition: neither is still pending. A missing or failed one does not hold the other back.
    static func isRevealed(_ picture: HeroSlot, _ logo: HeroSlot) -> Bool { !picture.isPending && !logo.isPending }

    /// Starts the picture and the logo together at `priority` (high by default) and returns when both have finished. Does nothing until both URLs are
    /// known, or known to be absent (`lookupFinished`), so neither starts alone. The reveal is one state change in one transaction.
    func load(priority: TaskPriority = .high, picture: URL?, pictureSize: CGFloat, logo: URL?, logoSize: CGFloat, lookupFinished: Bool) async {
        guard (picture != nil || lookupFinished), (logo != nil || lookupFinished) else { return }
        let wanted = [(picture, pictureSize), (logo, logoSize)].compactMap { url, size in
            url.map { ($0, size) }
        }
        var pending: [(URL, CGFloat)] = []
        for (url, size) in wanted {
            if size == Self.logoPixelSize, Self.storedLogo(url) != nil { continue }
            if held[Self.key(url, size)] != nil { continue }
            if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: size) { remember(cached, url: url, size: size); continue }
            pending.append((url, size))
        }
        guard !pending.isEmpty else { return }
        let results = await withTaskGroup(of: (URL, CGFloat, UIImage?, Bool).self, returning: [(URL, CGFloat, UIImage?, Bool)].self) { group in
            for (url, size) in pending {
                group.addTask {
                    do {
                        let image = try await ImagePipeline.shared.image(for: url, maxPixelSize: size, priority: priority)
                        return (url, size, image, false)
                    } catch { return (url, size, nil, !Task.isCancelled) }
                }
            }
            var all: [(URL, CGFloat, UIImage?, Bool)] = []
            for await result in group { all.append(result) }
            return all
        }
        guard !Task.isCancelled else { return }
        var failures: [String] = []
        for (url, size, image, didFail) in results {
            if let image { remember(image, url: url, size: size) } else if didFail { failures.append(Self.key(url, size)) }
        }
        withAnimation(.easeOut(duration: 0.25)) {
            failed.formUnion(failures)
            revision += 1
        }
    }
}

/// The hero picture alone: no placeholder, no spinner, no fade of its own. Shown only while `isRevealed`, with the logo.
struct HeroPicture: View {
    let slot: HeroSlot
    let isRevealed: Bool
    let contentMode: ContentMode
    var alignment: Alignment = TitleHero.imageAlignment
    /// Shown until the picture is revealed (the title page's poster). Nil on Home, where the carousel must not show one.
    var placeholderURL: URL?

    var body: some View {
        ZStack {
            if !isRevealed, let placeholderURL {
                ArtworkImage(url: placeholderURL, maxPixelSize: 600, contentMode: contentMode, placeholderBlur: 0, imageAlignment: alignment)
            }
            Color.clear
                .overlay(alignment: alignment) {
                    if case .ready(let image) = slot {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    }
                }
                .opacity(isRevealed ? 1 : 0)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
#endif
