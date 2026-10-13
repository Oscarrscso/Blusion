#if canImport(UIKit)
import StremioKit
import SwiftUI

extension StreamProvider {
    /// The service's logo in the app's asset catalog, drawn as a template in the mark's ink. Nil for a service with no logo here, which
    /// shows its initials instead.
    var logoName: String? {
        switch self {
        case .netflix: "StreamLogoNetflix"
        case .primeVideo: "StreamLogoPrimeVideo"
        case .appleTV: "StreamLogoAppleTV"
        case .hboMax: "StreamLogoHBOMax"
        case .paramountPlus: "StreamLogoParamountPlus"
        case .crunchyroll: "StreamLogoCrunchyroll"
        case .disneyPlus, .hulu, .peacock: nil
        }
    }

    /// The initials of a service with no logo here, as the service sets them.
    var markText: String? {
        switch self {
        case .disneyPlus: "D+"
        case .hulu: "hulu"
        case .peacock: "P"
        case .netflix, .primeVideo, .appleTV, .hboMax, .paramountPlus, .crunchyroll: nil
        }
    }

    /// The ink on the mark, dark on the lighter tiles so the logo or initials stay legible.
    var markInk: Color {
        switch self {
        case .appleTV, .primeVideo, .hulu, .peacock: .black
        case .netflix, .disneyPlus, .hboMax, .paramountPlus, .crunchyroll: .white
        }
    }
}

/// A service's mark: a small tile in the service's colour with its logo, or its initials where there is no logo.
struct StreamProviderMark: View {
    let provider: StreamProvider

    var body: some View {
        Group {
            if let logo = provider.logoName {
                Image(logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
            } else if let text = provider.markText {
                Text(text)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
            }
        }
        .foregroundStyle(provider.markInk)
        .lineLimit(1)
        .fixedSize()
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
