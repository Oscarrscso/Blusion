#if canImport(UIKit)
import StremioKit
import SwiftUI

extension StreamProvider {
    /// The service's logo in the app's asset catalog, drawn as a template in the mark's ink. Hulu shows the Disney+ logo, as the viewer
    /// chose: Hulu streams from the Disney+ app.
    var logoName: String {
        switch self {
        case .netflix: "StreamLogoNetflix"
        case .primeVideo: "StreamLogoPrimeVideo"
        case .appleTV: "StreamLogoAppleTV"
        case .hboMax: "StreamLogoHBOMax"
        case .paramountPlus: "StreamLogoParamountPlus"
        case .crunchyroll: "StreamLogoCrunchyroll"
        case .disneyPlus, .hulu: "StreamLogoDisneyPlus"
        case .peacock: "StreamLogoPeacock"
        }
    }

    /// The ink on the mark, dark on the lighter tiles so the logo stays legible.
    var markInk: Color {
        switch self {
        case .appleTV, .primeVideo, .hulu, .peacock: .black
        case .netflix, .disneyPlus, .hboMax, .paramountPlus, .crunchyroll: .white
        }
    }

    /// How large the logo is drawn against a tag's text height. Prime Video's icon is square, so it reads smaller than the wordmarks beside
    /// it and is drawn larger inside the same pill.
    var logoScale: CGFloat {
        switch self {
        case .primeVideo: 1.3
        case .netflix, .appleTV, .hboMax, .paramountPlus, .crunchyroll, .disneyPlus, .hulu, .peacock: 1
        }
    }
}

/// A service's logo at the height of a quality tag's line of text, so it lines up with the tags beside it.
struct StreamProviderMark: View {
    let provider: StreamProvider
    /// The height of the tags' text at the caption size, scaled with Dynamic Type the same way the tags' text is.
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 13

    var body: some View {
        Image(provider.logoName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height * provider.logoScale)
            .fixedSize()
            .foregroundStyle(provider.markInk)
    }
}

/// A web release's streaming service: its logo on a pill in the service's colour, the height and capsule shape of the quality tags beside it.
/// The pill is the badge itself, so the logo carries no second border and no name; VoiceOver reads the service's name.
struct StreamProviderBadge: View {
    let provider: StreamProvider
    /// A quality tag's height: its caption text with 3 pt of padding above and below. A logo can grow inside this height, never the pill.
    @ScaledMetric(relativeTo: .caption2) private var pillHeight: CGFloat = 19

    var body: some View {
        StreamProviderMark(provider: provider)
            .padding(.horizontal, 7)
            .frame(height: pillHeight)
            .background(provider.tint, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(provider.name)
    }
}
#endif
