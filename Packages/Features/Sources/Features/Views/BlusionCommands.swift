#if canImport(UIKit)
import SwiftUI

public struct BlusionCommands: Commands {
    @FocusedValue(AppRouter.self) private var router: AppRouter?

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { router?.showSettings() }.keyboardShortcut(",")
        }
        CommandMenu("Navigate") {
            Button("Home") { router?.open(.home) }.keyboardShortcut("1")
            Button("Discover") { router?.open(.discover) }.keyboardShortcut("2")
            Button("Library") { router?.open(.library) }.keyboardShortcut("3")
            Button("Search") { router?.open(.search) }.keyboardShortcut("f")
        }
    }
}
#endif
