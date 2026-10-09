#if canImport(UIKit)
import PlayerKit
import StremioKit
import SwiftUI

/// What the tab bar accessory shows: the newest title to resume. The accessory is enabled only while there is one.
@MainActor
@Observable
final class ContinueWatchingModel {
    private(set) var newest: WatchProgress?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    /// Reads the saved progress again. The root tab view calls this on launch and whenever the tab changes.
    func refresh() async {
        newest = LibraryViewModel.continueWatching(from: await services.progress.all()).first
    }
}

/// Attaches the accessory with its `isEnabled` form, which needs iOS 26.1. On iOS 26.0 there is no accessory and Continue Watching stays
/// on Home.
struct ResumeAccessoryModifier: ViewModifier {
    let model: ContinueWatchingModel

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
        #else
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: model.newest != nil) {
                if let newest = model.newest {
                    ContinueWatchingAccessory(item: newest)
                }
            }
        } else {
            content
        }
        #endif
    }
}

/// The tab bar accessory (iOS 26, like the mini player in Music): the newest title to resume, with its progress. Tapping it opens
/// Home at that title's streams, where the player resumes from the saved position.
struct ContinueWatchingAccessory: View {
    let item: WatchProgress
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.open(.home)
            router.homePath.append(LibraryViewModel.request(for: item))
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                ArtworkImage(url: item.poster, title: item.title, maxPixelSize: 120)
                    .frame(width: 30, height: 45)
                    .mediaArtwork(cornerRadius: 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    ProgressView(value: item.fraction)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue watching \(item.title), \(Int((item.fraction * 100).rounded())) percent watched")
        .accessibilityIdentifier("tabbar.continue")
    }
}
#endif
