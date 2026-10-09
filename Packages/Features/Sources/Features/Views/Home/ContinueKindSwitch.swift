#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Which titles the Continue Watching rail shows: everything, movies, or series (each episode counts as its series).
enum ContinueKind: String, CaseIterable, Identifiable {
    case all, movies, series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .movies: "Movies"
        case .series: "Series"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .movies: "film"
        case .series: "tv"
        }
    }

    func includes(_ request: StreamRequest) -> Bool {
        switch self {
        case .all: true
        case .movies: request.type != "series"
        case .series: request.type == "series"
        }
    }
}

/// A compact Liquid Glass pill of two SF Symbols, film and tv, with a sliding white segment for the active one. It sits at the trailing
/// end of the Continue Watching header, so it takes no more width than an icon. Each segment's touch area is larger than what it draws.
struct ContinueKindSwitch: View {
    @Binding var selection: ContinueKind
    @Namespace private var segment

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ContinueKind.allCases) { kind in
                let isSelected = selection == kind
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = kind }
                } label: {
                    Image(systemName: kind.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                        .frame(width: 36, height: 30)
                        .background {
                            if isSelected {
                                Capsule().fill(.white).matchedGeometryEffect(id: "segment", in: segment)
                            }
                        }
                        .contentShape(Rectangle().inset(by: -7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityLabel(kind.title)
                .accessibilityIdentifier("continue.kind.\(kind.rawValue)")
            }
        }
        .padding(3)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }
}
#endif
