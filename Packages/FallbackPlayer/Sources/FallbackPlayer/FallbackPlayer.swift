import Foundation

public enum FallbackPlayerInfo {
    /// True when the third-party player is linked into this build (ADR-006).
    public static var isMPVLinked: Bool {
        #if canImport(Libmpv)
        return true
        #else
        return false
        #endif
    }
}
