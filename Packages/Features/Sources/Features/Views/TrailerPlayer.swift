#if canImport(UIKit)
import AVKit
import StremioKit
import SwiftUI
import UIKit

extension View {
    /// Opens a YouTube trailer that the page handed over, and clears the binding again. The page hands over only a video that YouTube
    /// will not embed, so it opens in the YouTube app, or on its web page when the app is not installed. Any other trailer only clears
    /// the binding.
    func youTubeTrailer(_ item: Binding<Trailer?>) -> some View {
        modifier(YouTubeTrailerModifier(item: item))
    }
}

private struct YouTubeTrailerModifier: ViewModifier {
    @Binding var item: Trailer?

    func body(content: Content) -> some View {
        content.onChange(of: item) { _, trailer in
            guard let trailer else { return }
            item = nil
            guard let videoID = trailer.youtubeID else { return }
            openYouTube(videoID)
        }
    }

    /// The YouTube app first. The web link is a universal link too, so it opens the app when the app is installed; the page is the
    /// fallback.
    private func openYouTube(_ videoID: String) {
        guard let app = YouTubeLink.appURL(videoID: videoID), let web = YouTubeLink.webURL(videoID: videoID) else { return }
        UIApplication.shared.open(app, options: [:]) { opened in
            if !opened { UIApplication.shared.open(web, options: [:]) }
        }
    }
}

/// A trailer that is ready to play in AVKit's player, shown in the page's panel. Playing sets the audio session to playback;
/// stopping pauses the player, releases its item and lets the session go. A trailer that was prepared but never played leaves the
/// session alone, so stopping it cannot silence something else the app has started since.
@MainActor
final class AVTrailerPlayback: TrailerPlayback {
    let player: AVPlayer
    let duration: TimeInterval?
    let aspectRatio: Double?
    /// Never called: AVKit shows its own state once a trailer has started, including when it fails or ends.
    var onFinish: (@MainActor (TrailerPlaybackError?) -> Void)?
    private var hasActivatedSession = false

    init(player: AVPlayer, duration: TimeInterval?, aspectRatio: Double?) {
        self.player = player
        self.duration = duration
        self.aspectRatio = aspectRatio
    }

    func play() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        hasActivatedSession = true
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        guard hasActivatedSession else { return }
        hasActivatedSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Makes AVKit's player for a trailer's link and waits until it has buffered enough to start.
///
/// The remote link goes to AVPlayer as it is. AVPlayer streams it itself (the segments of an HLS stream, or byte ranges of a progressive
/// file), so nothing is downloaded whole and the app caches nothing.
struct AVTrailerPreparer: TrailerPreparing {
    /// How long the item may take to learn whether it can play at all.
    static let readyTimeout: Duration = .seconds(20)
    /// How long to wait for the first buffer. After it the player waits by itself, so the page is not held longer than this.
    static let bufferTimeout: Duration = .seconds(6)

    /// YouTube videos are not AVKit's: they play in YouTube's embedded player, see `YouTubeTrailerPreparer`.
    @MainActor
    func prepareYouTube(_ videoID: String) async throws -> any TrailerPlayback {
        try await YouTubeTrailerPreparer.prepare(videoID)
    }

    @MainActor
    func prepare(_ url: URL) async throws -> any TrailerPlayback {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        do {
            try await Self.waitUntilReady(item)
            try await Self.waitForBuffer(item)
        } catch {
            player.replaceCurrentItem(with: nil)
            throw error
        }
        let assetDuration = try? await item.asset.load(.duration)
        let seconds = assetDuration?.seconds
        let size = item.presentationSize
        let shape = size.width > 0 && size.height > 0 ? Double(size.width / size.height) : nil
        return AVTrailerPlayback(player: player, duration: seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }, aspectRatio: shape)
    }

    /// Polls until the item is ready or has failed. A poll keeps this simple and cancellable.
    @MainActor
    private static func waitUntilReady(_ item: AVPlayerItem) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        while item.status == .unknown {
            if started.duration(to: clock.now) > readyTimeout { throw TrailerPlaybackError.timedOut }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard item.status == .readyToPlay else { throw TrailerPlaybackError.unplayable }
    }

    /// Polls until the first buffer is in, or the timeout passes. An item that fails meanwhile is unplayable.
    @MainActor
    private static func waitForBuffer(_ item: AVPlayerItem) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        while !item.isPlaybackLikelyToKeepUp && !item.isPlaybackBufferFull {
            if item.status == .failed { throw TrailerPlaybackError.unplayable }
            if started.duration(to: clock.now) > bufferTimeout { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// AVKit's own player controller, with its controls and full-screen button. A trailer that is full screen covers the page without leaving
/// it, so the loader is told when that starts and ends, and the player resumes if it was playing.
struct TrailerPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let loader: TrailerLoader

    func makeCoordinator() -> Coordinator {
        Coordinator(loader: loader)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player = nil
        // A view that goes away while full screen never hears that full screen ended. The page must still close the player when it is left.
        coordinator.viewWasDismantled()
    }

    /// AVKit calls its delegate on the main thread, so each method hops onto the main actor to reach the loader.
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private let loader: TrailerLoader

        init(loader: TrailerLoader) {
            self.loader = loader
        }

        @MainActor
        func viewWasDismantled() {
            loader.isFullScreen = false
        }

        nonisolated func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            let loader = self.loader
            MainActor.assumeIsolated { loader.isFullScreen = true }
        }

        nonisolated func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            let loader = self.loader
            MainActor.assumeIsolated {
                // AVKit pauses the player when full screen closes, so it is started again once the transition has finished.
                let wasPlaying = playerViewController.player?.timeControlStatus != .paused
                coordinator.animate(alongsideTransition: nil) { context in
                    MainActor.assumeIsolated {
                        guard !context.isCancelled else { return }
                        loader.isFullScreen = false
                        if wasPlaying { loader.playback?.play() }
                    }
                }
            }
        }
    }
}
#endif
