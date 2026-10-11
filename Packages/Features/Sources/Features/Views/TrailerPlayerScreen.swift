#if canImport(UIKit)
import AVKit
import Combine
import StremioKit
import SwiftUI
import UIKit

extension View {
    /// Plays `item` where it stands, and every page does it this way. A direct file (the iTunes preview, or an addon's own link) plays full
    /// screen in Blusion's player. A YouTube trailer is not played in the app: it opens in the YouTube app, or on its web page when the app is
    /// not installed, and the binding is cleared again.
    func trailerPlayer(item: Binding<Trailer?>) -> some View {
        modifier(TrailerPlayerModifier(item: item))
    }
}

private struct TrailerPlayerModifier: ViewModifier {
    @Binding var item: Trailer?

    func body(content: Content) -> some View {
        let direct = Binding<Trailer?>(get: { item?.directURL == nil ? nil : item }, set: { item = $0 })
        content
            .fullScreenCover(item: direct) { trailer in
                if let url = trailer.directURL { TrailerPlayerScreen(trailer: trailer, url: url) }
            }
            .onChange(of: item) { _, trailer in
                guard let trailer, let videoID = trailer.youtubeID else { return }
                item = nil
                openYouTube(videoID)
            }
    }

    /// The YouTube app first. The web link is a universal link too, so it opens the app when the app is installed; the page is the fallback.
    private func openYouTube(_ videoID: String) {
        guard let app = YouTubeLink.appURL(videoID: videoID), let web = YouTubeLink.webURL(videoID: videoID) else { return }
        UIApplication.shared.open(app, options: [:]) { opened in
            if !opened { UIApplication.shared.open(web, options: [:]) }
        }
    }
}

/// A direct trailer file, full screen, in AVKit's player. It starts at once. Its length goes to `TrailerDurations` once the file has loaded,
/// and a file that cannot be played shows a message. Audio uses the playback category, and the player pauses and releases the session when
/// the screen closes.
struct TrailerPlayerScreen: View {
    let trailer: Trailer
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var failed = false

    init(trailer: Trailer, url: URL) {
        self.trailer = trailer
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            if failed {
                Text("This trailer can't be played here.")
                    .font(Theme.Typography.button)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("trailer.unplayable")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
            }
            .glassCircleButton()
            .padding(Theme.Spacing.l)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("trailer.close")
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
        .onDisappear {
            player.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        .task { await watchItem() }
    }

    /// Waits for the file to be ready or to fail. Ready: its length is kept. Failed: the message shows. Cancelled when the screen closes.
    private func watchItem() async {
        guard let item = player.currentItem else { return }
        for await status in item.publisher(for: \.status).values {
            switch status {
            case .readyToPlay:
                if let duration = try? await item.asset.load(.duration) {
                    TrailerDurations.shared.record(duration.seconds, for: trailer.id)
                }
                return
            case .failed:
                failed = true
                return
            default:
                break
            }
        }
    }
}
#endif
