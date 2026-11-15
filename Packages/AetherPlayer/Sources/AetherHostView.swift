#if canImport(UIKit)
import AetherEngine
import AVFoundation
import Combine
import Foundation
import PlaybackGeometry
import UIKit

/// The engine's player view, placed for the aspect override, crop, fit and zoom, with the subtitle overlay on the part that shows.
final class AetherHostView: UIView {
    let playerView = AetherPlayerView()
    let overlay = AetherSubtitleOverlay()
    /// Clips the picture to its visible part, so a crop hides the bars.
    private let clipView = UIView()
    /// Over the picture and the same size: carries a layer drawn over it (`hostPictureOverlay`).
    private let pictureOverlayView = UIView()
    private weak var pictureOverlay: CALayer?
    var fit = AetherFit.fit { didSet { if fit != oldValue { setNeedsLayout() } } }
    var zoom = 1.0 { didSet { if zoom != oldValue { setNeedsLayout() } } }
    /// How bright HDR gets, 0…1. 0 leaves each picture layer as the engine set it.
    var hdrBrightness = 0.0 { didSet { if hdrBrightness != oldValue { applyDynamicRange() } } }
    /// What the engine set on a picture layer before the override, so 0 can put it back.
    private let engineDynamicRange = NSMapTable<CALayer, NSString>.weakToStrongObjects()
    /// Width over height replacing the file's; nil keeps it.
    var aspect: Double? { didSet { if aspect != oldValue { setNeedsLayout() } } }
    /// Width over height to crop the picture to, centred; nil keeps it whole.
    var crop: Double? { didSet { if crop != oldValue { setNeedsLayout() } } }
    /// Points Fit keeps clear on the left and the right.
    var inset = 0.0 { didSet { if inset != oldValue { setNeedsLayout() } } }
    /// The next layout is a change of the zoom, not of the size: it eases the picture into place.
    private var animatesNextLayout = false
    private var laidOutSize = CGSize.zero
    /// How long a zoom change takes to ease into place.
    static let zoomAnimationDuration: TimeInterval = 0.3
    /// The picture's presented size, when the engine says it.
    var displaySize: CGSize? { didSet { if displaySize != oldValue { setNeedsLayout() } } }
    /// Tells the engine how to draw into the player view: stretched into the frame laid out here, or by fit before the size is known.
    var onGravity: (@MainActor (AVLayerVideoGravity) -> Void)?
    private var lastGravity: AVLayerVideoGravity?
    var currentGravity: AVLayerVideoGravity { lastGravity ?? .resizeAspect }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isAccessibilityElement = false
        clipView.clipsToBounds = true
        clipView.isUserInteractionEnabled = false
        clipView.addSubview(playerView)
        pictureOverlayView.isUserInteractionEnabled = false
        pictureOverlayView.backgroundColor = .clear
        clipView.addSubview(pictureOverlayView)
        addSubview(clipView)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Eases the next layout into place: a Zoom Mode or Aspect Ratio change, once the picture's size is known and it is on screen.
    func animateNextLayout() {
        guard displaySize != nil, window != nil else { return }
        animatesNextLayout = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sizeChanged = bounds.size != laidOutSize
        laidOutSize = bounds.size
        let animates = animatesNextLayout && !sizeChanged
        animatesNextLayout = false
        guard animates else {
            // A new size never animates: the engine's layer would otherwise slide the picture up or down for a moment, as it animates
            // its gravity and bounds by default.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            placePicture()
            CATransaction.commit()
            return
        }
        // A zoom change eases the frames to their new place; the gravity stays .resize, so the picture scales with its frame.
        UIView.animate(withDuration: Self.zoomAnimationDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Self.zoomAnimationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            self.placePicture()
            CATransaction.commit()
        }
    }

    /// Sets the dynamic range on the engine's picture layers (AVPlayerLayer on the native route, AVSampleBufferDisplayLayer on the software
    /// one). The engine can make a new layer when a file loads, so this also runs on every layout. Core Animation has no level between its
    /// ranges, so any brightness above 0 asks for `high`, the display's whole HDR range.
    private func applyDynamicRange() {
        var pending = [playerView.layer]
        while let layer = pending.popLast() {
            pending.append(contentsOf: layer.sublayers ?? [])
            guard layer is AVPlayerLayer || layer is AVSampleBufferDisplayLayer else { continue }
            if hdrBrightness > 0 {
                if engineDynamicRange.object(forKey: layer) == nil {
                    engineDynamicRange.setObject(layer.preferredDynamicRange.rawValue as NSString, forKey: layer)
                }
                if layer.preferredDynamicRange != .high { layer.preferredDynamicRange = .high }
            } else if let original = engineDynamicRange.object(forKey: layer) {
                layer.preferredDynamicRange = CALayer.DynamicRange(rawValue: original as String)
                engineDynamicRange.removeObject(forKey: layer)
            }
        }
    }

