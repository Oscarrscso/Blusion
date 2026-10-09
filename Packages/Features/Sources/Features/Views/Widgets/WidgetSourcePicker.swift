#if canImport(UIKit)
import StremioKit
import SwiftUI

struct WidgetSourcePicker: View {
    let model: WidgetsManagerViewModel
    var genresOnly = false
    /// A Trakt list or feed was chosen. Collections take addon genres only, so Trakt is not offered for them.
    var chooseTrakt: (WidgetSource) -> Void = { _ in }
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
            if !genresOnly && query.isEmpty {
                Section("Trakt") {
                    ForEach(TraktFeed.allCases, id: \.self) { feed in
                        Button { chooseTrakt(.traktFeed(feed)) } label: { Text(feed.title) }
                            .accessibilityIdentifier("widgetSource.trakt.\(feed.rawValue)")
                    }
                    NavigationLink {
                        TraktListLinkForm(model: model, chooseTrakt: chooseTrakt)
                    } label: {
                        Text("Trakt List from Link")
                    }
                    .accessibilityIdentifier("widgetSource.trakt.link")
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

/// Adds a public Trakt list from its link. The list's name is read from Trakt, so a bad link or a missing client ID is said here.
private struct TraktListLinkForm: View {
    let model: WidgetsManagerViewModel
    let chooseTrakt: (WidgetSource) -> Void
    @State private var link = ""
    @State private var isReading = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                TextField("trakt.tv/users/name/lists/list-name", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("widgetSource.trakt.linkField")
                Button {
                    Task { await addList() }
                } label: {
                    if isReading { ProgressView() } else { Text("Add List") }
                }
                .disabled(isReading || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("widgetSource.trakt.add")
            } footer: {
                if let problem { Text(problem).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Trakt List")
        .scrollContentBackground(.hidden)
        .screenBackground()
    }

    private func addList() async {
        isReading = true
        defer { isReading = false }
        do {
            let list = try await model.traktList(fromLink: link)
            problem = nil
            chooseTrakt(.traktList(list))
            dismiss()
        } catch let error as WidgetsManagerViewModel.TraktLinkError {
            problem = error.message
        } catch {
            problem = "Trakt couldn't read this list."
        }
    }
}
#endif
