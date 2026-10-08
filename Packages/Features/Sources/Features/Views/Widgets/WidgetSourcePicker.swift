#if canImport(UIKit)
import StremioKit
import SwiftUI

struct WidgetSourcePicker: View {
    let model: WidgetsManagerViewModel
    var genresOnly = false
    let choose: (WidgetsManagerViewModel.CatalogChoice, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            ForEach(model.catalogChoices.filter {
                (!genresOnly || !$0.genres.isEmpty) && (query.isEmpty || "\($0.title) \($0.addonName)".localizedCaseInsensitiveContains(query))
            }) { choice in
                if choice.genres.isEmpty || genresOnly {
                    Button { choose(choice, nil) } label: { label(choice) }
                } else {
                    NavigationLink {
                        List {
                            Button("All Genres") { choose(choice, nil) }
                            ForEach(choice.genres, id: \.self) { genre in Button(genre) { choose(choice, genre) } }
                        }
                        .navigationTitle(choice.title)
                        .scrollContentBackground(.hidden)
                        .screenBackground()
                    } label: { label(choice) }
                }
            }
        }
        .searchable(text: $query, prompt: "Find a catalog")
        .navigationTitle("Choose Source")
        .scrollContentBackground(.hidden)
        .screenBackground()
        .accessibilityIdentifier("widgetSource.list")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func label(_ choice: WidgetsManagerViewModel.CatalogChoice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(choice.title)
            Text(choice.addonName).font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
