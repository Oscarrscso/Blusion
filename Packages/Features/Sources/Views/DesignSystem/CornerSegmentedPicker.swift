#if canImport(UIKit)
import SwiftUI

/// Keep the native sliding selection; custom corner values clip its track to the filters group.
struct CornerSegmentedPicker<Selection: Hashable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    var symbols: [String] = []
    var showsTitles = true
    let label: (Selection) -> String
    @Environment(\.layoutMetrics) private var metrics

    init(_ title: String, options: [Selection], selection: Binding<Selection>, symbols: [String] = [],
         showsTitles: Bool = true, label: @escaping (Selection) -> String) {
        self.title = title
        self.options = options
        _selection = selection
        self.symbols = symbols
        self.showsTitles = showsTitles
        self.label = label
    }

    var body: some View {
        if metrics.cornerScale(for: .filters) == 1 {
            picker
        } else {
            picker.clipShape(ScaledCapsule(scale: metrics.cornerScale(for: .filters)))
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                segment(index).tag(options[index])
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .buttonCursor()
    }

    @ViewBuilder private func segment(_ index: Int) -> some View {
        if showsTitles, symbols.indices.contains(index) {
            Label(label(options[index]), systemImage: symbols[index])
        } else if !showsTitles, symbols.indices.contains(index) {
            Image(systemName: symbols[index])
                .accessibilityLabel(label(options[index]))
        } else {
            Text(label(options[index]))
        }
    }
}
#endif
