#if targetEnvironment(macCatalyst)
@preconcurrency import AVFoundation
import Foundation
import Libavcodec
import Libavformat
import Libavutil

/// Keep E-AC-3, including JOC, compressed until Apple's native player receives it.
@MainActor
final class NativeDolbyAudio {
    private let player: AVPlayer
    private let loader: EAC3AssetLoader
    private var observation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private(set) var isReady = false
    private var wantsPaused = true

    init(url: URL, headers: [String: String], streamIndex: Int?, audioOrdinal: Int, position: Double,
         onReady: @escaping @MainActor () -> Void,
         onFailure: @escaping @MainActor () -> Void,
         onWaiting: @escaping @MainActor (Bool) -> Void,
         onPosition: @escaping @MainActor (Double) -> Void) {
        loader = EAC3AssetLoader(url: url, headers: headers, streamIndex: streamIndex, audioOrdinal: audioOrdinal, position: position)
        let asset = AVURLAsset(url: URL(string: "blusion-dolby://host/stream.eac3")!)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        let item = AVPlayerItem(asset: asset)
        item.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, let item = self.player.currentItem else { return }
                if item.status == .readyToPlay, !self.isReady {
                    self.isReady = true
                    onReady()
                } else if item.status == .failed {
                    onFailure()
                }
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in
                if waiting { onWaiting(true) }
                else if playing { onWaiting(false) }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let self, self.isReady, seconds.isFinite else { return }
                let position = self.loader.startPosition + seconds
                self.loader.advance(to: position)
                onPosition(position)
            }
        }
    }

    func setPaused(_ paused: Bool) {
        guard isReady, paused != wantsPaused else { return }
        wantsPaused = paused
        if paused { player.pause() } else { player.playImmediately(atRate: 1) }
    }

    func setVolume(_ volume: Float) { player.volume = volume }
    func setMuted(_ muted: Bool) { player.isMuted = muted }

    func stop() {
        observation = nil
        playbackObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        loader.stop()
    }
}

