#if canImport(Libmpv) && canImport(UIKit)
import AVFoundation
import Foundation
import Libmpv
import PlayerKit
import QuartzCore
import UIKit

// UNVERIFIED (ADR-006): written against libmpv's C API and MPVKit's iOS usage from memory, on a host without Xcode.
// It is the only file in the project that touches the third-party player. If something here does not compile or render,
// fix this file only: the engine, the state mapping and the tests live behind `FallbackBackend` in PlayerKit.

/// mpv sets the drawable size itself; ignore the degenerate sizes UIKit layout produces.
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set { if newValue.width > 1, newValue.height > 1 { super.drawableSize = newValue } }
    }
}

final class MPVHostView: UIView {
    let metalLayer = MPVMetalLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(metalLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
        let scale = max(traitCollection.displayScale, 1)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

/// Polls mpv's event queue on its own thread and turns events into `FallbackEvent`s.
private final class MPVEventPump: @unchecked Sendable {
    private let handle: OpaquePointer
    private let continuation: AsyncStream<FallbackEvent>.Continuation
    private let lock = NSLock()
    private var running = true
    private let exited = DispatchSemaphore(value: 0)

    init(handle: OpaquePointer, continuation: AsyncStream<FallbackEvent>.Continuation) {
        self.handle = handle
        self.continuation = continuation
    }

    func start() {
        Thread.detachNewThread { [self] in
            run()
            exited.signal()
        }
    }

    /// Stops the loop and waits for it to leave mpv, so the handle can be destroyed safely.
    func stopAndWait() {
        lock.withLock { running = false }
        mpv_wakeup(handle)
        _ = exited.wait(timeout: .now() + 2)
    }

    private var isRunning: Bool { lock.withLock { running } }

    private func run() {
        var lastPosition = -1.0
        while isRunning {
            guard let event = mpv_wait_event(handle, 0.25)?.pointee else { continue }
            switch event.event_id {
            case MPV_EVENT_SHUTDOWN:
                return
            case MPV_EVENT_FILE_LOADED:
                continuation.yield(loadedEvent())
            case MPV_EVENT_END_FILE:
                guard let data = event.data else { continue }
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.reason == MPV_END_FILE_REASON_EOF {
                    continuation.yield(.ended)
                } else if end.reason == MPV_END_FILE_REASON_ERROR {
                    continuation.yield(.failed(Self.failure(code: end.error)))
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.data else { continue }
                let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                guard let value = property.data else { continue }
                switch (String(cString: property.name), property.format) {
                case ("time-pos", MPV_FORMAT_DOUBLE):
                    let position = value.assumingMemoryBound(to: Double.self).pointee
                    if abs(position - lastPosition) >= 0.2 {
                        lastPosition = position
                        continuation.yield(.position(position))
                    }
                case ("duration", MPV_FORMAT_DOUBLE):
                    break   // sent with `.loaded`; durations of live streams can change later and are ignored
                case ("demuxer-cache-time", MPV_FORMAT_DOUBLE):
                    continuation.yield(.buffered(value.assumingMemoryBound(to: Double.self).pointee))
                case ("pause", MPV_FORMAT_FLAG):
                    continuation.yield(.paused(value.assumingMemoryBound(to: Int32.self).pointee != 0))
                case ("paused-for-cache", MPV_FORMAT_FLAG):
                    continuation.yield(.buffering(value.assumingMemoryBound(to: Int32.self).pointee != 0))
                default:
                    break
                }
            default:
                break
            }
        }
    }

    private static func failure(code: Int32) -> PlaybackFailure {
        let text = String(cString: mpv_error_string(code))
        switch code {
        case MPV_ERROR_UNKNOWN_FORMAT.rawValue, MPV_ERROR_UNSUPPORTED.rawValue: return PlaybackFailure(.format, text)
        case MPV_ERROR_LOADING_FAILED.rawValue: return PlaybackFailure(.network, text)
        default: return PlaybackFailure(.other, text)
        }
    }

    private func loadedEvent() -> FallbackEvent {
        let duration = double("duration")
        var audio: [MediaTrack] = []
        var subtitles: [MediaTrack] = []
        var selectedAudio: String?
        var selectedSubtitle: String?
        for index in 0..<(int("track-list/count") ?? 0) {
            guard let kind = string("track-list/\(index)/type"), let id = int("track-list/\(index)/id") else { continue }
            let language = string("track-list/\(index)/lang")
            let title = string("track-list/\(index)/title") ?? language.map { LanguageCodes.displayName($0) } ?? "Track \(id)"
            let isDefault = flag("track-list/\(index)/default")
            let selected = flag("track-list/\(index)/selected")
            switch kind {
            case "audio":
                audio.append(MediaTrack(id: "a\(id)", title: title, language: language, isDefault: isDefault))
                if selected { selectedAudio = "a\(id)" }
            case "sub":
                subtitles.append(MediaTrack(id: "s\(id)", title: title, language: language, isDefault: isDefault))
                if selected { selectedSubtitle = "s\(id)" }
            default:
                break
            }
        }
        return .loaded(duration: duration, audio: audio, subtitles: subtitles, selectedAudio: selectedAudio, selectedSubtitle: selectedSubtitle)
    }

    private func string(_ name: String) -> String? {
        guard let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    private func int(_ name: String) -> Int? {
        var value: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 ? Int(value) : nil
    }

    private func double(_ name: String) -> Double? {
        var value = 0.0
        return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    private func flag(_ name: String) -> Bool {
        var value: Int32 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 && value != 0
    }
}

/// `FallbackBackend` on libmpv (MPVKit, LGPL build). Renders through a CAMetalLayer (MoltenVK) with VideoToolbox hardware decoding.
@MainActor
public final class MPVBackend: FallbackBackend {
    private let host = MPVHostView()
    private var handle: OpaquePointer?
    private var pump: MPVEventPump?
    private let events: AsyncStream<FallbackEvent>
    private let continuation: AsyncStream<FallbackEvent>.Continuation

    public var videoSurface: AnyObject { host }

    public init() {
        let (events, continuation) = AsyncStream<FallbackEvent>.makeStream()
        self.events = events
        self.continuation = continuation
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        setUp()
    }

    public func makeEventStream() -> AsyncStream<FallbackEvent> { events }

    private func setUp() {
        guard let handle = mpv_create() else {
            continuation.yield(.failed(PlaybackFailure(.noEngine, "The fallback player could not start.")))
            return
        }
        self.handle = handle
        for (name, value) in [("vo", "gpu-next"), ("gpu-api", "vulkan"), ("gpu-context", "moltenvk"), ("hwdec", "videotoolbox"),
                              ("pause", "yes"), ("keep-open", "no"), ("sub-auto", "no"), ("network-timeout", "20")] {
            mpv_set_option_string(handle, name, value)
        }
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(host.metalLayer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
        guard mpv_initialize(handle) >= 0 else {
            continuation.yield(.failed(PlaybackFailure(.noEngine, "The fallback player could not initialise.")))
            return
        }
        for (name, format) in [("time-pos", MPV_FORMAT_DOUBLE), ("duration", MPV_FORMAT_DOUBLE), ("demuxer-cache-time", MPV_FORMAT_DOUBLE),
                               ("pause", MPV_FORMAT_FLAG), ("paused-for-cache", MPV_FORMAT_FLAG)] {
            mpv_observe_property(handle, 0, name, format)
        }
        let pump = MPVEventPump(handle: handle, continuation: continuation)
        self.pump = pump
        pump.start()
    }

    // MARK: FallbackBackend

    public func load(url: URL, headers: [String: String], startPosition: TimeInterval) {
        guard let handle else { return }
        mpv_set_property_string(handle, "pause", "yes")
        mpv_set_property_string(handle, "start", startPosition > 0 ? String(startPosition) : "0")
        // List options accept `%length%value` entries so commas inside header values survive.
        let fields = headers.map { name, value -> String in
            let entry = "\(name): \(value)"
            return "%\(entry.utf8.count)%\(entry)"
        }.joined(separator: ",")
        mpv_set_property_string(handle, "http-header-fields", fields)
        command(["loadfile", url.absoluteString, "replace"])
    }

    public func setPaused(_ paused: Bool) {
        guard let handle else { return }
        mpv_set_property_string(handle, "pause", paused ? "yes" : "no")
    }

    public func seek(to position: TimeInterval) async {
        command(["seek", String(position), "absolute+exact"])
    }

    public func setRate(_ rate: Float) {
        guard let handle else { return }
        mpv_set_property_string(handle, "speed", String(rate))
    }

    public func selectAudio(id: String?) {
        guard let handle else { return }
        mpv_set_property_string(handle, "aid", id.flatMap { Int($0.dropFirst()) }.map(String.init) ?? "no")
    }

    public func selectSubtitle(id: String?) {
        guard let handle else { return }
        mpv_set_property_string(handle, "sid", id.flatMap { Int($0.dropFirst()) }.map(String.init) ?? "no")
    }

    public func shutdown() {
        pump?.stopAndWait()
        pump = nil
        if let handle {
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
        continuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func command(_ arguments: [String]) {
        guard let handle else { return }
        var cStrings: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = cStrings.map { $0.map { UnsafePointer($0) } }
        pointers.append(nil)
        mpv_command(handle, &pointers)
    }
}
#endif
