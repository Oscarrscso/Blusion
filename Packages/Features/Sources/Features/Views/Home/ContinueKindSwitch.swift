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

/// The shared glass pill: compact icons on Continue, or icons and text on Discover.
struct ContinueKindSwitch: View {
    @Binding var selection: ContinueKind
    var kinds = ContinueKind.allCases
    var showsTitles = false
    var accessibilityID = "continue.kind"
    @Namespace private var segment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(kinds) { kind in
                let isSelected = selection == kind
                Button {
                    selection = kind
                } label: {
                    Group {
                        if showsTitles {
                            Label(kind.title, systemImage: kind.symbol)
                        } else {
                            Image(systemName: kind.symbol)
                        }
                    }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                        .padding(.horizontal, showsTitles ? Theme.Spacing.m : 0)
                        .frame(maxWidth: showsTitles ? .infinity : nil)
                        .frame(width: showsTitles ? nil : 36, height: showsTitles ? 38 : 30)
                        .background {
                            if isSelected {
                                Capsule().fill(.white).matchedGeometryEffect(id: "segment", in: segment)
                            }
                        }
                        .contentShape(Rectangle().inset(by: showsTitles ? 0 : -7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityLabel(kind.title)
                .accessibilityIdentifier("\(accessibilityID).\(showsTitles ? kind.title : kind.rawValue)")
            }
        }
        .padding(3)
        .glassEffect(.regular.interactive(), in: .capsule)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
        .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
            guard showsTitles, !kinds.isEmpty, width > 6, abs(value.translation.width) > abs(value.translation.height) else { return }
            let segmentWidth = (width - 6) / CGFloat(kinds.count)
            let index = min(kinds.count - 1, max(0, Int((value.location.x - 3) / segmentWidth)))
            if selection != kinds[index] { selection = kinds[index] }
        })
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
        .accessibilityIdentifier(accessibilityID)
    }
}
#endif