    private func placePicture() {
        applyDynamicRange()
        playerView.transform = .identity
        pictureOverlayView.transform = .identity
        let gravity: AVLayerVideoGravity
        let pictureFit: PictureFit = switch fit { case .fit: .fit; case .fill: .fill; case .stretch: .stretch }
        if let size = displaySize, let layout = PictureGeometry(bounds: bounds.size, source: size, aspect: aspect, crop: crop,
                                                               fit: pictureFit, zoom: zoom, inset: inset) {
            clipView.frame = layout.visible
            playerView.frame = layout.picture.offsetBy(dx: -layout.visible.minX, dy: -layout.visible.minY)
            overlay.frame = bounds
            overlay.videoRect = layout.visible
            overlay.pictureRect = layout.picture
            gravity = .resize
        } else {
            clipView.frame = bounds
            playerView.frame = bounds
            overlay.frame = bounds
            overlay.videoRect = bounds
            overlay.pictureRect = bounds
            gravity = .resizeAspect
        }
        // Sent on every layout, not only on a change: the engine can make a new video layer when a file loads, which starts at its
        // default gravity.
        lastGravity = gravity
        onGravity?(gravity)
        // The picture overlay (AI super resolution) follows the picture, transform included.
        pictureOverlayView.bounds = CGRect(origin: .zero, size: playerView.bounds.size)
        pictureOverlayView.center = playerView.center
        pictureOverlayView.transform = playerView.transform
        pictureOverlay?.frame = pictureOverlayView.bounds
        (pictureOverlay as? AVSampleBufferDisplayLayer)?.videoGravity = gravity
    }

    func hostPictureOverlay(_ layer: CALayer?) {
        if layer == nil && pictureOverlay == nil { return }
        guard layer !== pictureOverlay || layer?.superlayer !== pictureOverlayView.layer else { return }
        if pictureOverlay?.superlayer === pictureOverlayView.layer { pictureOverlay?.removeFromSuperlayer() }
        pictureOverlay = layer
        if let layer { pictureOverlayView.layer.addSublayer(layer) }
        setNeedsLayout()
    }
}

/// Draws the engine's subtitle cues: text (plain or styled runs) and pictures (PGS, VobSub, DVB).
final class AetherSubtitleOverlay: UIView {
    var style = AetherSubtitleStyle() { didSet { needsRestyle = true } }
    var videoRect: CGRect = .zero { didSet { if videoRect != oldValue { setNeedsLayout() } } }
    var pictureRect: CGRect = .zero { didSet { if pictureRect != oldValue { setNeedsLayout() } } }
    private var shown: [SubtitleCue] = []
    private var textViews: [UILabel] = []
    private var imageViews: [UIImageView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(cues: [SubtitleCue], at time: Double) {
        let active = cues.filter { $0.startTime <= time && time < $0.endTime }
        if active.map(\.id) == shown.map(\.id), !needsRestyle { return }
        needsRestyle = false
        shown = active
        rebuild()
    }

    private var needsRestyle = false

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuild()
    }

    private func rebuild() {
        textViews.forEach { $0.removeFromSuperview() }
        imageViews.forEach { $0.removeFromSuperview() }
        textViews = []
        imageViews = []
        let rect = videoRect.isEmpty ? bounds : videoRect
        let fullPicture = pictureRect.isEmpty ? rect : pictureRect
        guard rect.width > 0, rect.height > 0 else { return }
        let fontSize = max(14, rect.height * 0.05 * style.scale)
        var bottom = rect.maxY - rect.height * style.bottomMarginPercent / 100
        // Later cues stack above earlier ones, as players do.
        for cue in shown.reversed() {
            switch cue.body {
            case .image(let image):
                let view = UIImageView(image: UIImage(cgImage: image.cgImage))
                view.frame = Self.imageRect(image, in: fullPicture, viewport: bounds)
                addSubview(view)
                imageViews.append(view)
            case .text(let text):
                bottom = place(attributed(runs: [SubtitleTextRun(text: text, color: nil)], fontSize: fontSize), placement: cue.placement,
                               in: rect, bottom: bottom, fontSize: fontSize)
            case .richText(let runs):
                bottom = place(attributed(runs: runs, fontSize: fontSize), placement: cue.placement, in: rect, bottom: bottom, fontSize: fontSize)
            }
        }
    }

