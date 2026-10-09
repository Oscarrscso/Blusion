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
        .defaultSize(Self.defaultWindowSize)
        .commands { BlusionCommands() }
    }

    /// 1280x800 where it fits. The Mac trims a new window that is too tall for the screen but not one that is too wide, and
    /// a Dock at the side takes some of the width: nine tenths of the screen leaves room for it.
    private static var defaultWindowSize: CGSize {
        #if targetEnvironment(macCatalyst)
        // No scene is connected this early, so there is no screen to reach through one: UIScreen.main is the only way to ask.
        let screen = UIScreen.main.bounds.size
        return CGSize(width: min(1280, screen.width * 0.9), height: min(800, screen.height * 0.9))
        #else
        return CGSize(width: 1280, height: 800)
        #endif
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
        #if targetEnvironment(macCatalyst)
        .modifier(MacWindowSize())
        #endif
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
            await DebugDemoData.installFakeOMDbIfRequested(environment.services)
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
            DebugStress.startIfRequested()
            DebugHangSampler.start()
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

#if targetEnvironment(macCatalyst)
/// A Mac window can be no larger than what it shows, and the first thing this app shows is a loading spinner: without room
/// to grow the window opens 16 points wide and ignores the default size. A snapshot run sets its own size (`DebugSnapshot`).
private struct MacWindowSize: ViewModifier {
    private let applies = ProcessInfo.processInfo.environment["BLUSION_WINDOW_SIZE"] == nil

    func body(content: Content) -> some View {
        if applies {
            content.frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        } else {
            content
        }
    }
}
#endif
