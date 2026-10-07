import SwiftUI

@main
struct BlusionApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Blusion",
            systemImage: "play.rectangle",
            description: Text("A player that works with Stremio addons.")
        )
        .accessibilityIdentifier("root.placeholder")
    }
}
