import Foundation
import Observation
import PlayerKit
import StremioKit
#if canImport(SwiftUI)
import SwiftUI
#endif

/// The app-level holder of the playback session that is on the air. The player's full-screen view once owned its `PlayerViewModel`
/// in `@State`, so when SwiftUI dropped that view — a dismissal, or (on some iOS versions) a drop of the cover's content while the
/// app was in the background — the view's disappearance closed the session with it. Now the view adopts, presents and leaves a
/// session that lives here, above any one screen: backgrounding and the view's own visual lifecycle no longer end playback, and a
/// screen that is rebuilt for the same plan rejoins its session instead of starting a second player.
@MainActor
@Observable
final class LivePlaybackSession {
    /// The session on the air now, kept strongly so it outlives the view that presented it.
    private(set) var model: PlayerViewModel?

    init() {}

    /// The player's screen is up: this session is the live one from now on. One at a time — an earlier session still on the books
    /// (its screen is gone or going) is released, so nothing plays on unseen.
    func present(_ model: PlayerViewModel) {
        if let onTheBooks = self.model, onTheBooks !== model, !onTheBooks.isClosed {
            Task { await onTheBooks.close() }
        }
        self.model = model
    }

    /// An explicit close of the named session takes it off the books.
    func forget(_ model: PlayerViewModel) {
        if self.model === model { self.model = nil }
    }

    /// A session this holder keeps open for the given plan, for a player screen that is starting again after a rebuild. A closed or
    /// foreign session is never handed back.
    func session(for plan: PlaybackPlan) -> PlayerViewModel? {
        guard let model, !model.isClosed, model.plan.id == plan.id else { return nil }
        return model
    }

    #if canImport(SwiftUI)
    /// Does a player screen's disappearance close its session?
    ///
    /// `onDisappear` fires on an actual dismissal (the Close button's `dismiss`, the cover's drag-down, the screen being popped), and
    /// SwiftUI may also report the surface as gone while the app is being backgrounded or locked, without a dismissal at all. Only the
    /// first kind stops playback: while the app is leaving or away from the front, the session stays put — the picture (or its audio)
    /// carries on, and a screen that comes back rejoins it.
    static func closesOnDisappear(scenePhase: ScenePhase) -> Bool {
        scenePhase == .active
    }
    #endif
}
