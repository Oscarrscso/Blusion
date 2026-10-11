#if canImport(UIKit)
import SwiftUI

/// The portrait hero's numbers, shared by Home's spotlight and the title page so that opening a title from one looks the same on the
/// other: the same picture size, fade, logo and placement. Both screens read them; change one here and both move together.
enum TitleHero {
    /// The portrait picture is drawn this much larger than its frame (see `pictureHeight`).
    static let zoom: CGFloat = 1.15
    /// The length of the bottom fade, as a share of the unzoomed hero height. The fade keeps that length however far the picture runs.
    static let fadeShare = 0.42
    static let fadeStrength = 1.0
    /// How far the bottom fade runs past the picture's bottom edge, so no row of picture pixels shows under it while the page moves.
    static let fadeOverscan: CGFloat = 2
    /// The tallest logo, bottom-aligned above the gap to the text.
    static let logoMaxHeight: CGFloat = 150
    /// The gap between the bottom of the logo and the text under it (the metadata line), on the title page and on Home's spotlight alike.
    /// The text starts at the picture's bottom edge, so the logo stops this far above that edge.
    static let logoTextGap = Theme.Spacing.s
    /// The longest edge the picture is decoded to. Smaller than full screen, so the neighbouring pages keep it in the image cache.
    static let portraitPixelSize: CGFloat = 2048
    /// The longest edge the stand-in poster is decoded to. `ArtworkImage` decodes its own stand-in at this size too, and Home preloads the
    /// poster at it, so the stand-in is ready at once.
    static let placeholderPixelSize: CGFloat = 600
    static let imageAlignment = Alignment.top
    /// The blur on the stand-in poster while the picture loads, kept opaque at the edges (see `HeroPicture`).
    static let placeholderBlur: CGFloat = 2
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

    /// The height of the zoomed portrait picture on a hero `height` tall. The picture is zoomed, so it is taller than the hero and reaches
    /// below its bottom edge, behind the text.
    static func pictureHeight(_ height: CGFloat) -> CGFloat { height * zoom }

    /// How much of the zoomed picture shows: it ends, fully faded to black, half way up the logo's space (the logo sits `logoTextGap`
    /// above the hero's bottom edge and is up to `logoMaxHeight` tall).
    static func visibleHeight(_ height: CGFloat) -> CGFloat {
        min(pictureHeight(height), max(1, height - logoTextGap - logoMaxHeight / 2))
    }

    /// The bottom fade's share of the visible picture, `fadeShare` of the hero height.
    static func fadeLength(height: CGFloat, visible: CGFloat) -> Double { fadeShare * Double(height / max(visible, 1)) }
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

