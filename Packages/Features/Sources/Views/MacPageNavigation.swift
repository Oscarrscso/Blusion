#if canImport(UIKit)
import Persistence
import SwiftUI
import StremioKit

extension EnvironmentValues {
    @Entry var hasMacBackNavigation = false
}

/// One navigation view for every Mac page, moved with the active page's scroll offset.
struct MacPageNavigation: View {
    @Environment(\.layoutMetrics) private var metrics
    static let height: CGFloat = 64
    static let controlHeight: CGFloat = 32
    /// The control's widest, and its distance from the window's edges.
    static let maxWidth: CGFloat = 650
    static let inset: CGFloat = 16

    /// Space from the window's top edge to the first control below the navigation bar, leaving `spacing` below the control's bottom edge.
    static func topInset(spacing: CGFloat) -> CGFloat { inset + controlHeight + spacing }
    #if targetEnvironment(macCatalyst)
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appAppearance.hover) private var hover
    @State private var hoveredSegment: Int?
    #endif

    var body: some View {
        #if targetEnvironment(macCatalyst)
        GeometryReader { geometry in
            let tabs: [LaunchRoute.Tab] = [.home, .discover, .library, .settings, .widgets, .search]
            let segmentWidth = geometry.size.width / CGFloat(tabs.count)
            // The segmented control draws the selection; clear hit targets above it always call `tapTab`, including a re-tap of Home
            // from a title page (a segmented picker does not set its binding when the chosen segment is tapped again).
            CornerSegmentedPicker("Navigation", options: tabs, selection: .constant(router.tab)) { tab in
                switch tab {
                case .home: "Home"
                case .discover: "Discover"
                case .library: "Library"
                case .settings: "Settings"
                case .widgets: "Widgets"
                case .search: "Search"
                }
            }
            .controlSize(.regular)
            .appFont(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { tab in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { router.tapTab(tab) }
                            .accessibilityAddTraits(tab == router.tab ? [.isButton, .isSelected] : .isButton)
                            .accessibilityLabel({
                                switch tab {
                                case .home: "Home"
                                case .discover: "Discover"
                                case .library: "Library"
                                case .settings: "Settings"
                                case .widgets: "Widgets"
                                case .search: "Search"
                                }
                            }())
                    }
                }
            }
            .overlay {
                if let hoveredSegment {
                    ScaledCapsule(scale: metrics.cornerScale(for: .filters))
                        .fill(.white.opacity(hover.segmentFillOpacity))
                        .overlay { ScaledCapsule(scale: metrics.cornerScale(for: .filters)).strokeBorder(.white.opacity(hover.segmentRimOpacity), lineWidth: 1) }
                        .frame(width: max(0, segmentWidth - 4), height: Self.controlHeight - 4)
                        .position(x: segmentWidth * (CGFloat(hoveredSegment) + 0.5), y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(hover.animation(0.15, reduceMotion: reduceMotion), value: hoveredSegment)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard segmentWidth > 0, geometry.frame(in: .local).contains(location) else {
                        hoveredSegment = nil
                        return
                    }
                    hoveredSegment = min(tabs.count - 1, Int(location.x / segmentWidth))
                case .ended:
                    hoveredSegment = nil
                }
            }
        }
        .frame(maxWidth: Self.maxWidth)
        .frame(height: Self.controlHeight)
        // A soft shadow under the control, so it stands out from whatever the page shows behind it.
        .background {
            Capsule()
                .fill(.black.opacity(0.45))
                .blur(radius: 10)
                .offset(y: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity)
        #else
        EmptyView()
        #endif
    }
}

extension View {
    /// A page's top selector: on Mac it takes the shared navigation's width and centre, so the two line up; elsewhere, `margin` each side.
    func navigationAlignedWidth(margin: CGFloat) -> some View {
        #if targetEnvironment(macCatalyst)
        frame(maxWidth: MacPageNavigation.maxWidth)
            .padding(.horizontal, MacPageNavigation.inset)
            .frame(maxWidth: .infinity)
        #else
        padding(.horizontal, margin)
        #endif
    }
}

extension View {
    func macPageScroll(reservesNavigationSpace: Bool = true) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacPageScroll(reservesNavigationSpace: reservesNavigationSpace))
        #else
        self
        #endif
    }

    func pageTabBar(hidden: Bool) -> some View {
        modifier(PageTabBarModifier(hidden: hidden))
    }
}

