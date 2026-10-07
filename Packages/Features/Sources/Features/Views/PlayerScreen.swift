#if canImport(SwiftUI)
import SwiftUI
import StremioKit

/// Replaced by the real player in M5.
struct PlayerScreen: View {
    let plan: PlaybackPlan
    let services: AppServices
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(plan.request.title).font(.title2)
            Button("Close") { dismiss() }
        }
    }
}
#endif
