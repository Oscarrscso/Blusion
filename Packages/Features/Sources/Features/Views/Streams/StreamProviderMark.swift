#if canImport(UIKit)
import StremioKit
import SwiftUI

extension StreamProvider {
    /// The initials on the service's mark, as the service sets them. Apple TV+ has none: its mark is Apple's own logo.
    var markText: String? {
        switch self {
        case .netflix: "N"
        case .primeVideo: "prime"
        case .appleTV: nil
        case .disneyPlus: "D+"
        case .hboMax: "HBO"
        case .hulu: "hulu"
        case .paramountPlus: "P+"
        case .peacock: "P"
        case .crunchyroll: "CR"
        }
    }

    /// The ink on the mark, dark on the lighter tiles so the initials stay legible.
    var markInk: Color {
        switch self {
        case .appleTV, .hulu, .peacock: .black
        case .netflix, .primeVideo, .disneyPlus, .hboMax, .paramountPlus, .crunchyroll: .white
        }
    }
}

/// A service's mark: a small tile in the service's colour with its initials, or Apple's logo for Apple TV+.
struct StreamProviderMark: View {
    let provider: StreamProvider

    var body: some View {
        Group {
            if let text = provider.markText {
                Text(text)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
            } else {
                Image(systemName: "applelogo")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(provider.markInk)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 3)
        .frame(minWidth: 16, minHeight: 13)
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
