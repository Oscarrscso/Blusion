#if canImport(UIKit)
import SwiftUI
import UIKit

/// Artwork that fills whatever frame it is given (aspect fill, clipped). While loading, or when there is no image, it shows a
/// flat grey placeholder with `title` centred in small secondary text; the image fades in. The caller sizes and clips it.
struct ArtworkImage: View {
    let url: URL?
    let title: String
    let maxPixelSize: CGFloat
    let contentMode: ContentMode
    let placeholderURL: URL?
    let placeholderBlur: CGFloat
    let imageAlignment: Alignment
    @Environment(\.displayScale) private var displayScale
    @State private var renderedSize: CGSize = .zero
    @State private var loadedPixelSize: CGFloat = 0

    private var pixelSize: CGFloat {
        guard maxPixelSize == 4096 else { return maxPixelSize }
        let pixels = max(renderedSize.width, renderedSize.height) * displayScale
        return min(4096, max(256, ceil(pixels / 128) * 128))
    }

    private var loadID: String { "\(url?.absoluteString ?? "")|\(Int(pixelSize))" }

    @State private var image: UIImage?
    /// The URL `image` was loaded for, so a view that re-appears keeps its picture instead of flashing the placeholder.
    @State private var imageURL: URL?
    @State private var placeholderImage: UIImage?

    init(url: URL?, title: String = "", maxPixelSize: CGFloat = 600, contentMode: ContentMode = .fill,
         placeholderURL: URL? = nil, placeholderBlur: CGFloat = 1, imageAlignment: Alignment = .center) {
        self.url = url
        self.title = title
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.placeholderURL = placeholderURL
        self.placeholderBlur = placeholderBlur
        self.imageAlignment = imageAlignment
        // Already decoded (the usual case when scrolling back): start with the picture, no placeholder frame and no fade.
        let cached = url.flatMap { ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: maxPixelSize) }
        _image = State(initialValue: cached)
        _loadedPixelSize = State(initialValue: cached == nil ? 0 : maxPixelSize)
        _imageURL = State(initialValue: cached == nil ? nil : url)
        _placeholderImage = State(initialValue: placeholderURL.flatMap { ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: 600) })
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
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .id(imageURL)
                        .transition(.opacity)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGSize.self) { maxPixelSize == 4096 ? $0.size : .zero } action: { renderedSize = $0 }
            .task(id: loadID) { await load() }
            .task(id: image == nil ? placeholderURL : nil) {
                guard image == nil, let placeholderURL else { return }
                let preview = try? await ImagePipeline.shared.image(for: placeholderURL, maxPixelSize: 600)
                guard !Task.isCancelled, image == nil else { return }
                withAnimation(.easeOut(duration: 0.1)) { placeholderImage = preview }
            }
    }

    /// Flat grey like the TV app's loading cards. No gradient: it is drawn once per card and must be cheap.
    private var placeholder: some View {
        ZStack {
            if contentMode == .fit { Theme.background } else { Theme.placeholder }
            if !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(8)
            }
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            imageURL = nil
            return
        }
        if maxPixelSize == 4096, renderedSize == .zero { return }
        let targetSize = pixelSize
        if imageURL == url, image != nil, loadedPixelSize >= targetSize { return }
        if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: targetSize) {
            withAnimation(.easeInOut(duration: placeholderURL == nil ? 0.35 : 0.15)) {
                image = cached
                imageURL = url
                loadedPixelSize = targetSize
                placeholderImage = nil
            }
            return
        }
        // Keep the current artwork visible while a replacement downloads.
        guard let loaded = try? await ImagePipeline.shared.image(for: url, maxPixelSize: targetSize), !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: placeholderURL == nil ? 0.35 : 0.15)) {
            image = loaded
            imageURL = url
            loadedPixelSize = targetSize
            placeholderImage = nil
        }
    }
}
#endif
