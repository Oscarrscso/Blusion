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
            .frame(height: height)
            .fixedSize()
            .foregroundStyle(provider.markInk)
    }
}

/// A web release's streaming service: its logo on a pill in the service's colour, the same height and capsule shape as the quality tags beside
/// it. The pill is the badge itself, so the logo carries no second border and no name; VoiceOver reads the service's name.
struct StreamProviderBadge: View {
    let provider: StreamProvider

    var body: some View {
        StreamProviderMark(provider: provider)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(provider.tint, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(provider.name)
    }
}
#endif
