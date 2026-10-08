#if canImport(UIKit)
import PlayerKit
import StremioKit
import SwiftUI

struct PlayerControls: View {
    let model: PlayerViewModel
    let onClose: () -> Void
    let onNextEpisode: () -> Void
    let pipToggle: () -> Void
    let pipAvailable: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack {
                topBar
                Spacer()
                transport
                Spacer()
                bottomBar
            }
            .padding()
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.controls")
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: onClose) { Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("player.close")
            Text(model.title).font(.headline).lineLimit(2).accessibilityAddTraits(.isHeader).accessibilityIdentifier("player.title")
            Spacer()
        }
    }

    private var transport: some View {
        HStack(spacing: 44) {
            Button { Task { await model.skip(by: -10) } } label: { Image(systemName: "gobackward.10").font(.largeTitle).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Back 10 seconds")
                .accessibilityIdentifier("player.skipBack")
            Button { model.togglePlayPause() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44)).frame(minWidth: 60, minHeight: 60) }
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("player.playPause")
            Button { Task { await model.skip(by: 10) } } label: { Image(systemName: "goforward.10").font(.largeTitle).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Forward 10 seconds")
                .accessibilityIdentifier("player.skipForward")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(model.positionText)
                    .font(.footnote.monospacedDigit())
                    .accessibilityIdentifier("player.time")
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(model.positionText)
                Slider(value: Binding(get: { model.fraction }, set: { model.updateScrub(fraction: $0) }), in: 0...1) { editing in
                    if editing { model.beginScrub() } else { Task { await model.endScrub() } }
                }
                .accessibilityLabel("Position")
                .accessibilityValue("\(model.positionText) of \(model.duration.map(PlayerTime.format) ?? "unknown")")
                .accessibilityIdentifier("player.scrubber")
                Text(model.remainingText).font(.footnote.monospacedDigit()).accessibilityLabel("Remaining time")
            }
            HStack(spacing: 20) {
                subtitlesMenu
                if model.audioTracks.count > 1 { audioMenu }
                speedMenu
                if model.hasNextStream {
                    Button { Task { await model.nextStream() } } label: { Label("Next stream", systemImage: "forward.end") }
                        .accessibilityIdentifier("player.nextStream")
                }
                if model.hasNextEpisode && model.hasFinished {
                    Button(action: onNextEpisode) { Label("Next episode", systemImage: "forward.end.alt") }
                        .accessibilityIdentifier("player.nextEpisode")
                }
                Spacer()
                if pipAvailable {
                    Button(action: pipToggle) { Image(systemName: "pip.enter").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Picture in Picture")
                        .accessibilityIdentifier("player.pip")
                }
                #if canImport(UIKit) && canImport(AVKit)
                AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay").accessibilityIdentifier("player.airplay")
                #endif
            }
            .labelStyle(.iconOnly)
            .font(.title3)
        }
    }

    private var subtitlesMenu: some View {
        Menu {
            Button { Task { await model.selectSubtitle(.off) } } label: { checkmarked("Off", model.subtitleChoice == .off) }
            ForEach(model.embeddedSubtitleTracks) { track in
                Button { Task { await model.selectSubtitle(.embedded(track.id)) } } label: { checkmarked(track.title, model.subtitleChoice == .embedded(track.id)) }
            }
            ForEach(model.subtitleOptions) { option in
                Button { Task { await model.selectSubtitle(.external(option.id)) } } label: { checkmarked(option.title, model.subtitleChoice == .external(option.id)) }
            }
            if case .external = model.subtitleChoice {
                Divider()
                Button("Delay +0.5 s") { model.adjustSubtitleOffset(by: 0.5) }
                Button("Earlier −0.5 s") { model.adjustSubtitleOffset(by: -0.5) }
                if model.subtitleOffset != 0 { Button("Reset timing (\(String(format: "%+.1f", model.subtitleOffset)) s)") { model.resetSubtitleOffset() } }
            }
            if let status = model.subtitleStatus { Text(status) }
        } label: {
            Image(systemName: model.subtitleChoice == .off ? "captions.bubble" : "captions.bubble.fill").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Subtitles")
        .accessibilityIdentifier("player.subtitlesMenu")
    }

    private var audioMenu: some View {
        Menu {
            ForEach(model.audioTracks) { track in
                Button { model.selectAudioTrack(id: track.id) } label: { checkmarked(track.title, model.selectedAudioTrackID == track.id) }
            }
        } label: { Image(systemName: "speaker.wave.2").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Audio")
            .accessibilityIdentifier("player.audioMenu")
    }

    private var speedMenu: some View {
        Menu {
            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                Button { model.setRate(rate) } label: { checkmarked(rate == 1 ? "Normal" : "\(rate)×", model.state.rate == rate) }
            }
        } label: { Image(systemName: "gauge.with.dots.needle.67percent").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Speed")
            .accessibilityIdentifier("player.speedMenu")
    }

    @ViewBuilder
    private func checkmarked(_ title: String, _ selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}
#endif
