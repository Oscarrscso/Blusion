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
                RootTabView(services: environment.services, route: environment.launchRoute)
            } else {
                ProgressView()
                    .accessibilityIdentifier("root.loading")
            }
        }
        .task {
            try? await environment.services.registry.load()
            await environment.seedDefaultAddons()
            #if DEBUG
            await DebugDemoData.installExtraAddons(environment.services)
            await DebugDemoData.seedIfRequested(environment.services)
            #endif
            isReady = true
            #if DEBUG
            DebugSnapshot.scheduleIfRequested()
            await DebugHandoffProbe.startIfRequested(environment.services)
            #endif
        }
        // The player app calls back here with where the viewer stopped (blusion://x-callback-url/handoff/...).
        .onOpenURL { url in
            Task {
                await PlaybackHandoffCenter(services: environment.services).handle(url)
                #if DEBUG
                await DebugHandoffProbe.record(url, services: environment.services)
                #endif
            }
        }
    }
}
