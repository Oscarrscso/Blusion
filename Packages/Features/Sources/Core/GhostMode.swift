#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Ghost mode: while it is on, nothing that is watched leaves a trace. No position or watched mark is saved, so nothing joins Continue
/// Watching, and Trakt is neither read nor told anything. It stays on, across launches, until it is switched off. Settings turns it on
/// and off with a pull past the top, the same distance lock the player uses to lock 2× (`GhostModePullRules`); the stores and the Trakt
/// sync read it here.
enum GhostMode {
    /// The key the choice is kept under, which Settings also watches to draw its indicator.
    static let defaultsKey = "ghostMode.isOn"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

/// How far Settings must be pulled past its top to arm and then toggle Ghost mode. Same shape as `SpeedHoldRules`' drag-down lock: the
/// ring fills with distance, and crossing `lockDistance` past the arm mark toggles once. Pure arithmetic so the steps are tested on the
/// host; `SettingsView` feeds it the overscroll.
enum GhostModePullRules {
    /// Pull past this before the ring starts filling toward a toggle.
    static let armPull: CGFloat = 40
    /// Extra pull past `armPull` that completes the toggle — the same distance the player uses to lock 2×.
    static let lockDistance: CGFloat = CGFloat(SpeedHoldRules.lockDistance)

    /// How far a pull has got toward toggling, from 0 to 1. Reaches 1 where `locks` turns true.
    static func progress(pull: CGFloat) -> Double {
        guard pull.isFinite else { return 0 }
        return min(1, max(0, Double((pull - armPull) / lockDistance)))
    }

    /// Whether a pull has gone far enough to toggle Ghost mode.
    static func locks(pull: CGFloat) -> Bool {
        pull.isFinite && pull > armPull + lockDistance
    }
}