    /// The logo cropped to its visible pixels (see `LogoTrim`), so every title's logo-to-text gap is the same.
    private static func trimmedLogo(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let trimmed = LogoTrim.trimmed(cgImage)
        return trimmed === cgImage ? image : UIImage(cgImage: trimmed, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func storeLogo(_ image: UIImage, for url: URL) {
        let key = key(url, logoPixelSize)
        let image = trimmedLogo(image)
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

    /// Remembers an image that has been resolved: logos in the shared store, pictures in this loader. A logo that is stored already is kept.
    private func remember(_ image: UIImage, url: URL, size: CGFloat) {
        if size == Self.logoPixelSize {
            if Self.storedLogo(url) == nil { Self.storeLogo(image, for: url) }
        } else {
            held[Self.key(url, size)] = image
        }
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

    /// Starts the picture and the logo as soon as each one's URL is known, and returns when both have finished. Neither waits for the other, so a
    /// logo the addon supplies starts while the picture's lookup is still running. The reveal still needs both (`isRevealed`), so a logo that
    /// arrives first is not shown early. `urgent` lets the picture and logo skip the pipeline's queue (see `ImagePipeline.image`).
    func load(priority: TaskPriority = .high, urgent: Bool = false, picture: URL?, pictureSize: CGFloat, logo: URL?, logoSize: CGFloat) async {
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
                let isLogo = size == Self.logoPixelSize
                group.addTask {
                    do {
                        let image = try await Self.download(url, size: size, isLogo: isLogo, priority: priority, urgent: urgent)
                        return (url, size, image, false)
                    } catch { return (url, size, nil, !Task.isCancelled) }
                }
            }
            var all: [(URL, CGFloat, UIImage?, Bool)] = []
            for await result in group { all.append(result) }
            return all
        }
        // Kept even when this load was cancelled: a logo that finished is stored, and the revision moves so the page shows it.
        var failures: [String] = []
        for (url, size, image, didFail) in results {
            if let image { remember(image, url: url, size: size) } else if didFail { failures.append(Self.key(url, size)) }
        }
        withAnimation(.easeOut(duration: 0.25)) {
            failed.formUnion(failures)
            revision += 1
        }
    }

    /// Downloads one picture or logo. A picture belongs to the load that asked for it, so cancelling the load stops it. A logo runs in a task of
    /// its own: a load that is cancelled (a page's task restarts when its picture's URL arrives) leaves it going, and the next load for the logo
    /// joins the same download in the pipeline rather than starting another.
    nonisolated private static func download(_ url: URL, size: CGFloat, isLogo: Bool, priority: TaskPriority, urgent: Bool) async throws -> UIImage {
        guard isLogo else {
            return try await ImagePipeline.shared.image(for: url, maxPixelSize: size, priority: priority, urgent: urgent)
        }
        return try await Task(priority: priority) {
            try await ImagePipeline.shared.image(for: url, maxPixelSize: size, priority: priority, urgent: urgent)
        }.value
    }
}

/// The hero picture, drawn over the poster it stands in with until the picture is revealed. The stand-in is a larger copy of the poster (see
/// `PosterQuality.placeholder`), slightly blurred and with a spinner over it, and the poster as it came shows first underneath. The picture
/// itself is shown only while `isRevealed`, with the logo.
struct HeroPicture: View {
    let slot: HeroSlot
    let isRevealed: Bool
    let contentMode: ContentMode
    var alignment: Alignment = TitleHero.imageAlignment
    /// The addon's poster as it came, which stands in until the picture is revealed. Nil draws no stand-in.
    var placeholderURL: URL?

    private var hasPicture: Bool {
        if case .ready = slot { return true }
        return false
    }

    var body: some View {
        ZStack {
            if !isRevealed, let placeholderURL {
                // Stays fully opaque while the picture fades in over it (the reveal lasts 0.25 s), then goes unseen. With no picture to
                // reveal it goes as it did, with a fade.
                ArtworkImage(url: PosterQuality.placeholder(placeholderURL), maxPixelSize: TitleHero.placeholderPixelSize,
                             contentMode: contentMode, placeholderURL: placeholderURL, placeholderBlur: 0, imageAlignment: alignment)
                    // One blur over whichever poster is showing, the small one or the larger one that replaces it.
                    .blur(radius: TitleHero.placeholderBlur, opaque: true)
                    .overlay {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                            .accessibilityHidden(true)
                    }
                    .transition(hasPicture ? .asymmetric(insertion: .identity, removal: .opacity.animation(.linear(duration: 0.01).delay(0.3)))
                                           : .opacity)
            }
            Color.clear
                .overlay(alignment: alignment) {
                    if case .ready(let image) = slot {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .transition(.identity)
                    }
                }
                .opacity(isRevealed ? 1 : 0)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The title on a portrait hero: the logo, or the name when there is no logo or it failed to load. The title page and Home's spotlight both
/// show it this way, so the logo sits the same distance above the text under it on both. The logo comes from the shared hero loader and is
/// revealed with the picture. While it is pending the name is not drawn, and its full height is kept, so the text below does not move when it
/// arrives.
struct HeroTitleArt: View {
    let name: String
    let slot: HeroSlot
    let alignment: Alignment
    let compact: Bool
    /// Draws nothing, not even the name, but keeps the logo's space, for a portrait picture that already carries the title.
    var hidden = false

    /// The tallest a logo can be on this page.
    private var logoHeight: CGFloat { compact ? TitleHero.landscapeLogoMaxHeight : TitleHero.logoMaxHeight }
    /// Whether the slot has no logo: no URL once the lookup has finished, or a failed load.
    private var isNone: Bool {
        if case .none = slot { return true }
        return false
    }
    /// A title keeps the logo's space until the logo is ready or known to be absent.
    private var reservesLogoHeight: Bool { !isNone || hidden }

    var body: some View {
        Group {
            if hidden {
                Color.clear.frame(height: 0)
            } else if case .ready(let image) = slot {
                LogoLayout(imageSize: image.size, maxWidth: compact ? TitleHero.landscapeLogoMaxWidth : .infinity, maxHeight: logoHeight) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                // Revealed by the page's opacity alone, on the same curve as the picture.
                .transition(.identity)
            } else {
                Text(name)
                    .font(compact ? .title2.bold() : .largeTitle.bold())
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .foregroundStyle(.white)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    // A logo ends at its last visible pixel; the name's frame ends a descender lower, so that space is taken back and the
                    // text under either sits the same distance from what can be seen.
                    .padding(.bottom, -abs(UIFont.preferredFont(forTextStyle: compact ? .title2 : .largeTitle).descender))
                    .opacity(isNone ? 1 : 0)
                    .transition(.identity)
            }
        }
        // Bottom-aligned, so a logo shorter than the reserved space sits where it did before, just above the text under it.
        .frame(minHeight: reservesLogoHeight ? logoHeight : nil, alignment: Alignment(horizontal: alignment.horizontal, vertical: .bottom))
    }
}

/// Reports the fitted image bounds instead of a taller frame containing empty space.
struct LogoLayout: Layout {
    let imageSize: CGSize
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let width = min(proposal.width ?? imageSize.width, maxWidth)
        let scale = min(width / imageSize.width, maxHeight / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// A title's logo for Home's landscape caption, fitted into a box of fixed size so the text under it never moves when it arrives.
struct HeroLogo: View {
    static let box = CGSize(width: 260, height: 84)

    let image: UIImage

    var body: some View {
        Color.clear
            .frame(width: Self.box.width, height: Self.box.height)
            .overlay(alignment: .bottom) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
    }
}
#endif
