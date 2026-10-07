#if canImport(SwiftUI)
import SwiftUI
import StremioKit

public struct RootTabView: View {
    public enum Tab: Hashable {
        case home, discover, search, addons
    }

    private let services: AppServices
    @State private var selection: Tab

    public init(services: AppServices, initialTab: Tab = .home) {
        self.services = services
        _selection = State(initialValue: initialTab)
    }

    public var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                BoardView(services: services) { selection = .addons }
                    .appDestinations(services: services)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                DiscoverView(services: services) { selection = .addons }
                    .appDestinations(services: services)
            }
            .tabItem { Label("Discover", systemImage: "square.grid.2x2") }
            .tag(Tab.discover)

            NavigationStack {
                SearchView(services: services)
                    .appDestinations(services: services)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(Tab.search)

            NavigationStack {
                AddonsView(services: services)
            }
            .tabItem { Label("Addons", systemImage: "puzzlepiece.extension") }
            .tag(Tab.addons)
        }
    }
}
#endif
