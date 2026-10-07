import SwiftUI
import Features

@main
struct BlusionApp: App {
    @State private var environment = AppEnvironment.make()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}

/// Loads installed addons before showing the tabs, so the first screen never flashes an empty state.
struct RootView: View {
    let environment: AppEnvironment
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                RootTabView(services: environment.services)
            } else {
                ProgressView()
                    .accessibilityIdentifier("root.loading")
            }
        }
        .task {
            try? await environment.services.registry.load()
            isReady = true
        }
    }
}
