#if canImport(UIKit)
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

private struct ArtworkLoadingSpinnerKey: EnvironmentKey { static let defaultValue = false }

private struct ArtworkPriorityKey: EnvironmentKey { static let defaultValue: TaskPriority = .medium }
private struct ArtworkOrderKey: EnvironmentKey { static let defaultValue: Int? = nil }

extension EnvironmentValues {
    var showsArtworkLoadingSpinner: Bool {
        get { self[ArtworkLoadingSpinnerKey.self] }
        set { self[ArtworkLoadingSpinnerKey.self] = newValue }
    }

    var artworkPriority: TaskPriority {
        get { self[ArtworkPriorityKey.self] }
        set { self[ArtworkPriorityKey.self] = newValue }
    }
    var artworkOrder: Int? {
        get { self[ArtworkOrderKey.self] }
        set { self[ArtworkOrderKey.self] = newValue }
    }
}

private struct VisibleArtworkPriority: ViewModifier {
    let order: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .environment(\.artworkPriority, isVisible ? .medium : .low)
            .environment(\.artworkOrder, order)
            .onScrollVisibility { isVisible = $0 }
    }
}

extension View {
    /// Visible Home rows first; ties follow the widget layout from top to bottom.
    func prioritizesArtwork(order: Int) -> some View { modifier(VisibleArtworkPriority(order: order)) }
}

/// Artwork that fills whatever frame it is given (aspect fill, clipped). While loading, or when there is no image, it shows a
/// flat grey skeleton; the image fades in. Missing artwork uses `title` as its fallback after loading finishes. The caller sizes and clips it.
struct ArtworkImage: View {
    let url: URL?
    let title: String
    /// Nil preserves the provider's complete source resolution, including decoded memory-cache hits.
    let maxPixelSize: CGFloat?
    let contentMode: ContentMode
    let placeholderURL: URL?
    let placeholderBlur: CGFloat
    /// Tried once, at the same size, when `url` fails to load. Nil, or the same URL as `url`, means no second try.
    let fallbackURL: URL?
    let imageAlignment: Alignment
    /// Keeps a sharp 16:9 top image and continues a lower band of it down the frame, blurring progressively towards the bottom.
    let extendsArtworkDownward: Bool
    /// True for a stand-in: a picture of `url` that is decoded at another size is shown as it is, so one the user has just seen is there
    /// in the first frame and nothing is loaded for it.
    let acceptsAnyCachedSize: Bool
    /// Told whether the picture on show is the fallback, so the caller can draw what the first choice would have carried itself.
    let usesFallback: Binding<Bool>?
    /// True for a card's poster. The picture it replaces stays opaque under the new one while that fades in, so no placeholder shows
    /// through. With `fallbackURL` (a BetterPosters picture over the usual poster), a decoded copy of the fallback, at any size, stands in
    /// from the first frame.
    let keepsPictureOnShow: Bool
    @Environment(\.showsArtworkLoadingSpinner) private var showsLoadingSpinner
    @Environment(\.artworkPriority) private var artworkPriority
    @Environment(\.artworkOrder) private var artworkOrder
    @Environment(\.loadsVisibleArtwork) private var sectionIsVisible
    @Environment(\.appAppearance) private var appearance

    @State private var hasFinishedLoading = false
    @State private var image: UIImage?
    /// The picture `image` replaced, held opaque under it while the new one fades in, so no placeholder shows through (see `show`).
    @State private var beneath: UIImage?
    /// Counts the pictures shown, so a fade that a newer one has overtaken knows not to clear what it left beneath.
    @State private var fadeCount = 0
    /// The URL `image` was loaded for, so a view that re-appears keeps its picture instead of flashing the placeholder.
    @State private var imageURL: URL?
    @State private var placeholderImage: UIImage?
    /// True while `image` came from `fallbackURL`.
    @State private var showsFallback: Bool

