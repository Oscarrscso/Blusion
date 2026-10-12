#if canImport(UIKit)
import SwiftUI
import UIKit

/// The trailer's place on the title page, under the actions and above the synopsis: the player in a 16:9 panel while a trailer
/// plays (AVKit's for a direct file, YouTube's embedded player for a YouTube video), or one line saying it could not be played
/// with a button that tries again. Nothing is shown in the other phases.
struct DetailTrailerPanel: View {
    let model: DetailViewModel
    /// The panel's width; its height follows at 16:9.
    let width: CGFloat
    /// The id the page scrolls to when the panel appears.
    static let scrollID = "detail.trailerPanel"

    var body: some View {
        content
            .id(Self.scrollID)
    }

    @ViewBuilder
    private var content: some View {
        switch model.trailer.phase {
        case .playing:
            if let playback = model.trailer.playback as? AVTrailerPlayback {
                TrailerPlayerView(player: playback.player, loader: model.trailer)
                    .frame(width: width, height: width * 9 / 16)
                    .mediaArtwork()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("detail.trailerPlayer")
            } else if let playback = model.trailer.playback as? YouTubeTrailerPlayback {
                YouTubeTrailerView(playback: playback)
                    .frame(width: width, height: width * 9 / 16)
                    .mediaArtwork()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("detail.trailerPlayer")
            }
        case .failed(let message):
            InlineErrorView(message) { model.toggleTrailer() }
                .accessibilityIdentifier("detail.trailerError")
        case .idle, .loading:
            EmptyView()
        }
    }
}
#endif
