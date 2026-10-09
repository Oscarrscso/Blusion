#if canImport(UIKit)
import SwiftUI

/// The shared glass pill for media types and quality filters, with a sliding white selection.
struct QualitySelector: View {
    let titles: [String]
    @Binding var selection: Int
    var symbols: [String] = []
    var showsTitles = true
    var accessibilityID = "streams.filter"
    @Namespace private var segment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - 6 - CGFloat(max(0, titles.count - 1)) * 2) / CGFloat(max(1, titles.count)))
            HStack(spacing: 2) {
                ForEach(titles.indices, id: \.self) { index in
                    Button {
                        if selection != index { selection = index }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            if symbols.indices.contains(index) { Image(systemName: symbols[index]) }
                            if showsTitles { Text(titles[index]) }
                        }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(selection == index ? Color.black : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, showsTitles ? Theme.Spacing.s : 0)
                            .frame(width: width, height: showsTitles ? 38 : 30)
                            .background {
                                if selection == index {
                                    Capsule().fill(.white).matchedGeometryEffect(id: "segment", in: segment)
                                }
                            }
                            .contentShape(Rectangle().inset(by: showsTitles ? 0 : -7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
                    .accessibilityLabel(titles[index])
                    .accessibilityIdentifier("\(accessibilityID).\(showsTitles ? titles[index] : titles[index].lowercased())")
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: .capsule)
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                guard showsTitles, !titles.isEmpty, abs(value.translation.width) > abs(value.translation.height) else { return }
                let index = min(titles.count - 1, max(0, Int((value.location.x - 3) / (width + 2))))
                if selection != index { selection = index }
            })
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selection)
            .sensoryFeedback(.selection, trigger: selection)
        }
        .frame(width: showsTitles ? nil : CGFloat(titles.count * 38 + 4), height: showsTitles ? 44 : 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
        .accessibilityIdentifier(accessibilityID)
    }
}
#endif