/// A sequential elementary stream. It demuxes packets; it never opens an audio decoder.
private final class EAC3AssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "Blusion.native-dolby")
    private let url: URL
    private let headers: [String: String]
    private let preferredStreamIndex: Int?
    private let audioOrdinal: Int
    private var streamIndex = 0
    private let requestedPosition: Double
    private let condition = NSCondition()
    private var stopped = false
    private var playbackPosition: Double
    private var firstPosition: Double
    private var hasFirstPacket = false
    // FFmpeg and the byte cache are accessed only on queue.
    private var format: UnsafeMutablePointer<AVFormatContext>?
    private var packet: UnsafeMutablePointer<AVPacket>?
    private var bytes = Data()
    private var byteOffset: Int64 = 0
    private var lastPacketPosition: Double

    init(url: URL, headers: [String: String], streamIndex: Int?, audioOrdinal: Int, position: Double) {
        self.url = url
        self.headers = headers
        preferredStreamIndex = streamIndex
        self.audioOrdinal = audioOrdinal
        requestedPosition = max(0, position)
        playbackPosition = max(0, position)
        firstPosition = max(0, position)
        lastPacketPosition = max(0, position)
    }

    var startPosition: Double {
        condition.lock()
        defer { condition.unlock() }
        return firstPosition
    }

    private var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopped
    }

    func advance(to position: Double) {
        condition.lock()
        playbackPosition = position
        condition.broadcast()
        condition.unlock()
    }

    func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
        queue.async { [self] in
            av_packet_free(&packet)
            avformat_close_input(&format)
            bytes.removeAll()
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        do {
            if let info = request.contentInformationRequest {
                info.contentType = "public.enhanced-ac3-audio"
                info.contentLength = Int64(Int32.max)
                info.isByteRangeAccessSupported = false
            }
            guard let data = request.dataRequest else {
                request.finishLoading()
                return true
            }
            try openIfNeeded()
            let end = data.requestedOffset + Int64(data.requestedLength)
            while !isStopped && !request.isCancelled && (data.requestsAllDataToEndOfResource || data.currentOffset < end) {
                let offset = data.currentOffset
                guard offset >= byteOffset else { throw URLError(.cannotDecodeContentData) }
                while offset >= byteOffset + Int64(bytes.count) {
                    guard try appendPacket() else {
                        request.finishLoading()
                        return true
                    }
                }
                let start = Int(offset - byteOffset)
                let available = bytes.count - start
                let count = data.requestsAllDataToEndOfResource ? available : min(available, Int(end - offset))
                data.respond(with: bytes.subdata(in: start..<(start + count)))
                // Keep a small rewind window for AVPlayer's initial format probe.
                if bytes.count > 262_144 {
                    let discard = min(Int(data.currentOffset - byteOffset), bytes.count - 131_072)
                    bytes = Data(bytes.dropFirst(discard))
                    byteOffset += Int64(discard)
                }
            }
            if !request.isCancelled { request.finishLoading() }
        } catch {
            if !request.isCancelled { request.finishLoading(with: error) }
        }
        return true
    }

    private func openIfNeeded() throws {
        guard format == nil else { return }
        format = avformat_alloc_context()
        guard let format else { throw URLError(.cannotOpenFile) }
        format.pointee.interrupt_callback = AVIOInterruptCB(callback: { pointer in
            guard let pointer else { return 1 }
            return Unmanaged<EAC3AssetLoader>.fromOpaque(pointer).takeUnretainedValue().isStopped ? 1 : 0
        }, opaque: Unmanaged.passUnretained(self).toOpaque())
        var options: OpaquePointer?
        let fields = headers.map { "\($0.key): \($0.value)\r\n" }.joined()
        av_dict_set(&options, "headers", fields, 0)
        av_dict_set(&options, "rw_timeout", "15000000", 0)
        defer { av_dict_free(&options) }
        let source = url.isFileURL ? url.path : url.absoluteString
        guard avformat_open_input(&self.format, source, nil, &options) >= 0,
              let context = self.format,
              avformat_find_stream_info(context, nil) >= 0 else {
            throw URLError(.cannotDecodeContentData)
        }
        if let preferredStreamIndex {
            streamIndex = preferredStreamIndex
        } else {
            // mpv's native Matroska demuxer has no FFmpeg index; both preserve audio-track order.
            let audioStreams = (0..<Int(context.pointee.nb_streams)).filter {
                context.pointee.streams[$0]?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_AUDIO
            }
            guard audioStreams.indices.contains(audioOrdinal) else { throw URLError(.cannotDecodeContentData) }
            streamIndex = audioStreams[audioOrdinal]
        }
        guard streamIndex >= 0, streamIndex < Int(context.pointee.nb_streams),
              let stream = context.pointee.streams[streamIndex],
              stream.pointee.codecpar.pointee.codec_id == AV_CODEC_ID_EAC3 else {
            throw URLError(.cannotDecodeContentData)
        }
        for index in 0..<Int(context.pointee.nb_streams) where index != streamIndex {
            context.pointee.streams[index]?.pointee.discard = AVDISCARD_ALL
        }
        let origin = context.pointee.start_time == Int64.min ? 0 : context.pointee.start_time
        if requestedPosition > 0 {
            let timestamp = Int64(requestedPosition * 1_000_000) + origin
            guard avformat_seek_file(context, -1, Int64.min, timestamp, timestamp, AVSEEK_FLAG_BACKWARD) >= 0 else {
                throw URLError(.cannotDecodeContentData)
            }
        }
        packet = av_packet_alloc()
        guard packet != nil else { throw URLError(.cannotDecodeContentData) }
    }

    private func appendPacket() throws -> Bool {
        guard let format, let packet, let stream = format.pointee.streams[streamIndex] else {
            throw URLError(.cannotDecodeContentData)
        }
        condition.lock()
        while !stopped && lastPacketPosition > playbackPosition + 30 {
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.1))
        }
        let cancelled = stopped
        condition.unlock()
        guard !cancelled else { throw URLError(.cancelled) }
        while !isStopped {
            av_packet_unref(packet)
            let result = av_read_frame(format, packet)
            if result == -541_478_725 { return false } // AVERROR_EOF is a C macro Swift cannot import.
            guard result >= 0 else { throw URLError(.networkConnectionLost) }
            guard packet.pointee.stream_index == Int32(streamIndex) else { continue }
            let timestamp = packet.pointee.pts != Int64.min ? packet.pointee.pts : packet.pointee.dts
            if timestamp != Int64.min {
                let timebase = stream.pointee.time_base
                let origin = format.pointee.start_time == Int64.min ? 0 : Double(format.pointee.start_time) / 1_000_000
                lastPacketPosition = Double(timestamp) * Double(timebase.num) / Double(timebase.den) - origin
                if lastPacketPosition + 0.001 < requestedPosition { continue }
            }
            guard let data = packet.pointee.data, packet.pointee.size > 0 else { continue }
            condition.lock()
            if !hasFirstPacket {
                hasFirstPacket = true
                firstPosition = lastPacketPosition
            }
            condition.unlock()
            bytes.append(data, count: Int(packet.pointee.size))
            return true
        }
        throw URLError(.cancelled)
    }
}
#endif
