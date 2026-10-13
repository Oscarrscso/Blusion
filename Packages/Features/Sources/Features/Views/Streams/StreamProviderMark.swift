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

/// A service's mark: its logo on a small tile in the service's colour.
struct StreamProviderMark: View {
    let provider: StreamProvider

    var body: some View {
        Image(provider.logoName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 40, maxHeight: 14)
            .fixedSize()
            .foregroundStyle(provider.markInk)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 15)
            .background(provider.tint, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A web release's streaming service: its mark and name in the service's colour, where the source badge would stand.
struct StreamProviderBadge: View {
    let provider: StreamProvider

    var body: some View {
        HStack(spacing: 5) {
            StreamProviderMark(provider: provider)
            Text(provider.name)
        }
        .qualityBadgeChrome(tint: provider.tint)
    }
}
#endif
