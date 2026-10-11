#if canImport(UIKit)
import SwiftUI

/// The portrait hero's numbers, shared by Home's spotlight and the title page so that opening a title from one looks the same on the
/// other: the same picture size, fade, logo and placement. Both screens read them; change one here and both move together.
enum TitleHero {
    /// The share of the picture's height that the bottom fade covers.
    static let fadeLength = 0.42
    static let fadeStrength = 1.0
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
@MainActor @Observable
final class HeroLoader {
    /// Longest edge the logo is decoded to, on Home and on the title page.
    static let logoPixelSize: CGFloat = 800
    private var failed: Set<String> = []
    private var revision = 0

    nonisolated private static func key(_ url: URL, _ size: CGFloat) -> String { "\(Int(size))|\(url.absoluteString)" }

    /// A slot's state. A nil URL is pending until `lookupFinished`, then there is none.
    func slot(url: URL?, maxPixelSize: CGFloat, lookupFinished: Bool) -> HeroSlot {
        _ = revision
        guard let url else { return lookupFinished ? .none : .pending }
        if let image = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) { return .ready(image) }
        return failed.contains(Self.key(url, maxPixelSize)) ? .none : .pending
    }

    /// The one reveal condition: neither is still pending. A missing or failed one does not hold the other back.
    static func isRevealed(_ picture: HeroSlot, _ logo: HeroSlot) -> Bool { !picture.isPending && !logo.isPending }

    /// Starts the picture and the logo together at high priority and returns when both have finished. Does nothing until both URLs are
    /// known, or known to be absent (`lookupFinished`), so neither starts alone. The reveal is one state change in one transaction.
    func load(picture: URL?, pictureSize: CGFloat, logo: URL?, logoSize: CGFloat, lookupFinished: Bool) async {
        guard (picture != nil || lookupFinished), (logo != nil || lookupFinished) else { return }
        let wanted = [(picture, pictureSize), (logo, logoSize)].compactMap { url, size in
            url.map { ($0, size) }
        }.filter { ImagePipeline.shared.cachedImage(for: $0.0, maxPixelSize: $0.1) == nil }
        guard !wanted.isEmpty else { return }
        let failures = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for (url, size) in wanted {
                group.addTask {
                    do { _ = try await ImagePipeline.shared.image(for: url, maxPixelSize: size, priority: .high); return nil }
                    catch { return Task.isCancelled ? nil : Self.key(url, size) }
                }
            }
            var keys: [String] = []
            for await key in group { if let key { keys.append(key) } }
            return keys
        }
        guard !Task.isCancelled else { return }
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
