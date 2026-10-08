#if canImport(UIKit)
import SwiftUI

/// Settings › Widgets: the rows that make up Home. Add, edit, reorder, remove, import and export them.
struct WidgetsManagerView: View {
    let services: AppServices

    var body: some View {
        ContentUnavailableView("Widgets", systemImage: "rectangle.3.group",
                               description: Text("Choose which rows appear on Home."))
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("widgets.manager")
    }
}
#endif
