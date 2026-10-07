#if canImport(SwiftUI) && canImport(UIKit) && canImport(AVKit)
import AVKit
import PlayerKit
import SwiftUI
import UIKit

/// A view whose backing layer is an `AVPlayerLayer`.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else { preconditionFailure("layerClass is AVPlayerLayer") }
        return layer
    }

    private weak var embedded: UIView?

    /// Hosts the view a fallback engine renders into (nil removes it).
    func embed(_ surface: UIView?) {
        guard surface !== embedded else { return }
        embedded?.removeFromSuperview()
        embedded = surface
        guard let surface else { return }
        surface.frame = bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(surface)
    }
}

/// Picture in Picture for the AVPlayer engine. It starts only from `toggle()`, which only the PiP button calls (ADR-005: App Review rejects
/// programmatic starts).
@MainActor
@Observable
final class PiPProxy {
    private(set) var isPossible = false
    private(set) var isActive = false
    private var controller: AVPictureInPictureController?
    private var observations: [NSKeyValueObservation] = []

    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported(), controller == nil,
              let controller = AVPictureInPictureController(playerLayer: layer) else { return }
        self.controller = controller
        observations.append(controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = possible }
        })
        observations.append(controller.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] controller, _ in
            let active = controller.isPictureInPictureActive
            Task { @MainActor in self?.isActive = active }
        })
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() } else { controller.startPictureInPicture() }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let engine: (any PlaybackEngine)?
    let pip: PiPProxy

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if let avEngine = engine as? AVEngine {
            view.embed(nil)
            if view.playerLayer.player !== avEngine.player {
                view.playerLayer.player = avEngine.player
                pip.attach(to: view.playerLayer)
            }
        } else if let provider = engine as? any VideoSurfaceProviding, let surface = provider.videoSurface as? UIView {
            view.playerLayer.player = nil
            view.embed(surface)
        } else {
            view.playerLayer.player = nil
            view.embed(nil)
        }
    }
}

/// The system AirPlay route picker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
