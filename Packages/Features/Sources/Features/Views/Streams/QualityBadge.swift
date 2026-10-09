#if canImport(UIKit)
import StremioKit
import SwiftUI

/// A stream's quality marker: a small SF Symbol and a short label in a hairline capsule. Sharpness and format are told apart by their
/// symbol first; colour is restrained. 4K alone carries the premium champagne accent, HDR a cool lilac, and everything else stays
/// white, so the sharpest stream stands out without the list turning loud.
struct QualityBadge: View {
    let title: String
    let symbol: String
    let tint: Color

    init(_ title: String, symbol: String, tint: Color = .white) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint.opacity(0.92))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
        .accessibilityElement(children: .combine)
    }
}

extension QualityBadge {
    /// The champagne of a 4K picture: the one premium accent on the list.
    static let premium = Color(red: 0.93, green: 0.82, blue: 0.62)
    /// A cool lilac for high dynamic range, quieter than the accent.
    static let dynamicRange = Color(red: 0.80, green: 0.76, blue: 0.98)

    static func resolution(_ label: String, is4K: Bool) -> QualityBadge {
        QualityBadge(label, symbol: is4K ? "4k.tv" : "tv", tint: is4K ? premium : .white)
    }

    static func source(_ kind: StreamSourceKind) -> QualityBadge {
        switch kind {
        case .bluray: QualityBadge("Blu-ray", symbol: "opticaldisc")
        case .webDL: QualityBadge("WEB-DL", symbol: "globe")
        case .webRip: QualityBadge("WEBRip", symbol: "globe")
        case .hdtv: QualityBadge("HDTV", symbol: "tv")
        case .dvd: QualityBadge("DVD", symbol: "opticaldisc")
        case .cam: QualityBadge("CAM", symbol: "video.slash")
        }
    }

    static let remux = QualityBadge("REMUX", symbol: "square.stack.3d.down.right")

    static func hdr(dolbyVision: Bool) -> QualityBadge {
        QualityBadge(dolbyVision ? "Dolby Vision" : "HDR", symbol: "sun.max", tint: dynamicRange)
    }
}
#endif
