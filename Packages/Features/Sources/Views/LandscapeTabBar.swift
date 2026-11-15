#if canImport(UIKit)
import Persistence
import SwiftUI
import StremioKit

/// The tab bar collapses to Home after scrolling down on a landscape iPhone.
@MainActor
@Observable
final class LandscapeTabBarState {
    var collapsed = false
    /// The current pushed browse/picker page, shown on top of the landscape panel.
    var pageTitle: String?
    /// The browse-page title hidden while a title detail is on top of it.
    private var suspendedPageTitle: String?
    /// A detail page stays tucked away through its initial downward scroll and expands only when the user reverses upward.
    private var waitsForUpwardScroll = false
    private var previousOffset: CGFloat?
    private var distanceDown: CGFloat = 0
    private var distanceUp: CGFloat = 0

    func showPageTitle(_ title: String) {
        pageTitle = title
        suspendedPageTitle = nil
    }

    func clearPageTitle() {
        pageTitle = nil
        suspendedPageTitle = nil
    }

    func reset() {
        collapsed = false
        waitsForUpwardScroll = false
        previousOffset = nil
        distanceDown = 0
        distanceUp = 0
    }

    func prepareForDetailPage() {
        collapsed = true
        waitsForUpwardScroll = true
        if let pageTitle { suspendedPageTitle = pageTitle }
        pageTitle = nil
        previousOffset = nil
        distanceDown = 0
        distanceUp = 0
    }

    func restoreAfterDetailPage() {
        reset()
        pageTitle = suspendedPageTitle
        suspendedPageTitle = nil
    }

    func update(offset: CGFloat) {
        let offset = max(0, offset)
        guard offset > 8 else {
            if waitsForUpwardScroll {
                previousOffset = offset
                distanceDown = 0
                distanceUp = 0
            } else {
                reset()
            }
            return
        }
        guard let previousOffset else { self.previousOffset = offset; return }
        self.previousOffset = offset
        let difference = offset - previousOffset
        // A tab-bar visibility change can relayout the scroll view. Ignore jumps instead of treating them as scrolling.
        guard abs(difference) < 100 else { return }
        if difference > 1 {
            distanceDown += difference
            distanceUp = 0
            if distanceDown >= 35 { collapsed = true; distanceDown = 0 }
        } else if difference < -1 {
            distanceUp -= difference
            distanceDown = 0
            // Scrolling back up brings the icons back almost at once.
            if distanceUp >= 12 {
                collapsed = false
                waitsForUpwardScroll = false
                distanceUp = 0
            }
        }
    }

    /// How far the landscape buttons (Back, Home and its panel, Search) sit from the screen's two edges at their corner: a 44-point
    /// round button whose edge keeps an even 6-point gap from the curve of an iPhone's roughly 55-point screen corner. They sit out in the
    /// corners, past the safe area at the sides, rather than over the page.
    static let cornerInset: CGFloat = 14
    static func edgeInset(for width: CGFloat) -> CGFloat { cornerInset + (width * 0.015).rounded() }
    static let buttonDiameter: CGFloat = 44
    /// The landscape Back button's corner gap and 44-point height. A page whose navigation bar is hidden in phone landscape starts its
    /// content below this, so the button sits clear of the artwork at rest.
    static let backClearance: CGFloat = cornerInset + buttonDiameter
}

private struct LandscapeTabScrollModifier: ViewModifier {
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape
    @Environment(LandscapeTabBarState.self) private var landscapeTabs: LandscapeTabBarState?

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // Mac has no collapsing phone tab bar, so it needs no per-scroll tracking.
        content
        #else
        content.onScrollGeometryChange(for: CGFloat.self) {
            guard isPhoneLandscape, UIDevice.current.userInterfaceIdiom == .phone else { return 0 }
            return max(0, $0.contentOffset.y + $0.contentInsets.top)
        } action: { _, offset in
            guard isPhoneLandscape, UIDevice.current.userInterfaceIdiom == .phone else { return }
            landscapeTabs?.update(offset: offset)
        }
        #endif
    }
}

extension View {
    func macRootNavigation() -> some View {
        #if targetEnvironment(macCatalyst)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    func macBackNavigation() -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacBackNavigation())
        #else
        self
        #endif
    }

    func pageNavigationBar(hidden: Bool) -> some View {
        #if targetEnvironment(macCatalyst)
        toolbar(.hidden, for: .navigationBar)
        #else
        toolbarVisibility(hidden ? .hidden : .automatic, for: .navigationBar)
        #endif
    }

    func trackLandscapeTabScroll() -> some View {
        modifier(LandscapeTabScrollModifier())
    }
}

/// Mac uses the shared app-level navigation. iPad keeps its adaptive sidebar.
struct TabBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.tabViewStyle(.tabBarOnly)
        #else
        if UIDevice.current.userInterfaceIdiom == .phone {
            content.tabViewStyle(.tabBarOnly)
        } else {
            content.tabViewStyle(.sidebarAdaptable)
        }
        #endif
    }
}

