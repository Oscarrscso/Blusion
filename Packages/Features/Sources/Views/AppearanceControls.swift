#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The controls every part of Appearance builds its choices from. Pickers and switches save at once and tick (Pickers & switches);
/// sliders show their value as they move and save, with the Sliders tick, when they are let go.
@MainActor
struct AppearanceControls {
    let appearance: Binding<AppearancePreferences>
    let draft: Binding<AppearancePreferences?>
    let isSliding: Binding<Bool>

    /// The look shown: a slider's value while it is dragged, otherwise what is saved.
    var current: AppearancePreferences { draft.wrappedValue ?? appearance.wrappedValue }

    /// The look being set, drawn on the app's own `samples`, as a row of the page.
    func preview(_ samples: [AppearanceSample], lightsOnePiece: Bool = false, contentPadding: CGFloat = 0) -> some View {
        AppearancePreview(appearance: current, samples: samples, lightsOnePiece: lightsOnePiece, contentPadding: contentPadding)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    func choice<Value: Equatable>(_ keyPath: WritableKeyPath<AppearancePreferences, Value>) -> Binding<Value> {
        let appearance = appearance
        return Binding(get: { appearance.wrappedValue[keyPath: keyPath] }, set: { value in
            guard value != appearance.wrappedValue[keyPath: keyPath] else { return }
            Haptics.play(.choices)
            appearance.wrappedValue[keyPath: keyPath] = value
        })
    }

    func colour(_ keyPath: WritableKeyPath<AppearancePreferences, AppearancePreferences.RGB>) -> Binding<Color> {
        let appearance = appearance
        return Binding(get: { appearance.wrappedValue[keyPath: keyPath].colour }, set: { colour in
            appearance.wrappedValue[keyPath: keyPath] = AppearancePreferences.RGB(colour)
        })
    }

    func toggle(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Bool>, id: String) -> some View {
        Toggle(title, isOn: choice(keyPath))
            .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A menu of every case.
    func menu<Option: AppearanceOption>(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Option>,
                                        id: String) -> some View {
        Picker(title, selection: choice(keyPath)) {
            ForEach(Option.allCases) { option in Text(option.label).tag(option) }
        }
        .settingsHover()
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A titled segmented control over every case.
    func segmented<Option: AppearanceOption>(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Option>,
                                             id: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
            CornerSegmentedPicker(title, options: Array(Option.allCases), selection: choice(keyPath)) {
                $0.label
            }
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A titled segmented control over numbers.
    func numbers(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Int>, in values: ClosedRange<Int>,
                 id: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
            CornerSegmentedPicker(title, options: Array(values), selection: choice(keyPath)) {
                String($0)
            }
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    /// A titled slider with its value as a percentage beside the title and a small and a large symbol at its ends. A drag shows in the
    /// preview as it goes and is saved when it ends; VoiceOver's and the keyboard's steps, which come without a drag, are saved at once.
    func slider(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Double>, in range: ClosedRange<Double>,
                step: Double, low: String, high: String, id: String) -> some View {
        slider(title, read: { $0[keyPath: keyPath] }, write: { $0[keyPath: keyPath] = $1 },
               in: range, step: step, low: low, high: high, id: id)
    }

    func columnSlider(_ title: String, _ keyPath: WritableKeyPath<AppearancePreferences, Int>, id: String) -> some View {
        let appearance = appearance
        let value = Binding<Double>(get: { Double(appearance.wrappedValue[keyPath: keyPath]) }, set: { newValue in
            let columns = Int(newValue.rounded())
            guard columns != appearance.wrappedValue[keyPath: keyPath] else { return }
            Haptics.play(.sliders)
            appearance.wrappedValue[keyPath: keyPath] = columns
        })
        let range = AppearancePreferences.phoneGridColumnRange
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(title)
                Spacer()
                Text("\(current[keyPath: keyPath])").monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            CornerSlider(value: value, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .accessibilityLabel(title)
                .accessibilityValue("\(current[keyPath: keyPath])")
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    func slider(_ title: String, read: @escaping (AppearancePreferences) -> Double,
                write: @escaping (inout AppearancePreferences, Double) -> Void, in range: ClosedRange<Double>,
                step: Double, low: String, high: String, id: String) -> some View {
        let appearance = appearance
        let draft = draft
        let isSliding = isSliding
        let value = Binding<Double>(get: { read(draft.wrappedValue ?? appearance.wrappedValue) }, set: { newValue in
            if isSliding.wrappedValue {
                var look = draft.wrappedValue ?? appearance.wrappedValue
                write(&look, newValue)
                draft.wrappedValue = look
            } else if newValue != read(appearance.wrappedValue) {
                Haptics.play(.sliders)
                var look = appearance.wrappedValue
                write(&look, newValue)
                appearance.wrappedValue = look
            }
        })
        let shown = percent(read(current))
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(title)
                Spacer()
                Text(shown)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            HStack {
                Image(systemName: low).imageScale(.small).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                CornerSlider(value: value, in: range, step: step) { editing in
                    isSliding.wrappedValue = editing
                    guard !editing, let look = draft.wrappedValue else { return }
                    draft.wrappedValue = nil
                    if look != appearance.wrappedValue {
                        Haptics.play(.sliders)
                        appearance.wrappedValue = look
                    }
                }
                .accessibilityLabel(title)
                .accessibilityValue(shown)
                Image(systemName: high).imageScale(.large).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("settings.appearance.\(id)")
    }

    func textMenu<Option: AppearanceOption>(_ title: String, _ role: AppearancePreferences.TextRole,
                                            _ value: WritableKeyPath<AppearancePreferences.TextStyle, Option>,
                                            follow: WritableKeyPath<AppearancePreferences.TextStyle, Bool>? = nil,
                                            id: String) -> some View {
        Picker(title, selection: textChoice(role, value, follow: follow)) {
            if role != .reading, follow != nil {
                Text("Same as body text").tag(Optional<Option>.none)
            }
            ForEach(Option.allCases) { option in Text(option.label).tag(Optional(option)) }
        }
        .settingsHover()
        .accessibilityIdentifier(textID(role, id))
    }

    func textSlant(_ role: AppearancePreferences.TextRole) -> some View {
        Picker("Italic", selection: textChoice(role, \.italic, follow: \.followsItalic)) {
            Text("Same as body text").tag(Optional<Bool>.none)
            Text("Off").tag(Optional(false))
            Text("On").tag(Optional(true))
        }
        .settingsHover()
        .accessibilityIdentifier(textID(role, "italic"))
    }

    func textToggle(_ title: String, _ role: AppearancePreferences.TextRole,
                    _ value: WritableKeyPath<AppearancePreferences.TextStyle, Bool>, id: String) -> some View {
        let choice = textChoice(role, value, follow: nil)
        return Toggle(title, isOn: Binding(get: { choice.wrappedValue ?? false }, set: { choice.wrappedValue = $0 }))
            .accessibilityIdentifier(textID(role, id))
    }

    private func textID(_ role: AppearancePreferences.TextRole, _ id: String) -> String {
        "settings.appearance.text.\(role.rawValue).\(id)"
    }

    /// A nil selection links this one attribute back to body text.
    private func textChoice<Value: Equatable>(_ role: AppearancePreferences.TextRole,
                                              _ value: WritableKeyPath<AppearancePreferences.TextStyle, Value>,
                                              follow: WritableKeyPath<AppearancePreferences.TextStyle, Bool>?) -> Binding<Value?> {
        let appearance = appearance
        return Binding(get: {
            let stored = appearance.wrappedValue.storedText(for: role)
            if role != .reading, let follow, stored[keyPath: follow] { return nil }
            return stored[keyPath: value]
        }, set: { newValue in
            var look = appearance.wrappedValue
            var stored = look.storedText(for: role)
            if let newValue {
                stored[keyPath: value] = newValue
            } else {
                let defaults: AppearancePreferences.TextStyle = role == .display ? .headings() : .followingReading()
                stored[keyPath: value] = defaults[keyPath: value]
            }
            if role != .reading, let follow { stored[keyPath: follow] = newValue == nil }
            guard stored != look.storedText(for: role) else { return }
            Haptics.play(.choices)
            look.setStoredText(stored, for: role)
            appearance.wrappedValue = look
        })
    }
}
#endif