    init(url: URL?, title: String = "", maxPixelSize: CGFloat? = 600, contentMode: ContentMode = .fill,
         placeholderURL: URL? = nil, placeholderBlur: CGFloat = 1, fallbackURL: URL? = nil, imageAlignment: Alignment = .center,
         acceptsAnyCachedSize: Bool = false, usesFallback: Binding<Bool>? = nil, keepsPictureOnShow: Bool = false,
         extendsArtworkDownward: Bool = false) {
        self.url = url
        self.title = title
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.placeholderURL = placeholderURL
        self.placeholderBlur = placeholderBlur
        self.fallbackURL = fallbackURL
        self.imageAlignment = imageAlignment
        self.extendsArtworkDownward = extendsArtworkDownward
        self.acceptsAnyCachedSize = acceptsAnyCachedSize
        self.usesFallback = usesFallback
        self.keepsPictureOnShow = keepsPictureOnShow
        // Already decoded (the usual case when scrolling back): start with the picture, no placeholder frame and no fade.
        var cached = url.flatMap { Self.cachedPicture($0, maxPixelSize: maxPixelSize, anySize: acceptsAnyCachedSize) }
        var fellBack = false
        // The URL the first picture belongs to. Nil for a stand-in, so `load()` still fetches `url`.
        var shownURL = cached == nil ? nil : url
        if cached == nil, let url, let fallbackURL, fallbackURL != url {
            // A first choice that is known not to exist is not waited for again: its fallback, when decoded, is there at once too.
            if ImagePipeline.shared.isKnownMissing(url) {
                cached = ImagePipeline.shared.cachedImage(for: fallbackURL, maxPixelSize: maxPixelSize)
                fellBack = cached != nil
                shownURL = cached == nil ? nil : url
            }
            if cached == nil, keepsPictureOnShow, maxPixelSize != nil {
                cached = ImagePipeline.shared.cachedImageAtAnySize(for: fallbackURL)
                fellBack = cached != nil
            }
        }
        _image = State(initialValue: cached)
        _imageURL = State(initialValue: shownURL)
        _showsFallback = State(initialValue: fellBack)
        _placeholderImage = State(initialValue: placeholderURL.flatMap {
            ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: maxPixelSize == nil ? nil : 600)
        })
    }

    var body: some View {
        // Color.clear takes the size it is offered. The picture lives in an overlay, so its own pixel size never reaches the layout.
        Color.clear
            .overlay { placeholder }
            .overlay(alignment: imageAlignment) {
                if image == nil, let placeholderImage {
                    Image(uiImage: placeholderImage)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .blur(radius: placeholderBlur)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: imageAlignment) {
                if let beneath {
                    picture(beneath)
                }
            }
            .overlay(alignment: imageAlignment) {
                if let image {
                    picture(image)
                        .id(imageURL)
                        .transition(.opacity)
                }
            }
            .clipped()
            .loadingCardSpinner(showsLoadingSpinner && url != nil && image == nil && placeholderImage == nil && !hasFinishedLoading)
            .accessibilityHidden(true)
            // Stretching changes only the frame; it must not restart the download, decode or fade.
            // Lazy containers create nearby cards before they enter the viewport. Fill them now, including from the Far buffer.
            .task(id: sectionIsVisible ? [url, fallbackURL] : []) {
                guard sectionIsVisible else { return }
                await load()
            }
            // Promote an existing queued request when its row scrolls on screen, without restarting its download.
            .task(id: "\(url?.absoluteString ?? "-")|\(artworkPriority.rawValue)|\(artworkOrder ?? -1)") {
                guard let url, artworkOrder != nil else { return }
                await ImagePipeline.shared.prioritize(url, maxPixelSize: maxPixelSize, priority: artworkPriority, order: artworkOrder)
                if let fallbackURL {
                    await ImagePipeline.shared.prioritize(fallbackURL, maxPixelSize: maxPixelSize,
                                                           priority: artworkPriority, order: artworkOrder)
                }
            }
            .onChange(of: showsFallback, initial: true) { _, fellBack in usesFallback?.wrappedValue = fellBack }
            .task(id: image == nil && sectionIsVisible ? placeholderURL : nil) {
                guard sectionIsVisible, image == nil, let placeholderURL else { return }
                let preview = try? await ImagePipeline.shared.image(for: placeholderURL, maxPixelSize: maxPixelSize == nil ? nil : 600,
                                                                    priority: artworkPriority, order: artworkOrder)
                guard !Task.isCancelled, image == nil else { return }
                withAnimation(.easeOut(duration: 0.1)) { placeholderImage = preview }
            }
    }

    @ViewBuilder
    private func picture(_ image: UIImage) -> some View {
        if extendsArtworkDownward {
            ExtendedArtwork(image: image)
        } else {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        }
    }

    /// Flat grey like the TV app's loading cards. No gradient: it is drawn once per card and must be cheap.
    private var placeholder: some View {
        ZStack {
            if contentMode == .fit { appearance.pageBackground } else { Theme.placeholder }
            if !title.isEmpty && (url == nil || hasFinishedLoading) {
                Text(title)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(8)
            }
        }
    }

    private func load() async {
        hasFinishedLoading = false
        defer { if !Task.isCancelled { hasFinishedLoading = true } }
        guard let url else {
            image = nil
            beneath = nil
            imageURL = nil
            showsFallback = false
            return
        }
        if imageURL == url, image != nil { return }
        // The picture on show is still the fallback while `url` loads over it, so the caller keeps drawing what the fallback lacks.
        if keepsPictureOnShow, image != nil, let fallbackURL, imageURL == fallbackURL { showsFallback = true }
        if let cached = Self.cachedPicture(url, maxPixelSize: maxPixelSize, anySize: acceptsAnyCachedSize) {
            await show(cached, url: url, fellBack: false)
            return
        }
        // Keep the current artwork visible while a replacement downloads.
        guard let loaded = try? await download(url), !Task.isCancelled else { return }
        await show(loaded.image, url: url, fellBack: loaded.isFallback)
    }

    /// Fades `picture` in over the one on show. For a poster, the one on show stays opaque beneath until the fade is over, so the
    /// placeholder never shows through: a BetterPosters picture replacing the usual poster, or the reverse, goes straight from one to the other.
    private func show(_ picture: UIImage, url: URL, fellBack: Bool) async {
        let duration = placeholderURL == nil ? 0.35 : 0.15
        let previous = image
        fadeCount += 1
        let fade = fadeCount
        beneath = keepsPictureOnShow ? previous : nil
        withAnimation(.easeInOut(duration: duration)) {
            image = picture
            imageURL = url
            placeholderImage = nil
            showsFallback = fellBack
        }
        guard keepsPictureOnShow, previous != nil else { return }
        // A cancelled fade leaves `beneath` under an opaque picture until the next change replaces it.
        do { try await Task.sleep(for: .seconds(duration + 0.05)) } catch { return }
        // Only the latest fade clears `beneath`, so an older one cannot clear it while a newer one still fades.
        if fadeCount == fade { beneath = nil }
    }

    /// The decoded picture of `url` at this view's size, or, for a stand-in, at any size.
    private static func cachedPicture(_ url: URL, maxPixelSize: CGFloat?, anySize: Bool) -> UIImage? {
        if let exact = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) { return exact }
        return maxPixelSize != nil && anySize ? ImagePipeline.shared.cachedImageAtAnySize(for: url) : nil
    }

    /// The picture at `url`, or at `fallbackURL` once when `url` fails. A load that was cancelled does not try the fallback.
    private func download(_ url: URL) async throws -> (image: UIImage, isFallback: Bool) {
        do {
            return (try await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize,
                                                         priority: artworkPriority, order: artworkOrder), false)
        } catch {
            guard !Task.isCancelled, let fallbackURL, fallbackURL != url else { throw error }
            return (try await ImagePipeline.shared.image(for: fallbackURL, maxPixelSize: maxPixelSize,
                                                         priority: artworkPriority, order: artworkOrder), true)
        }
    }
}

