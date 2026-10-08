#if canImport(UIKit)
import SwiftUI
import UIKit

/// Artwork that fills whatever frame it is given (aspect fill, clipped). While loading, or when there is no image, it shows a
/// dark placeholder with `title` centred in small secondary text; the image fades in. The caller sizes and clips it.
struct ArtworkImage: View {
    let url: URL?
    let title: String
    let maxPixelSize: CGFloat

    @State private var image: UIImage?
    /// The URL `image` was loaded for, so a view that re-appears keeps its picture instead of flashing the placeholder.
    @State private var imageURL: URL?

    init(url: URL?, title: String = "", maxPixelSize: CGFloat = 600) {
        self.url = url
        self.title = title
        self.maxPixelSize = maxPixelSize
        // Already decoded (the usual case when scrolling back): start with the picture, no placeholder frame and no fade.
        let cached = url.flatMap { ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: maxPixelSize) }
        _image = State(initialValue: cached)
        _imageURL = State(initialValue: cached == nil ? nil : url)
    }

    var body: some View {
        // Color.clear takes the size it is offered. The picture lives in an overlay, so its own pixel size never reaches the layout.
        Color.clear
            .overlay { placeholder }
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: url) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.15, green: 0.15, blue: 0.19), Color(red: 0.06, green: 0.06, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(8)
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            imageURL = nil
            return
        }
        if imageURL == url, image != nil { return }
        if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            image = cached
            imageURL = url
            return
        }
        image = nil
        imageURL = nil
        guard let loaded = try? await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize), !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        imageURL = url
    }
}
#endif
