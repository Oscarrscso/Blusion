#if canImport(UIKit)
import StremioKit
import SwiftUI

/// The New Widget screen for a Trakt list: a title, how the list is ordered, and a browser of lists and users. Choosing a list sets
/// the widget's source; Add (or Save, when editing) makes the Home carousel. It is the editor's own state, not a second editor.
struct TraktListBrowserView: View {
    let navigationTitle: String
    let actionTitle: String
    @Binding var title: String
    let titlePlaceholder: String
    @Binding var sort: TraktListSort?
    let selectedID: Int?
    let canAdd: Bool
    let select: (TraktListSummary) -> Void
    let commit: () -> Void

    @State private var browser: TraktBrowserViewModel
    @Environment(\.layoutMetrics) private var metrics

    init(services: AppServices, navigationTitle: String, actionTitle: String, title: Binding<String>, titlePlaceholder: String,
         sort: Binding<TraktListSort?>, selectedID: Int?, canAdd: Bool, select: @escaping (TraktListSummary) -> Void,
         commit: @escaping () -> Void) {
        self.navigationTitle = navigationTitle
        self.actionTitle = actionTitle
        _title = title
        self.titlePlaceholder = titlePlaceholder
        _sort = sort
        self.selectedID = selectedID
        self.canAdd = canAdd
        self.select = select
        self.commit = commit
        _browser = State(initialValue: TraktBrowserViewModel(services: services))
    }

    var body: some View {
        @Bindable var browser = browser
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                titleField
                sortSection
                QualitySelector(titles: TraktBrowserViewModel.Tab.allCases.map(\.rawValue), selection: Binding {
                    TraktBrowserViewModel.Tab.allCases.firstIndex(of: browser.tab) ?? 0
                } set: { browser.tab = TraktBrowserViewModel.Tab.allCases[$0] }, accessibilityID: "traktBrowser.tab")
                .padding(.horizontal, metrics.contentMargin)
                if browser.tab == .lists && browser.trimmedQuery.isEmpty { scopeChips }
                if let user = browser.browsedUser { userHeader(user) }
                results
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $browser.query, prompt: browser.tab == .lists ? "Search Trakt lists…" : "Search Trakt users…")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable { await browser.load(refresh: true) }
        .task(id: browser.request) {
            // A typed query waits for a pause; a tap on a tab or a chip loads at once.
            if !browser.trimmedQuery.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await browser.load()
        }
        .onChange(of: browser.tab) { browser.leaveUser() }
        .screenBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(actionTitle, action: commit)
                    .disabled(!canAdd)
                    .accessibilityIdentifier("widgetEditor.save")
            }
        }
        .accessibilityIdentifier("traktBrowser")
    }

    // MARK: Sections

    private var titleField: some View {
        TextField(titlePlaceholder.isEmpty ? "Widget title (optional)" : titlePlaceholder, text: $title)
            .submitLabel(.done)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 48)
            .glassCardSurface(cornerRadius: Theme.Radius.surface)
            .padding(.horizontal, metrics.contentMargin)
            .accessibilityIdentifier("widgetEditor.title")
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Sort")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, metrics.contentMargin)
            ChipRow {
                GlassChip("List Default", isSelected: sort == nil) { sort = nil }
                ForEach(TraktListSort.allCases) { option in
                    GlassChip(option.title, isSelected: sort == option) { sort = option }
                }
            }
            .accessibilityIdentifier("traktBrowser.sort")
        }
    }

    private var scopeChips: some View {
        ChipRow {
            ForEach(TraktBrowserViewModel.ListScope.allCases) { scope in
                GlassChip(scope.rawValue, isSelected: browser.scope == scope) { browser.scope = scope }
            }
        }
        .accessibilityIdentifier("traktBrowser.scope")
    }

    private func userHeader(_ user: TraktUserSummary) -> some View {
        Button {
            browser.leaveUser()
        } label: {
            Label("Lists by @\(user.username)", systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(GlassCapsuleButtonStyle())
        .padding(.horizontal, metrics.contentMargin)
        .accessibilityIdentifier("traktBrowser.userBack")
    }

    @ViewBuilder
    private var results: some View {
        switch browser.phase {
        case .idle:
            if browser.tab == .users {
                EmptyStateView("Find a Trakt user", systemImage: "person.2",
                               message: "Search by name to browse someone's public lists. Searching users needs your Trakt sign-in.")
                    .frame(minHeight: 260)
            }
        case .loading:
            VStack(spacing: Theme.Spacing.m) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous)
                        .fill(Theme.surface)
                        .frame(height: 112)
                }
            }
            .padding(.horizontal, metrics.contentMargin)
            .shimmering()
            .accessibilityLabel("Loading")
        case .needsSignIn(let message):
            EmptyStateView("Sign in to Trakt", systemImage: "person.crop.circle.badge.exclamationmark", message: message)
                .frame(minHeight: 260)
        case .failed(let message):
            InlineErrorView(message) { Task { await browser.load(refresh: true) } }
                .padding(.horizontal, metrics.contentMargin)
        case .loaded:
            if browser.isEmpty {
                EmptyStateView("Nothing here", systemImage: "list.bullet.rectangle", message: browser.emptyMessage)
                    .frame(minHeight: 260)
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        LazyVStack(spacing: Theme.Spacing.m) {
            if browser.showsUsers {
                ForEach(browser.users) { user in
                    Button {
                        Haptics.selection()
                        browser.browse(user: user)
                    } label: { TraktUserRow(user: user) }
                        .buttonStyle(.plain)
                        .onAppear { if user.id == browser.users.last?.id { Task { await browser.loadMore() } } }
                        .accessibilityIdentifier("traktBrowser.user.\(user.username)")
                }
            } else {
                ForEach(browser.lists) { list in
                    Button {
                        Haptics.selection()
                        select(list)
                    } label: { TraktListRow(list: list, isSelected: list.id == selectedID) }
                        .buttonStyle(.plain)
                        .onAppear { if list.id == browser.lists.last?.id { Task { await browser.loadMore() } } }
                        .accessibilityIdentifier("traktBrowser.list.\(list.slug)")
                }
            }
            if browser.isLoadingMore { ProgressView().padding(Theme.Spacing.l) }
        }
        .padding(.horizontal, metrics.contentMargin)
    }
}

/// A Trakt list as a large Liquid Glass row: icon, title, owner, counts and a two-line description.
struct TraktListRow: View {
    let list: TraktListSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: list.isPrivate ? "lock.rectangle.stack" : "list.bullet.rectangle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(list.name)
                    .font(.headline)
                    .lineLimit(2)
                Text("by @\(list.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.m) {
                    Label("\(list.itemCount)", systemImage: "film.stack")
                    Label("\(list.likes)", systemImage: "heart")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                if !list.description.isEmpty {
                    Text(TraktListRow.plain(list.description))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.Spacing.l)
        .glassCardSurface(cornerRadius: Theme.Radius.surface)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Trakt descriptions are Markdown; a row shows them as running text.
    static func plain(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "#", with: "")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}

private struct TraktUserRow: View {
    let user: TraktUserSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName ?? "@\(user.username)").font(.headline)
                if user.displayName != nil { Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if user.isVIP { Badge("VIP") }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.l)
        .frame(minHeight: 64)
        .glassCardSurface(cornerRadius: Theme.Radius.surface)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
#endif
