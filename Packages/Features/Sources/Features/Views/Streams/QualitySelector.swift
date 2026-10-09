#if canImport(UIKit)
import SwiftUI

/// One connected glass control. Dragging changes the filter as the thumb crosses a segment.
struct QualitySelector: View {
    let titles: [String]
    @Binding var selection: Int
    var accessibilityID = "streams.filter"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - 8) / CGFloat(max(1, titles.count)))
            HStack(spacing: 0) {
                ForEach(titles.indices, id: \.self) { index in
                    Button {
                        if selection != index { selection = index }
                    } label: {
                        Text(titles[index])
                            .font(.subheadline.weight(selection == index ? .bold : .medium))
                            .foregroundStyle(selection == index ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: width, height: 36)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
                    .accessibilityIdentifier("\(accessibilityID).\(titles[index])")
                }
            }
            .background(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.42), lineWidth: 0.8) }
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                    .frame(width: width, height: 36)
                    .offset(x: CGFloat(selection) * width)
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.7) }
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                guard !titles.isEmpty, abs(value.translation.width) > abs(value.translation.height) else { return }
                let index = min(titles.count - 1, max(0, Int((value.location.x - 4) / width)))
                if selection != index { selection = index }
            })
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: selection)
            .sensoryFeedback(.selection, trigger: selection)
        }
        .frame(height: 44)
        .accessibilityIdentifier(accessibilityID)
    }
}
#endif
