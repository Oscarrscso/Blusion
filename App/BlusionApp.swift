import SwiftUI
import Features
import StremioKit
import UIKit

@main
struct BlusionApp: App {
    @State private var environment = AppEnvironment.make()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { BlusionCommands() }
    }
}

/// Loads installed addons before showing the tabs, so the first screen never flashes an empty state.
struct RootView: View {
    let environment: AppEnvironment
    @State private var isReady = false
    @State private var addonLink: String?
    @State private var userStateRevision = 0

    var body: some View {
        Group {
            if isReady {
                RootTabView(services: environment.services, route: environment.launchRoute,
                            addonLink: $addonLink, userStateRevision: userStateRevision)
            } else {
                ProgressView()
                    .accessibilityIdentifier("root.loading")
            }
        }
        .task {
            try? await environment.services.registry.load()
            let settings = await environment.services.settings.load()
            environment.services.posterRatings.isEnabled = settings.showsPosterRatings
            await environment.services.posterRatings.setReviewServices(
                omdb: settings.omdbAPIKey.map { OMDbRatings(client: environment.services.client, apiKey: $0) },
                tmdb: settings.tmdbReadToken.map { TMDbRatings(client: environment.services.client, readAccessToken: $0) })
            await environment.seedDefaultAddons()
            #if DEBUG
            await DebugDemoData.installExtraAddons(environment.services)
            await DebugDemoData.seedIfRequested(environment.services)
            #endif
            isReady = true
            #if targetEnvironment(macCatalyst)
            if ProcessInfo.processInfo.environment["BLUSION_WINDOW_SIZE"] == nil {
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    scene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 600)
                }
            }
            #endif
            #if DEBUG
            DebugSnapshot.scheduleIfRequested()
            await DebugHandoffProbe.startIfRequested(environment.services)
            #endif
        }
        // The player app calls back here with where the viewer stopped (blusion://x-callback-url/handoff/...).
        .onOpenURL { url in
            if let link = AddonLink.installText(from: url) {
                addonLink = link
                return
            }
            Task {
                if await PlaybackHandoffCenter(services: environment.services).handle(url) { userStateRevision += 1 }
                #if DEBUG
                await DebugHandoffProbe.record(url, services: environment.services)
                #endif
            }
        }
    }
}
