#if canImport(SwiftUI)
import SwiftUI
import StremioKit

struct SearchView: View {
    @State private var model: SearchViewModel

    init(services: AppServices) {
        _model = State(initialValue: SearchViewModel(services: services))
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !model.failures.isEmpty {
                    WrappingStack {
                        ForEach(model.failures) { ErrorChip(text: $0.text) }
                    }
                    .padding(.horizontal)
                    .accessibilityIdentifier("search.failures")
                }
                ForEach(model.sections) { section in
                    if !section.items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.addon.name).font(.title3.bold()).padding(.horizontal).accessibilityAddTraits(.isHeader)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(section.items) { PosterLink(item: $0) }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                status
            }
            .padding(.vertical)
        }
        .navigationTitle("Search")
        .searchable(text: $model.query, prompt: "Movies")
        .onChange(of: model.query) { model.queryDidChange() }
        .onSubmit(of: .search) { Task { await model.submit() } }
        .accessibilityIdentifier("search.results")
    }

    @ViewBuilder
    private var status: some View {
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
#endif