/// The still in a sharp 16:9 frame, continued down the card by a lower band of its own colours: one picture that stays sharp through
/// most of the still while the blur grows near its foot and into the text. Rendered off the main thread once per still and size, and
/// kept for scrolling back.
private struct ExtendedArtwork: View {
    let image: UIImage
    @Environment(\.displayScale) private var displayScale
    /// The latest rendering. It stands in, stretched, while a new size renders.
    @State private var rendered: UIImage?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let key = Self.key(image, size: size, scale: displayScale)
            ZStack {
                if let picture = Self.cached(image, key: key) ?? rendered {
                    Image(uiImage: picture).resizable()
                }
            }
            .frame(width: size.width, height: size.height)
            .task(id: key) { await render(size: size, key: key) }
        }
    }

    private func render(size: CGSize, key: NSString) async {
        guard size.width >= 1, size.height >= 1, Self.cached(image, key: key) == nil else { return }
        // A card being resized waits for its size to settle, so an animated width does not render every frame.
        if rendered != nil {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        }
        let source = image, scale = displayScale
        guard let picture = await Task.detached(priority: .userInitiated, operation: {
            ExtendedArtworkRenderer.render(source, size: size, scale: scale)
        }).value else { return }
        // Kept even when the card has scrolled away, so coming back finds it.
        let bytes = picture.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        Self.cache.setObject(Rendering(source: source, picture: picture), forKey: key, cost: bytes)
        guard !Task.isCancelled else { return }
        if rendered == nil {
            withAnimation(.easeOut(duration: 0.2)) { rendered = picture }
        } else {
            rendered = picture
        }
    }

    private static let cache: NSCache<NSString, Rendering> = {
        let cache = NSCache<NSString, Rendering>()
        cache.totalCostLimit = 96 << 20
        return cache
    }()

    private static func key(_ image: UIImage, size: CGSize, scale: CGFloat) -> NSString {
        "\(UInt(bitPattern: ObjectIdentifier(image)))-\(Int((size.width * scale).rounded()))x\(Int((size.height * scale).rounded()))" as NSString
    }

    private static func cached(_ image: UIImage, key: NSString) -> UIImage? {
        guard let rendering = cache.object(forKey: key), rendering.source === image else { return nil }
        return rendering.picture
    }

    private final class Rendering {
        /// Weak, so a later picture at the same address is not taken for this one.
        weak var source: UIImage?
        let picture: UIImage
        init(source: UIImage, picture: UIImage) {
            self.source = source
            self.picture = picture
        }
    }
}

