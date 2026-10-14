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

    /// How large the logo is drawn within its box. Prime Video's icon is square, so it reads smaller than the wordmarks beside it and is
    /// drawn larger in the same box.
    var logoScale: CGFloat {
        switch self {
        case .primeVideo: 1.3
        case .netflix, .appleTV, .hboMax, .paramountPlus, .crunchyroll, .disneyPlus, .hulu, .peacock: 1
        }
    }
}

/// A web release's streaming service: its logo in a box of the service's colour, set to the left of the release name. VoiceOver reads
/// the service's name.
struct StreamProviderBox: View {
    let provider: StreamProvider
    /// The box's size. The logo is fitted inside a margin within it, so a wide wordmark and a square icon both sit in the box.
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 52
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 36

    var body: some View {
        Image(provider.logoName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: (width - 12) * provider.logoScale, maxHeight: (height - 14) * provider.logoScale)
            .foregroundStyle(provider.markInk)
            .frame(width: width, height: height)
            .background(provider.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(provider.name)
    }
}
#endif