/// Landscape controls: one glass panel with the page's title on top, a hairline, and Home with the tab icons below. Scrolling down slides
/// the panel left and leaves Home alone in the corner; scrolling up slides it back in from the left. Home stays the same size and
/// position throughout, without a native tab-bar relayout.
/// Slide selection is iPhone-only because the Mac uses native tab navigation instead of this compact bar.
struct LandscapeTabControls: View {
    @Environment(\.layoutMetrics) private var metrics
    let router: AppRouter
    let collapsed: Bool
    let title: String
    let hidesPageHeader: Bool
    let onHome: () -> Void
    let onReveal: () -> Void
    /// The selected tab takes Appearance's accent.
    @Environment(\.appAppearance) private var appearance

    private var currentTab: (symbol: String, title: String) {
        switch router.tab {
        case .home: ("play.house.fill", "Home")
        case .discover: ("square.grid.2x2.fill", "Discover")
        case .library: ("books.vertical.fill", "Library")
        case .settings: ("gearshape.fill", "Settings")
        case .search: ("magnifyingglass", "Search")
        case .widgets: ("rectangle.3.group.fill", "Widgets")
        }
    }

    /// Home and three tab icons, 44 points each, 12 apart.
    private static let panelContentWidth: CGFloat = 44 * 4 + 12 * 3
    /// Every corner takes Home's radius, so Home sits flush in the bottom-leading corner and the panel's corners all match under any
    /// corner setting. Home's 44-point shape can't round past 22 points, so neither does the panel.
    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22 * min(metrics.circularButtonScale(for: .actionButtons), 1), style: .continuous)
    }
    /// The panel slides away smoothly and returns on a soft spring; Search uses the same timing for its fade.
    static func fade(collapsed: Bool) -> Animation {
        collapsed ? Theme.Motion.standard : .spring(duration: 0.38, bounce: 0.18)
    }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if !hidesPageHeader {
                    Text(title)
                        .appFont(.smallStrong)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 6)
                        .padding(.top, 11)
                        .padding(.bottom, 9)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("landscape.pageTitle")
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(height: 0.5)
                        // A little gap so the line clears the round buttons below it.
                        .padding(.bottom, 6)
                }
                HStack(spacing: 12) {
                    Color.clear.frame(width: 44, height: 44)
                    tabButton(.discover, symbol: "square.grid.2x2", selectedSymbol: "square.grid.2x2.fill", title: "Discover")
                    tabButton(.library, symbol: "books.vertical", selectedSymbol: "books.vertical.fill", title: "Library")
                    tabButton(.settings, symbol: "gearshape", selectedSymbol: "gearshape.fill", title: "Settings")
                }
                .contentShape(Rectangle())
                .highPriorityGesture(tabDrag)
            }
            .frame(width: Self.panelContentWidth)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            // The clearer, more see-through variant of Liquid Glass; it clears away with the rest when scrolled.
            .glassEffect(.clear, in: panelShape)
            .offset(x: collapsed ? -(Self.panelContentWidth + 10 + 12) : 0)
            // Cut the sliding panel to its own rounded outline, which matches Home's corners, so no square edge shows past Home; it
            // fades as it goes, so its icons don't pass visibly behind Home's glass.
            .clipShape(panelShape)
            .opacity(collapsed ? 0 : 1)
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)
            .animation(Self.fade(collapsed: collapsed), value: collapsed)

            // This is the same instance in both states: it never moves, scales or changes glass.
            Button {
                Haptics.play(.navigation)
                if collapsed { onReveal() } else { onHome() }
            } label: {
                Image(systemName: collapsed ? currentTab.symbol : (router.tab == .home ? "play.house.fill" : "play.house"))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(router.tab == .home ? appearance.selectionColour : .white)
                    .frame(width: 44, height: 44)
                    .buttonSurface(.regular, in: ScaledCapsule(scale: metrics.circularButtonScale(for: .actionButtons)))
                    .contentShape(ScaledCapsule(scale: metrics.circularButtonScale(for: .actionButtons)))
            }
            .buttonStyle(.hoverPlain)
            .accessibilityLabel(collapsed ? currentTab.title : "Home")
            .accessibilityIdentifier("landscape.home")
            .highPriorityGesture(tabDrag)
        }
        .coordinateSpace(name: "landscapeTabs")
    }

    private var tabDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("landscapeTabs"))
            .onChanged { drag in
                guard (!collapsed || drag.translation.width > 8), abs(drag.translation.width) > abs(drag.translation.height) else { return }
                // Open the whole panel once; reversing a held drag must not slice through its glass.
                if collapsed { onReveal() }
                // Boundaries sit halfway between the existing 44-point buttons, including Home's separate circle.
                let tab: LaunchRoute.Tab
                switch drag.location.x {
                case ..<55: tab = .home
                case ..<116: tab = .discover
                case ..<172: tab = .library
                default: tab = .settings
                }
                guard tab != router.tab else { return }
                // A tick as the drag crosses into another tab, so the finger learns the tab changed before it lifts.
                Haptics.play(.navigation)
                if tab == .home { router.tapTab(.home) } else { router.tapTab(tab) }
            }
    }

    private func tabButton(_ tab: LaunchRoute.Tab, symbol: String, selectedSymbol: String, title: String) -> some View {
        Button {
            Haptics.play(.navigation)
            router.tapTab(tab)
        } label: {
            Image(systemName: router.tab == tab ? selectedSymbol : symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(router.tab == tab ? appearance.selectionColour : .white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.hoverPlain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("landscape.\(title.lowercased())")
    }
}
#endif