/// Builds `ExtendedArtwork`'s picture. Positions are shares of the still's height from the card's top, so the ramp sits on the still
/// whatever the text below it measures.
enum ExtendedArtworkRenderer {
    /// Gamma-encoded, as UIKit composites, so the veil reads as its numbers say.
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB) as Any,
        .cacheIntermediates: false,
    ])
    /// Sharp above `blurStart`, so hands and props low in the still keep their detail; the blur eases in to its full radius at `blurEnd`.
    /// Shares of the still's height from the card's top.
    private static let blurStart = 0.8, blurEnd = 1.45, blurRadius = 0.18
    /// The thin strip at the still's foot whose colours run down the card, so hands and shirts carry on as soft streaks behind the text.
    private static let band = 0.08
    /// A veil of mid-grey behind the text, apart from the blur: it pulls whites down and lifts darks, as the TV app's cards do, so
    /// the text reads on both. It starts late, so the still's lightest colours run on past its edge first.
    private static let veilStart = 0.8, veilEnd = 1.7, veilAmount = 0.68, veilGrey = 0.3
    /// A darker charcoal veil for title-page poster backdrops so bright posters cannot wash out `Theme.metaText`, `Theme.faintText`,
    /// `Theme.surface`, and section dividers, while saturated poster colours remain recognizable.
    private static let backdropVeilAmount = 0.75, backdropVeilGrey = 0.06

    static func render(_ image: UIImage, size: CGSize, scale: CGFloat) -> UIImage? {
        let width = (size.width * scale).rounded(), height = (size.height * scale).rounded()
        guard width >= 1, height >= 1, var source = image.cgImage.map({ CIImage(cgImage: $0) }) ?? image.ciImage else { return nil }
        source = source.oriented(CGImagePropertyOrientation(image.imageOrientation))
        source = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        guard source.extent.width >= 1, source.extent.height >= 1 else { return nil }

        // Core Image counts up from the bottom: the still fills the top `still` pixels, down to `seam`.
        let still = (width * 9 / 16).rounded()
        let seam = height - still
        let scaler = CIFilter.lanczosScaleTransform()
        scaler.inputImage = source.clampedToExtent()
        scaler.scale = Float(max(width / source.extent.width, still / source.extent.height))
        scaler.aspectRatio = 1
        let scaledWidth = source.extent.width * CGFloat(scaler.scale)
        let scaledHeight = source.extent.height * CGFloat(scaler.scale)
        guard let scaled = scaler.outputImage else { return nil }
        let frame = scaled
            .transformed(by: CGAffineTransform(translationX: -(scaledWidth - width) / 2,
                                               y: seam - (scaledHeight - still) / 2))
            .cropped(to: CGRect(x: 0, y: seam, width: width, height: still))

        // The still's lower band, mirrored at its edge and stretched to the card's foot: the colours meet the still without a seam
        // and each stays under the column it came from.
        var canvas = frame
        if seam >= 1 {
            let bandHeight = max(1, (still * band).rounded())
            let stretch = seam / bandHeight
            let below = frame.cropped(to: CGRect(x: 0, y: seam, width: width, height: bandHeight))
                .transformed(by: CGAffineTransform(translationX: 0, y: -seam))
                .clampedToExtent()
                .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -stretch, tx: 0, ty: seam))
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: seam))
            canvas = frame.composited(over: below)
        }

        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = canvas.clampedToExtent()
        blur.mask = ramp(blurStart, blurEnd, still: still, height: height,
                         from: CIColor(red: 0, green: 0, blue: 0), to: CIColor(red: 1, green: 1, blue: 1))
        blur.radius = Float(still * blurRadius)

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        guard let blurred = blur.outputImage,
              let shade = ramp(veilStart, veilEnd, still: still, height: height,
                               from: CIColor(red: veilGrey, green: veilGrey, blue: veilGrey, alpha: 0),
                               to: CIColor(red: veilGrey, green: veilGrey, blue: veilGrey, alpha: veilAmount)),
              let pixels = context.createCGImage(shade.composited(over: blurred).cropped(to: bounds), from: bounds) else { return nil }
        return UIImage(cgImage: pixels, scale: scale, orientation: .up)
    }

    /// A vertical ramp, eased at both ends, from `from` at `start` to `to` at `end`: shares of the still's height from the card's top.
    private static func ramp(_ start: Double, _ end: Double, still: CGFloat, height: CGFloat, from: CIColor, to: CIColor) -> CIImage? {
        let gradient = CIFilter.smoothLinearGradient()
        gradient.point0 = CGPoint(x: 0, y: height - still * start)
        gradient.point1 = CGPoint(x: 0, y: height - still * end)
        gradient.color0 = from
        gradient.color1 = to
        return gradient.outputImage
    }

    /// A thin strip from the visible picture's bottom or leading edge, with the card's blur and a dark charcoal veil.
    /// Bottom colours run down the page; leading-edge colours run across it, retaining their top-to-bottom order.
    static func backdrop(_ request: TitleBackdropRequest) -> UIImage? {
        // A blurred background needs few pixels; cap the new two-dimensional rendering work.
        let scale = min(request.scale, 320 / max(1, request.pageWidth))
        let pageWidth = (request.pageWidth * scale).rounded()
        let frameWidth = request.frame.width * scale, frameHeight = request.frame.height * scale
        guard pageWidth >= 1, frameWidth >= 1, frameHeight >= 1,
              var picture = request.image.cgImage.map({ CIImage(cgImage: $0) }) ?? request.image.ciImage else { return nil }
        picture = picture.oriented(CGImagePropertyOrientation(request.image.imageOrientation))
        picture = picture.transformed(by: CGAffineTransform(translationX: -picture.extent.minX, y: -picture.extent.minY))
        picture = PosterBackdropColours.repair(picture, source: request.image, context: context)
        let imageWidth = picture.extent.width, imageHeight = picture.extent.height
        guard imageWidth >= 1, imageHeight >= 1 else { return nil }

        // The picture as the hero draws it: filling its frame, centred across it, from the frame's top or its middle. Core Image counts
        // up from the bottom.
        let fill = max(frameWidth / imageWidth, frameHeight / imageHeight)
        let left = (frameWidth - imageWidth * fill) / 2
        let top = request.alignsTop ? 0 : (frameHeight - imageHeight * fill) / 2
        let bottom = min(max(1, request.visibleBottom * scale), frameHeight)
        let bandRect = (request.samplesLeadingEdge
            ? CGRect(x: -left / fill, y: imageHeight - (bottom - top) / fill,
                     width: max(1, frameWidth * band) / fill, height: bottom / fill)
            : CGRect(x: -left / fill, y: imageHeight - (bottom - top) / fill,
                     width: frameWidth / fill, height: max(1, bottom * band) / fill))
                .intersection(picture.extent)
        guard bandRect.width >= 1, bandRect.height >= 1 else { return nil }

        let stripSize = request.samplesLeadingEdge ? CGSize(width: 1, height: bottom)
            : CGSize(width: frameWidth, height: max(1, bottom * band))
        let scaler = CIFilter.lanczosScaleTransform()
        scaler.inputImage = picture.cropped(to: bandRect)
            .transformed(by: CGAffineTransform(translationX: -bandRect.minX, y: -bandRect.minY))
            .clampedToExtent()
        scaler.scale = Float(stripSize.height / bandRect.height)
        scaler.aspectRatio = Float(stripSize.width / bandRect.width * bandRect.height / stripSize.height)
        guard let strip = scaler.outputImage?.cropped(to: CGRect(origin: .zero, size: stripSize)) else { return nil }

        let height = request.samplesLeadingEdge ? bottom : frameHeight
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: height)
        let canvas: CIImage
        if request.samplesLeadingEdge {
            canvas = strip.clampedToExtent()
        } else {
            // Mirror the edge band as the card does: colours continue away from the edge instead of flattening into one row.
            canvas = strip.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -height / stripSize.height,
                                                            tx: pageWidth + request.trailingOverhang * scale - frameWidth, ty: height))
                .clampedToExtent()
        }
        let spread = CIFilter.smoothLinearGradient()
        spread.point0 = request.samplesLeadingEdge ? CGPoint(x: pageWidth, y: 0) : CGPoint(x: 0, y: height)
        spread.point1 = .zero
        spread.color0 = CIColor(red: 0, green: 0, blue: 0)
        spread.color1 = CIColor(red: 1, green: 1, blue: 1)
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = canvas
        blur.mask = spread.outputImage
        blur.radius = Float(pageWidth * 9 / 16 * blurRadius)

        let veil = CIImage(color: CIColor(red: backdropVeilGrey, green: backdropVeilGrey, blue: backdropVeilGrey, alpha: backdropVeilAmount))
            .cropped(to: bounds)
        guard let blurred = blur.outputImage,
              let pixels = context.createCGImage(veil.composited(over: blurred).cropped(to: bounds), from: bounds) else { return nil }
        return UIImage(cgImage: pixels, scale: scale, orientation: .up)
    }
}