    /// Positions one text block; returns the new bottom for the default (stacked) placement.
    private func place(_ text: NSAttributedString, placement: SubtitleTextPlacement?, in rect: CGRect, bottom: CGFloat, fontSize: CGFloat) -> CGFloat {
        guard text.length > 0 else { return bottom }
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.attributedText = text
        if style.boxed {
            label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            label.layer.cornerRadius = fontSize * 0.2
            label.layer.masksToBounds = true
        } else {
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.9
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = .zero
        }
        let pad = style.boxed ? fontSize * 0.3 : 0
        let fitted = label.sizeThatFits(CGSize(width: rect.width * 0.9 - pad * 2, height: .greatestFiniteMagnitude))
        let size = CGSize(width: fitted.width + pad * 2, height: fitted.height + pad)
        let origin: CGPoint
        var nextBottom = bottom
        if let placement, placement.alignment.map({ $0 > 3 }) == true || placement.position != nil {
            origin = Self.blockOrigin(placement, size: size, in: rect, margin: rect.height * style.bottomMarginPercent / 100)
        } else {
            origin = CGPoint(x: rect.midX - size.width / 2, y: bottom - size.height)
            nextBottom = origin.y - fontSize * 0.2
        }
        label.frame = CGRect(origin: origin, size: size)
        addSubview(label)
        textViews.append(label)
        return nextBottom
    }

    private func attributed(runs: [SubtitleTextRun], fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base = UIColor(red: style.red, green: style.green, blue: style.blue, alpha: 1)
        for run in runs {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.isBold, !style.overridesFileStyles { traits.insert(.traitBold) }
            if run.isItalic { traits.insert(.traitItalic) }
            var font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: descriptor, size: fontSize) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let colour = run.color, !style.overridesFileStyles {
                attributes[.foregroundColor] = UIColor(red: CGFloat(colour.r) / 255, green: CGFloat(colour.g) / 255, blue: CGFloat(colour.b) / 255, alpha: 1)
            } else {
                attributes[.foregroundColor] = base
            }
            if !style.boxed {
                attributes[.strokeColor] = UIColor.black
                attributes[.strokeWidth] = -3.0
            }
            if run.isUnderlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.isStruckThrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// `position` is normalised against the subtitle canvas, mapped onto the scaled source picture (`rect`), and clamped vertically
    /// inside `viewport` when bottom black bars are cropped beyond the screen edge.
    static func imageRect(_ image: SubtitleImage, in rect: CGRect, viewport: CGRect = .zero) -> CGRect {
        let position = image.position
        let canvas = image.canvasSize
        let raw: CGRect
        if canvas.width > 0, canvas.height > 0 {
            let scale = rect.width / canvas.width
            raw = CGRect(x: rect.minX + position.minX * canvas.width * scale,
                         y: rect.midY + (position.minY * canvas.height - canvas.height / 2) * scale,
                         width: position.width * canvas.width * scale, height: position.height * canvas.height * scale)
        } else {
            raw = CGRect(x: rect.minX + position.minX * rect.width, y: rect.minY + position.minY * rect.height,
                         width: position.width * rect.width, height: position.height * rect.height)
        }
        guard !viewport.isEmpty, viewport.height > raw.height + 16 else { return raw }
        let clampedY = min(max(viewport.minY + 8, raw.minY), viewport.maxY - raw.height - 8)
        return CGRect(x: raw.minX, y: clampedY, width: raw.width, height: raw.height)
    }

    /// ASS numpad alignment (1–3 bottom, 4–6 middle, 7–9 top); with a position, the point is the anchor. Top-left coordinates.
    static func blockOrigin(_ placement: SubtitleTextPlacement, size: CGSize, in rect: CGRect, margin: CGFloat) -> CGPoint {
        let alignment = placement.alignment ?? 2
        let column = (alignment - 1) % 3
        let row = (alignment - 1) / 3
        guard let position = placement.position else {
            let x = column == 0 ? rect.minX + margin : column == 1 ? rect.midX - size.width / 2 : rect.maxX - size.width - margin
            let y = row == 0 ? rect.maxY - size.height - margin : row == 1 ? rect.midY - size.height / 2 : rect.minY + margin
            return CGPoint(x: x, y: y)
        }
        let anchorX = rect.minX + position.x * rect.width
        let anchorY = rect.minY + position.y * rect.height
        let x = column == 0 ? anchorX : column == 1 ? anchorX - size.width / 2 : anchorX - size.width
        let y = row == 0 ? anchorY - size.height : row == 1 ? anchorY - size.height / 2 : anchorY
        return CGPoint(x: x, y: y)
    }
}
#endif
