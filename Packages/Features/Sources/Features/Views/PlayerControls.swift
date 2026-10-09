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
            LinearGradient(colors: [.black.opacity(0.2), .clear, .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
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
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .pointerInteraction(cornerRadius: 22)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Esc)")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("player.close")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline).lineLimit(2).accessibilityAddTraits(.isHeader).accessibilityIdentifier("player.title")
                if let season = model.plan.request.season, let episode = model.plan.request.episode {
                    Text("S\(season), E\(episode)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if pipAvailable {
                        Button(action: pipToggle) {
                            Image(systemName: "pip.enter").frame(width: 44, height: 44)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .pointerInteraction(cornerRadius: 22)
                        }
                        .help("Picture in Picture")
                        .accessibilityLabel("Picture in Picture")
                        .accessibilityIdentifier("player.pip")
                    }
                    #if canImport(AVKit)
                    AirPlayButton().frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .pointerInteraction(cornerRadius: 22)
                        .help("AirPlay")
                        .accessibilityLabel("AirPlay").accessibilityIdentifier("player.airplay")
                    #endif
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var transport: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 24) {
                Button { Task { await model.skip(by: -10) } } label: {
                    Image(systemName: "gobackward.10").font(.title).frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .pointerInteraction(cornerRadius: 28)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("Back 10 seconds (←)")
                .accessibilityLabel("Back 10 seconds")
                .accessibilityIdentifier("player.skipBack")
                Button { model.togglePlayPause() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32)).contentTransition(.symbolEffect(.replace))
                        .frame(width: 76, height: 76).glassEffect(.regular.interactive(), in: .circle)
                        .pointerInteraction(cornerRadius: 38)
                }
                .keyboardShortcut(" ", modifiers: [])
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("player.playPause")
                Button { Task { await model.skip(by: 10) } } label: {
                    Image(systemName: "goforward.10").font(.title).frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .pointerInteraction(cornerRadius: 28)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("Forward 10 seconds (→)")
                .accessibilityLabel("Forward 10 seconds")
                .accessibilityIdentifier("player.skipForward")
            }
            .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                subtitlesMenu
                if model.audioTracks.count > 1 { audioMenu }
                speedMenu
                if model.hasNextStream {
                    Button { Task { await model.nextStream() } } label: {
                        Label("Next stream", systemImage: "forward.end").frame(minWidth: 44, minHeight: 44)
                            .pointerInteraction(cornerRadius: 12)
                    }
                        .help("Next stream")
                        .accessibilityIdentifier("player.nextStream")
                }
                if model.hasNextEpisode && model.hasFinished {
                    Button(action: onNextEpisode) {
                        Label("Next episode", systemImage: "forward.end.alt").frame(minWidth: 44, minHeight: 44)
                            .pointerInteraction(cornerRadius: 12)
                    }
                        .help("Next episode")
                        .accessibilityIdentifier("player.nextEpisode")
                }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
        }
        .tint(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
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
                .pointerInteraction(cornerRadius: 12)
        }
        .help("Subtitles")
        .accessibilityLabel("Subtitles")
        .accessibilityIdentifier("player.subtitlesMenu")
    }

    private var audioMenu: some View {
        Menu {
            ForEach(model.audioTracks) { track in
                Button { model.selectAudioTrack(id: track.id) } label: { checkmarked(track.title, model.selectedAudioTrackID == track.id) }
            }
        } label: {
            Image(systemName: "speaker.wave.2").frame(minWidth: 44, minHeight: 44)
                .pointerInteraction(cornerRadius: 12)
        }
            .help("Audio")
            .accessibilityLabel("Audio")
            .accessibilityIdentifier("player.audioMenu")
    }

    private var speedMenu: some View {
        Menu {
            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                Button { model.setRate(rate) } label: { checkmarked(rate == 1 ? "Normal" : "\(rate)×", model.state.rate == rate) }
            }
        } label: {
            Group {
                if model.state.rate == 1 {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                } else {
                    Text("\(model.state.rate.formatted())×").font(.subheadline.weight(.semibold))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .pointerInteraction(cornerRadius: 12)
        }
            .help("Playback speed")
            .accessibilityLabel("Speed")
            .accessibilityIdentifier("player.speedMenu")
    }

    @ViewBuilder
    private func checkmarked(_ title: String, _ selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}
#endif
