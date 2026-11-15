#if canImport(UIKit)
import AetherEngine
import AVFoundation
import Combine
import Foundation
import PlaybackGeometry
import UIKit

extension AetherSession {
    // MARK: Statistics

    public func statistics() -> AetherStatistics {
        var stats = AetherStatistics(engine: "AetherEngine (\(Self.routeName(engine.videoRoute)))")
        stats.decoder = engine.activeVideoDecoder
        stats.videoCodec = engine.sourceVideoCodecName
        if engine.sourceVideoWidth > 0 {
            stats.width = Int(engine.sourceVideoWidth)
            stats.height = Int(engine.sourceVideoHeight)
        }
        stats.frameRate = engine.sourceVideoFrameRate
        stats.videoBitrate = engine.sourceVideoBitrate > 0 ? Double(engine.sourceVideoBitrate) : nil
        stats.networkBitrate = networkBitrate
        stats.bufferedAhead = bufferedMediaAhead
        let stream = engine.sourceVideoStreamFormat
        let colourDetails = [stream?.transferLabel, stream?.colorPrimariesLabel, stream?.bitDepth.map { "\($0)-bit" }].compactMap { $0 }
        let source = Self.formatName(engine.sourceVideoFormat)
        stats.sourceColour = colourDetails.isEmpty ? source : "\(source) (\(colourDetails.joined(separator: ", ")))"
        stats.outputColour = Self.formatName(engine.videoFormat)
        if let profile = engine.sourceDVProfile {
            var text = "Profile \(profile)"
            if profile == 7 {
                if engine.dolbyVisionConversion == .profile7ToProfile81 {
                    text += ", converted to 8.1 (enhancement layer dropped)"
                } else if engine.videoRoute == .software, options.composesFEL {
                    text += ", both layers composed on the GPU (FEL) with per-frame 8.1 metadata"
                } else {
                    text += ", base layer"
                }
            }
            stats.dolbyVision = text
        }
        if let audio = engine.audioTracks.first(where: { $0.id == engine.activeAudioTrackIndex }) {
            stats.audioCodec = Self.audioName(audio)
            stats.audioChannels = audio.channels > 0 ? Self.channelLayout(audio.channels) + (audio.sampleRate > 0 ? ", \(Double(audio.sampleRate) / 1000) kHz" : "") : nil
            stats.audioBitrate = audio.bitrate > 0 ? Double(audio.bitrate) : nil
        }
        stats.audioOutput = [Self.deliveryName(engine.audioDelivery), engine.activeAudioDecoder].compactMap { $0 }.joined(separator: " · ")
        if let container = engine.sourceContainerFormat { stats.notes.append("Container: \(container).") }
        if engine.airPlayPictureStaysLocal { stats.notes.append("AirPlay plays this title's sound only; the picture stays on this device.") }
        return stats
    }

    public func shutdown() {
        #if DEBUG
        trace.end()
        #endif
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        subscriptions.removeAll()
        engine.stop()
        engine.unbind(view: host.playerView)
        continuation.finish()
    }

    // MARK: Observation

