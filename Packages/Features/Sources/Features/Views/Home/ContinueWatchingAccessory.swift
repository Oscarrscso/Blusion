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
        update(from: await services.progress.all())
    }

    func update(from records: [WatchProgress]) {
        newest = LibraryViewModel.continueWatching(from: records).first
    }

    /// Takes the title off Continue Watching. The removal is queued for Trakt, which sync sends, so this never waits on the network.
    func remove(_ item: WatchProgress) async {
        await services.removeContinueWatching(identity: item.id)
        await refresh()
    }
}

/// Attaches the accessory with its `isEnabled` form, which needs iOS 26.1. On iOS 26.0 there is no accessory and Continue Watching stays
/// on Home.
struct ResumeAccessoryModifier: ViewModifier {
    let model: ContinueWatchingModel

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.safeAreaInset(edge: .bottom) {
            if let newest = model.newest {
                ContinueWatchingAccessory(item: newest, onRemove: { Task { await model.remove(newest) } })
                    .padding(.vertical, Theme.Spacing.s)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.s)
            }
        }
        #else
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: model.newest != nil) {
                if let newest = model.newest {
                    ContinueWatchingAccessory(item: newest, onRemove: { Task { await model.remove(newest) } })
                }
            }
        } else {
            content
        }
        #endif
    }
}

/// The tab bar accessory (iOS 26, like the mini player in Music): the newest title to resume, with its progress. Tapping it opens
/// that title's page on Home with its stream picker open, where the player resumes from the saved position.
struct ContinueWatchingAccessory: View {
    let item: WatchProgress
    let onRemove: () -> Void

    var body: some View {
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
        .continueWatchingHold(preview: MetaPreview(id: ContentID(item.contentID).baseID, type: item.type,
                                                  name: item.title, poster: item.poster), request: LibraryViewModel.request(for: item),
                                  onRemove: onRemove)
        .accessibilityLabel("Continue watching \(item.title), \(Int((item.fraction * 100).rounded())) percent watched")
        .accessibilityIdentifier("tabbar.continue")
    }
}
#endif
