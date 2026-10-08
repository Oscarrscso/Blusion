#if canImport(UIKit)
import SwiftUI
import StremioKit

struct SearchView: View {
    @State private var model: SearchViewModel
    private let initialQuery: String?

    /// `initialQuery` is searched for on arrival (launch routes and UI tests).
    init(services: AppServices, initialQuery: String? = nil) {
        _model = State(initialValue: SearchViewModel(services: services))
        self.initialQuery = initialQuery
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.isOffline {
                    OfflineBanner()
                } else if !model.failures.isEmpty {
                    WrappingStack {
                        ForEach(model.failures) { ErrorChip(text: $0.text) }
                    }
                    .padding(.horizontal)
                    .accessibilityIdentifier("search.failures")
                }
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(.title3.bold()).padding(.horizontal).accessibilityAddTraits(.isHeader)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(group.items, id: \.identity) { PosterLink(item: $0) }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                status
            }
            .padding(.vertical)
        }
        .navigationTitle("Search")
        .searchable(text: $model.query, prompt: "Movies, series and more")
        .onChange(of: model.query) { model.queryDidChange() }
        .onSubmit(of: .search) { Task { await model.submit() } }
        .task { await model.refreshAvailability() }
        .task {
            guard let initialQuery, model.query.isEmpty else { return }
            model.query = initialQuery
            await model.submit()
        }
        .accessibilityIdentifier("search.results")
    }

    @ViewBuilder
    private var status: some View {
        if model.showsNoSearchableAddons {
            ContentUnavailableView("No addon can search", systemImage: "magnifyingglass",
                                   description: Text("Search asks your catalog addons. Add one, such as Cinemeta, in Settings."))
                .accessibilityIdentifier("search.noSearchableAddons")
        } else {
            switch model.phase {
            case .idle:
                ContentUnavailableView("Search your addons", systemImage: "magnifyingglass",
                                       description: Text("Type a title. Every addon that supports search is asked at once."))
            case .searching:
                ProgressView().frame(maxWidth: .infinity)
            case .done:
                if model.showsNoResults {
                    ContentUnavailableView.search(text: model.query)
                }
            }
        }
    }
}
#endif