    func observe() {
        engine.$startupProgress.compactMap { $0 }.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] progress in
            MainActor.assumeIsolated {
                guard let self, !self.isLoaded else { return }
                let stage: AetherPreparationStage = switch progress.stage {
                case .connecting: .openingConnection
                case .openingContainer, .analyzingStreams, .preparingDisplay, .selectingRoute, .buildingSession, .preparingPlayback: .loadingMedia
                case .awaitingFirstFrame, .presenting: .startingPlayback
                }
                self.continuation.yield(.preparing(stage))
            }
        }.store(in: &subscriptions)
        // Reuse the engine's 1 Hz telemetry. On loopback, AVPlayer's throughput measures localhost; source-byte deltas measure
        // the actual download instead. Never turn a missing counter or a counter reset into a speed.
        engine.diagnostics.$liveTelemetry.receive(on: RunLoop.main).sink { [weak self] telemetry in
            MainActor.assumeIsolated {
                guard let self, self.isLoaded else { return }
                var bitrate: Double?
                if let telemetry {
                    let now = ContinuousClock.now
                    let bytes = telemetry.demuxerBytesFetched
                    if self.engine.videoRoute == .loopback {
                        if bytes > 0, let previous = self.downloadSample, bytes >= previous.bytes {
                            let elapsed = previous.at.duration(to: now).components
                            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                            if seconds > 0 { bitrate = Double(bytes - previous.bytes) * 8 / seconds }
                        }
                        self.downloadSample = bytes > 0 ? (bytes, now) : nil
                    } else {
                        bitrate = telemetry.networkThroughputMbps.map { $0 * 1_000_000 }
                    }
                } else {
                    self.downloadSample = nil
                }
                self.networkBitrate = bitrate
                self.continuation.yield(.networkBitrate(bitrate))
            }
        }.store(in: &subscriptions)
        engine.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.publishTransport() }
        }.store(in: &subscriptions)
        engine.$playbackPhase.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.publishTransport() }
        }.store(in: &subscriptions)
        engine.clock.$currentTime.receive(on: RunLoop.main).sink { [weak self] time in
            MainActor.assumeIsolated { self?.publishPosition(time) }
        }.store(in: &subscriptions)
        // AetherEngine's player often publishes the length a moment after the load has finished. Reported only at load, the
        // timeline had no length for the whole film: no time left, no scrubbing and no swipe to seek.
        engine.$duration.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] duration in
            MainActor.assumeIsolated { self?.publishDuration(duration) }
        }.store(in: &subscriptions)
        engine.clock.$bufferedPosition.receive(on: RunLoop.main).sink { [weak self] until in
            MainActor.assumeIsolated {
                guard let self, self.isLoaded else { return }
                let until = self.bufferedAhead.map { self.engine.clock.currentTime + $0 } ?? until
                guard abs(until - self.lastBuffered) >= 0.5 else { return }
                self.lastBuffered = until
                self.continuation.yield(.buffered(until))
            }
        }.store(in: &subscriptions)
        engine.$residentRanges.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isLoaded, self.engine.videoRoute == .software,
                      let ahead = self.bufferedAhead else { return }
                let until = self.engine.clock.currentTime + ahead
                guard abs(until - self.lastBuffered) >= 0.5 else { return }
                self.lastBuffered = until
                self.continuation.yield(.buffered(until))
            }
        }.store(in: &subscriptions)
        for publisher in [engine.$audioTracks.map { _ in () }.eraseToAnyPublisher(),
                          engine.$subtitleTracks.map { _ in () }.eraseToAnyPublisher(),
                          engine.$activeAudioTrackIndex.map { _ in () }.eraseToAnyPublisher(),
                          engine.$activeSubtitleTrackIndex.map { _ in () }.eraseToAnyPublisher(),
                          engine.$isSubtitleActive.map { _ in () }.eraseToAnyPublisher(),
                          engine.$isLoadingSubtitles.map { _ in () }.eraseToAnyPublisher()] {
            publisher.receive(on: RunLoop.main).sink { [weak self] in
                MainActor.assumeIsolated { self?.publishTracks() }
            }.store(in: &subscriptions)
        }
        engine.$mediaChapters.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.publishChapters() }
        }.store(in: &subscriptions)
        engine.$subtitleCues.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSubtitles() }
        }.store(in: &subscriptions)
        engine.clock.$sourceTime.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSubtitles() }
        }.store(in: &subscriptions)
        // This publisher is backed by the native or sample-buffer layer's actual
        // display readiness. Transport .playing can precede it by several seconds.
        engine.$hasFirstFrameReadyForDisplay.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] ready in
            MainActor.assumeIsolated {
                guard let self, self.isLoaded, ready else { return }
                self.host.displaySize = self.presentedSize()
                self.continuation.yield(.videoFrameReady)
            }
        }.store(in: &subscriptions)
        engine.$softwareDisplaySize.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isLoaded else { return }
                self.host.displaySize = self.presentedSize()
            }
        }.store(in: &subscriptions)
    }

    func publishTransport() {
        guard isLoaded else {
            if case .error = engine.state { continuation.yield(.failed(failure(thrown: nil))) }
            return
        }
        switch engine.state {
        case .error:
            continuation.yield(.failed(failure(thrown: nil)))
            return
        case .ended:
            if !hasEnded {
                hasEnded = true
                continuation.yield(.ended)
            }
            return
        case .playing:
            setPausedState(false)
        case .paused:
            setPausedState(true)
        case .idle, .loading, .seeking:
            break
        }
        let buffering = switch engine.playbackPhase {
        case .rebuffering, .stalled: true
        default: false
        }
        if buffering != bufferingState {
            bufferingState = buffering
            #if DEBUG
            trace.note("buffering=\(buffering) phase=\(engine.playbackPhase)")
            #endif
            continuation.yield(.buffering(buffering))
        }
    }

    private func setPausedState(_ paused: Bool) {
        guard pausedState != paused else { return }
        pausedState = paused
        continuation.yield(.paused(paused))
    }

    private func publishDuration(_ duration: Double) {
        guard isLoaded, duration.isFinite, duration > 0, duration != lastDuration else { return }
        lastDuration = duration
        continuation.yield(.duration(duration))
    }

    private func publishPosition(_ time: Double) {
        guard isLoaded, time.isFinite, abs(time - lastPosition) >= 0.2 else { return }
        lastPosition = time
        continuation.yield(.position(max(0, time)))
    }

    func currentTracks() -> (audio: [AetherTrack], subtitles: [AetherTrack], audioID: Int?, subtitleID: Int?) {
        var audioID = engine.activeAudioTrackIndex
        if let pending = pendingAudio {
            if pending == audioID || errorStateReached { pendingAudio = nil } else { audioID = pending }
        }
        var subtitleID = engine.isSubtitleActive ? engine.activeSubtitleTrackIndex : nil
        if let pending = pendingSubtitle {
            // Settled once AetherEngine reports the pick, or has stopped loading without taking it.
            if pending.trackID == subtitleID || (!engine.isLoadingSubtitles && pending == .off) { pendingSubtitle = nil } else { subtitleID = pending.trackID }
        }
        return (engine.audioTracks.map(Self.track), engine.subtitleTracks.map(Self.track), audioID, subtitleID)
    }

    private var errorStateReached: Bool {
        if case .error = engine.state { return true }
        return false
    }

    func publishTracks() {
        guard isLoaded else { return }
        let next = currentTracks()
        if let last = lastTracks, last.audio == next.audio, last.subtitles == next.subtitles, last.audioID == next.audioID,
           last.subtitleID == next.subtitleID { return }
        lastTracks = next
        continuation.yield(.tracks(audio: next.audio, subtitles: next.subtitles, selectedAudio: next.audioID, selectedSubtitle: next.subtitleID))
    }

    func publishChapters() {
        guard isLoaded else { return }
        let chapters = engine.mediaChapters.enumerated().map { index, chapter in
            AetherChapter(title: chapter.name.isEmpty ? "Chapter \(index + 1)" : chapter.name, start: max(0, chapter.startSeconds))
        }
        guard chapters != lastChapters else { return }
        lastChapters = chapters
        continuation.yield(.chapters(chapters))
    }

    func refreshSubtitles() {
        host.overlay.show(cues: engine.subtitleCues, at: engine.clock.sourceTime - subtitleDelay)
    }
}
#endif
