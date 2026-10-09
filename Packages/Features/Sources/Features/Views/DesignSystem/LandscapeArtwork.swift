#if canImport(UIKit)
import SwiftUI

/// One darkened landscape image and centered logo, shared by Continue and landscape poster cards.
struct LandscapeArtwork: View {
    let title: String
    let artwork: URL?
    let logo: URL?
    let maxPixelSize: CGFloat
    @State private var logoImage: UIImage?

    init(title: String, artwork: URL?, logo: URL?, maxPixelSize: CGFloat) {
        self.title = title
        self.artwork = artwork
        self.logo = logo
        self.maxPixelSize = maxPixelSize
        _logoImage = State(initialValue: logo.flatMap { ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: 400) })
    }

    var body: some View {
        GeometryReader { geometry in
            ArtworkImage(url: artwork, maxPixelSize: maxPixelSize)
                .overlay { Color.black.opacity(0.32).allowsHitTesting(false) }
                .overlay {
                    Group {
                        if let logoImage {
                            Image(uiImage: logoImage).resizable().scaledToFit()
                        } else {
                            Text(title)
                                .font(Theme.Typography.cardTitle)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(width: geometry.size.width * 0.74, height: geometry.size.height * 0.38)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .allowsHitTesting(false)
                }
        }
        .accessibilityHidden(true)
        .task(id: logo) {
            guard let logo else { logoImage = nil; return }
            let image = try? await ImagePipeline.shared.image(for: logo, maxPixelSize: 400)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { logoImage = image }
        }
    }
}
#endif
