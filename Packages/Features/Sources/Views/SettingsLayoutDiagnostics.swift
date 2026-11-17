#if canImport(UIKit)
import SwiftUI

extension View {
    func settingsRowBounds() -> some View {
        #if DEBUG
        anchorPreference(key: SettingsRowBoundsKey.self, value: .bounds) { [$0] }
        #else
        self
        #endif
    }

    func settingsLayoutDiagnostics() -> some View {
        #if DEBUG
        overlayPreferenceValue(SettingsRowBoundsKey.self) { anchors in
            GeometryReader { geometry in
                let frames = anchors.map { geometry[$0] }
                Color.clear
                    .allowsHitTesting(false)
                    .onChange(of: frames, initial: true) {
                        for (index, frame) in frames.enumerated() {
                            if frame.minX < -1 || frame.maxX > geometry.size.width + 1 {
                                print("Settings layout: row \(index) exceeds column bounds: \(frame)")
                            }
                            for other in frames.dropFirst(index + 1) {
                                let overlap = frame.intersection(other)
                                if overlap.width > 1, overlap.height > 1 {
                                    print("Settings layout: overlapping rows: \(frame), \(other)")
                                }
                            }
                        }
                    }
            }
        }
        #else
        self
        #endif
    }
}

#if DEBUG
private struct SettingsRowBoundsKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}
#endif
#endif
