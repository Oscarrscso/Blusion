import Foundation
import Observation
import Persistence
import PlayerKit
import StremioKit

extension PlayerViewModel {
    // MARK: Audio

    var audioTracks: [MediaTrack] { state.audioTracks }

    var selectedAudioTrackID: String? { state.selectedAudioTrackID }

    var audioDelay: TimeInterval { coordinator?.audioDelay ?? 0 }

    func selectAudioTrack(id: String) {
        pendingResume?.audioTrack = nil
        userChoseAudio = true
        audioTrackSelectionID = id
        coordinator?.selectAudioTrack(id: id)
        showControls()
    }

    func adjustAudioDelay(by delta: TimeInterval) {
        let limit = Self.maximumAudioDelay
        coordinator?.setAudioDelay(min(limit, max(-limit, ((audioDelay + delta) * 20).rounded() / 20)))
        showControls()
    }

    func resetAudioDelay() {
        coordinator?.setAudioDelay(0)
    }

    /// An audio file the user opened (a commentary, another dub), played in sync. Needs an engine with `.externalAudio`.
    func loadAudioFile(at url: URL) async {
        guard capabilities.contains(.externalAudio), let copy = copyIn(url) else { return }
        userChoseAudio = true
        coordinator?.addExternalAudio(url: copy, title: url.deletingPathExtension().lastPathComponent)
        showControls()
    }

    // MARK: Picture

    var videoLayout: VideoLayout { coordinator?.videoLayout ?? pictureLayout }

    var processing: VideoProcessing { coordinator?.processing ?? settings.player.processing }

    // MARK: Zoom Mode and Aspect Ratio

    /// Video › Zoom Mode (see `VideoZoomMode`).
    typealias ZoomMode = VideoZoomMode

    /// Video › Aspect Ratio (see `AspectRatioChoice`).
    typealias AspectRatioChoice = StremioKit.AspectRatioChoice

    /// The picture Zoom Mode and Aspect Ratio make on this screen.
    var pictureLayout: VideoLayout {
        VideoLayout(zoomMode: zoomMode, aspectRatio: aspectRatio, safeInset: safeAreaInset)
    }

    /// Kept for every video, as in Infuse.
    func setZoomMode(_ mode: ZoomMode) {
        changeZoomMode(to: mode)
        showControls()
    }

    private func changeZoomMode(to mode: ZoomMode) {
        let mode = mode.onThisDevice
        zoomMode = mode
        applyPicture()
        savePreferences { $0.zoomMode = mode }
    }

    /// The zoom button: the next Zoom Mode, round to the first (Normal, Aspect Fit, Crop, Fill, Stretch; a Mac has no Aspect Fit).
    func cycleZoomMode() {
        setZoomMode(zoomMode.next)
    }

    /// A pinch selects Fill outward and restores Normal inward.
    func pinchZoom(in zoomsIn: Bool) {
        let mode: ZoomMode = zoomsIn ? .fill : .normal
        guard mode != zoomMode else { return }
        // A pinch leaves the controls as they were, so the picture stays clear.
        changeZoomMode(to: mode)
        lastInteraction = now()
    }

    /// The centred source crop for Crop, Fill and Stretch, kept for the film or every episode of its season.
    func setAspectRatio(_ choice: AspectRatioChoice) {
        defer { showControls() }
        let promotesToCrop = choice != .original && (zoomMode == .normal || zoomMode == .aspectFit)
        guard choice != aspectRatio || promotesToCrop else { return }
        aspectRatio = choice
        if promotesToCrop { zoomMode = .crop }
        applyPicture()
        let key = AspectRatioChoice.titleKey(for: plan.request)
        let savedZoom = zoomMode
        savePreferences {
            $0.aspectRatios[key] = choice == .original ? nil : choice
            if promotesToCrop { $0.zoomMode = savedZoom }
        }
    }

    /// The safe area the player screen reports. Only Normal uses it.
    func setSafeAreaInset(_ inset: Double) {
        let inset = max(0, inset.rounded())
        guard inset != safeAreaInset else { return }
        safeAreaInset = inset
        if zoomMode == .normal { applyPicture() }
    }

    /// Hands the renderer the picture for the current Zoom Mode, Aspect Ratio and safe area.
    func applyPicture() {
        let layout = pictureLayout
        guard coordinator?.videoLayout != layout else { return }
        coordinator?.setVideoLayout(layout)
    }

    /// Kept for next time, like the rest of the picture processing.
    func setDolbyVision(_ enabled: Bool) {
        var processing = processing
        processing.dolbyVision = enabled
        setProcessing(processing)
    }

    func toggleAmbientMode() {
        savePreferences { $0.ambientMode.toggle() }
        showControls()
    }

    /// `save` false applies it to the picture only, for a slider mid-drag; the release saves it.
    func setProcessing(_ processing: VideoProcessing, save: Bool = true) {
        coordinator?.setProcessing(processing)
        if save { savePreferences { $0.processing = processing } }
        showControls()
    }
}