/// Appearance's Blurred background: a strip from the hero picture's bottom, or its leading side in the landscape title layout.
/// The strip stretches across the page with the same blur and veil as the bottom-edge background.
struct TitleBackdropRequest: Equatable, Sendable {
    let image: UIImage
    /// The frame the hero fills with the picture, and how far down it the picture shows.
    let frame: CGSize
    let visibleBottom: CGFloat
    /// The picture sits at its frame's top (portrait) rather than its middle.
    let alignsTop: Bool
    /// Landscape title artwork sits beside the text, so extend its leading edge across the page.
    var samplesLeadingEdge: Bool = false
    /// How far the frame's trailing edge runs past the page's.
    var trailingOverhang: CGFloat = 0
    var pageWidth: CGFloat = 0
    var scale: CGFloat = 1

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.image === rhs.image && lhs.frame == rhs.frame && lhs.visibleBottom == rhs.visibleBottom && lhs.alignsTop == rhs.alignsTop
            && lhs.samplesLeadingEdge == rhs.samplesLeadingEdge && lhs.trailingOverhang == rhs.trailingOverhang
            && lhs.pageWidth == rhs.pageWidth && lhs.scale == rhs.scale
    }

    func render() -> UIImage? { ExtendedArtworkRenderer.backdrop(self) }
}

extension EnvironmentValues {
    /// The title page's Blurred background, while it has one. `BottomFade` fades into it in place of the page's colour.
    @Entry var pageBackdrop: UIImage?
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        default: self = .up
        }
    }
}

#endif