/// The tab bar on a page: hidden where the page asks, and on every page while the editorial pill bar stands in for it.
private struct PageTabBarModifier: ViewModifier {
    let hidden: Bool
    @Environment(\.usesEditorialTabBar) private var usesEditorialTabBar

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackgroundVisibility(.hidden, for: .tabBar)
        #else
        content.toolbar(hidden || usesEditorialTabBar ? .hidden : .automatic, for: .tabBar)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Whether the Mac's navigation is showing. Scrolling a page down hides it and scrolling up brings it straight back, on every page; at the
/// top of a page it always shows. Each scrolling page reports its own offset, so two side by side (Settings' list and page) do not mix.
@MainActor
@Observable
final class MacNavigationScrollState {
    private(set) var isHidden = false
    @ObservationIgnored private var lastOffsets: [UUID: CGFloat] = [:]
    /// How far the page has scrolled in its current direction.
    @ObservationIgnored private var travel: CGFloat = 0
    /// How far a scroll runs one way before the navigation follows it, so a trackpad's small wobbles do not flick it.
    private static let threshold: CGFloat = 12

    func update(offset: CGFloat, maxOffset: CGFloat, from page: UUID) {
        let previous = lastOffsets[page] ?? offset
        lastOffsets[page] = offset
        guard offset > MacPageNavigation.height else {
            travel = 0
            setHidden(false)
            return
        }
        // The bounce past the page's end moves back up by itself, which is no scroll up.
        guard offset <= maxOffset else { return }
        let delta = offset - previous
        guard delta != 0 else { return }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel > Self.threshold { setHidden(true) } else if travel < -Self.threshold { setHidden(false) }
    }

    /// A page has come on screen: the navigation shows on it.
    func show() {
        travel = 0
        setHidden(false)
    }

    func forget(_ page: UUID) { lastOffsets[page] = nil }

    private func setHidden(_ hidden: Bool) {
        if isHidden != hidden { isHidden = hidden }
    }
}

struct MacPageNavigationOverlay: View {
    @Environment(MacNavigationScrollState.self) private var scroll
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MacPageNavigation()
            // Slides up out of the window, or fades with Reduce Motion.
            .offset(y: scroll.isHidden && !reduceMotion ? -MacPageNavigation.height : 0)
            .opacity(scroll.isHidden && reduceMotion ? 0 : 1)
            .animation(reduceMotion ? Theme.Motion.fade : Theme.Motion.standard, value: scroll.isHidden)
            .frame(height: MacPageNavigation.height, alignment: .top)
            .clipped()
            .allowsHitTesting(!scroll.isHidden)
    }
}

struct MacBackNavigation: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    /// Split-view roots can report themselves as presented even though their stack has no page to pop.
    @Environment(\.isPresented) private var isPresented
    @Environment(\.showsSettingsColumnTitle) private var showsColumnTitle
    @Environment(\.settingsColumnDepth) private var columnDepth
    @Environment(\.hasMacBackNavigation) private var hasMacBackNavigation

    private var showsBackButton: Bool {
        !hasMacBackNavigation && (showsColumnTitle ? columnDepth > 0 : isPresented)
    }

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.hasMacBackNavigation, hasMacBackNavigation || showsBackButton)
            .overlay(alignment: .topLeading) {
                if showsBackButton {
                    // The system's glass button draws a third shorter than its frame on Mac, so the glass is drawn at the navigation
                    // control's height, as the round actions beside Play are.
                    Button("Back", systemImage: "chevron.backward") { dismiss() }
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                        .buttonStyle(FixedGlassButtonStyle(size: MacPageNavigation.controlHeight))
                        .padding(MacPageNavigation.inset)
                        .accessibilityIdentifier("mac.back")
                }
            }
    }
}

private struct MacPageScroll: ViewModifier {
    let reservesNavigationSpace: Bool
    @Environment(MacNavigationScrollState.self) private var navigation: MacNavigationScrollState?
    @Environment(\.layoutMetrics) private var metrics
    /// This page's place in the navigation's scroll tracking.
    @State private var scrollID = UUID()
    @State private var isVisible = false

    private struct Position: Equatable {
        let offset: CGFloat
        let maxOffset: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, reservesNavigationSpace ? MacPageNavigation.topInset(spacing: metrics.cardSpacing) : 0, for: .scrollContent)
            .onScrollGeometryChange(for: Position.self) {
                let insets = $0.contentInsets.top + $0.contentInsets.bottom
                return Position(offset: max(0, $0.contentOffset.y + $0.contentInsets.top),
                                maxOffset: $0.contentSize.height + insets - $0.containerSize.height)
            } action: { _, position in
                if isVisible { navigation?.update(offset: position.offset, maxOffset: position.maxOffset, from: scrollID) }
            }
            .onAppear {
                isVisible = true
                navigation?.show()
            }
            .onDisappear {
                isVisible = false
                navigation?.forget(scrollID)
            }
    }
}
#endif
#endif
