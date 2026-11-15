#if canImport(UIKit)
import SwiftUI

/// The page Mac Settings shows to the right of the page it was opened from (Appearance → Colour beside Appearance), as the list opens a
/// page beside itself. Only Mac Settings provides one (see `SettingsView`); without it a `SettingsSubpageLink` pushes its page.
@MainActor
@Observable
final class SettingsSidePage {
    /// The open row's identity, which lights it.
    private(set) var openID: String?
    private(set) var page: AnyView?
    /// True on Mac (where re-clicking closes the third column); false in two-column phone landscape so the detail column stays filled.
    var closesWhenToggled = true

    /// Opens `id`'s page, or closes it when it is already open (if `closesWhenToggled`).
    func toggle(_ id: String, page: () -> AnyView) {
        if openID == id {
            if closesWhenToggled { close() }
        } else {
            openID = id
            self.page = page()
        }
    }

    func close() {
        openID = nil
        page = nil
    }
}

extension EnvironmentValues {
    @Entry var settingsSidePage: SettingsSidePage? = nil
    @Entry var showsSettingsColumnTitle = false
    @Entry var settingsColumnDepth = 0
}

/// A Settings page's row that opens a page of its own: pushed on iPhone, beside the page in Mac Settings, where the open row is lit and
/// choosing it again closes the page.
struct SettingsSubpageLink<Label: View, Destination: View>: View {
    let id: String
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label
    @Environment(\.settingsSidePage) private var sidePage

    init(id: String, @ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.id = id
        self.destination = destination
        self.label = label
    }

    var body: some View {
        if let sidePage {
            let isOpen = sidePage.openID == id
            Button {
                Haptics.play(.buttons)
                if sidePage.closesWhenToggled {
                    withAnimation(Theme.Motion.quick) { sidePage.toggle(id) { AnyView(destination()) } }
                } else {
                    sidePage.toggle(id) { AnyView(destination()) }
                }
            } label: {
                HStack {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(Theme.Typography.smallStrong)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            #if targetEnvironment(macCatalyst)
            .buttonStyle(.settingsHover)
            #else
            .buttonStyle(.hoverPlain)
            #endif
            .listRowBackground(SettingsRowBackground(isSelected: isOpen))
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        } else {
            NavigationLink(destination: destination, label: label)
        }
    }
}

/// Where a Settings column title sits relative to the Mac navigation. The list and the heading share this so the title clears the
/// navigation without a second empty band under it.
enum SettingsColumnTitleLayout {
    /// On Mac the shared navigation floats over the top of the window. The column title starts beneath that band, clear of the control
    /// and of Back or Close, which sit in it. Other platforms draw the title at the top of the column.
    static var topClearance: CGFloat {
        #if targetEnvironment(macCatalyst)
        MacPageNavigation.height
        #else
        0
        #endif
    }

    /// The list reserves the navigation band when the title is not already leaving it. A pushed page still reserves it so Back, which is
    /// drawn at the top of the list, stays clear of the first row.
    static func reservesNavigationSpace(showsColumnTitle: Bool, showsBack: Bool) -> Bool {
        if topClearance > 0, showsColumnTitle, !showsBack { return false }
        return true
    }
}

/// Each settings column owns its heading, even when its navigation bar is hidden.
struct SettingsColumnHeading: ViewModifier {
    let title: String
    var action: AnyView? = nil
    @Environment(\.showsSettingsColumnTitle) private var showsTitle
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.isPhoneLandscape) private var isPhoneLandscape

    func body(content: Content) -> some View {
        if showsTitle {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).headingStyle()
                        Spacer(minLength: Theme.Spacing.m)
                        action
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, Theme.Spacing.xl)
                        .padding(.bottom, Theme.Spacing.l)
                        .readableColumn()
                        .padding(.top, SettingsColumnTitleLayout.topClearance)
                        .screenBackground(reservesNavigationSpace: false)
                }
        } else {
            content
        }
    }

    /// The page margin, then one more standard inset, so the title is not tight against the column edge and lines up with the
    /// section titles in the list. Phone landscape insets that list by `Theme.Spacing.m`; the title keeps the same extra inset.
    private var horizontalPadding: CGFloat {
        let landscapeInset = isPhoneLandscape && UIDevice.current.userInterfaceIdiom == .phone ? Theme.Spacing.m : 0
        return metrics.pageMargin + Theme.Spacing.l + landscapeInset
    }
}

#if targetEnvironment(macCatalyst)
/// Mac Settings' detail: the chosen page always stays beside the page opened from it. Its Close button sits at the trailing corner, clear of the navigation over the window's centre.
struct SettingsDetailColumns<Page: View>: View {
    let sidePage: SettingsSidePage
    @ViewBuilder let page: () -> Page
    @State private var sidePath = NavigationPath()

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // One view throughout, so the page keeps its place and state as the column opens and closes.
                page()
                    .environment(\.settingsSidePage, sidePage)
                    .frame(width: sidePage.page == nil ? geometry.size.width : min(400, geometry.size.width * 0.45))
                    .clipped()
                if let opened = sidePage.page {
                    Divider().ignoresSafeArea()
                    NavigationStack(path: $sidePath) {
                        opened
                            .overlay(alignment: .topTrailing) { closeButton }
                    }
                    .environment(\.settingsColumnDepth, sidePath.count)
                    .id(sidePage.openID)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .environment(\.showsSettingsColumnTitle, true)
        }
        .onChange(of: sidePage.openID) { sidePath = NavigationPath() }
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark") {
            withAnimation(Theme.Motion.quick) { sidePage.close() }
        }
        .labelStyle(.iconOnly)
        .fontWeight(.semibold)
        .buttonStyle(FixedGlassButtonStyle(size: MacPageNavigation.controlHeight))
        .padding(MacPageNavigation.inset)
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .accessibilityIdentifier("settings.sidePage.close")
    }
}
#endif
#endif
