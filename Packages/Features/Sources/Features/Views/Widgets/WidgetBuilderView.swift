#if canImport(UIKit)
import StremioKit
import SwiftUI
import UIKit

/// The screen that makes a row, spotlight or banner, or changes a saved one. Its middle is a sentence that describes the widget, whose
/// words are its settings; the settings also sit in a strip of pills at the foot of the screen, and the open one has its editor in a
/// panel above that strip. `WidgetBuilderModel` holds the state and the logic; this view draws it and calls it.
struct WidgetBuilderView: View {
    let manager: WidgetsManagerViewModel
    let services: AppServices
    let mode: WidgetBuilderModel.Mode
    @State private var model: WidgetBuilderModel
    @State private var showsPicker = false
    @State private var showsTraktBrowser = false
    /// True while a text field in the open panel is being edited, so the pill strip gives way to the keyboard.
    @State private var isTyping = false
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    /// Makes a row, spotlight or banner when `widget` is nil (a TMDB list of popular movies), or changes `widget`.
    init(mode: WidgetBuilderModel.Mode, widget: HomeWidget?, manager: WidgetsManagerViewModel, services: AppServices) {
        self.mode = mode
        self.manager = manager
        self.services = services
        _model = State(initialValue: WidgetBuilderModel(mode: mode, widget: widget, manager: manager, services: services))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if model.needsTMDbToken { tokenNotice }
                SentenceCard(model: model)
                if mode == .edit { removeButton }
            }
            .padding(.horizontal, metrics.contentMargin)
            .padding(.vertical, Theme.Spacing.m)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .screenBackground()
        .navigationTitle(mode == .create ? "New Widget" : "Edit Widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(mode == .create ? "Add" : "Save", action: save)
                    .disabled(!model.canCommit)
                    .accessibilityIdentifier("widgetEditor.save")
            }
            // One Done key for every field of the open panel: the number pad has no return key of its own.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .navigationDestination(isPresented: $showsPicker) {
            WidgetSourcePicker(model: manager, openTraktLists: { showsTraktBrowser = true }, chooseTrakt: { source in
                model.setSource(source)
                showsPicker = false
            }) { choice, _ in
                model.setSource(.addonCatalog(choice.reference))
                showsPicker = false
            }
        }
        .navigationDestination(isPresented: $showsTraktBrowser) {
            TraktListBrowserView(services: services, navigationTitle: mode == .create ? "New Widget" : "Edit Widget",
                                 actionTitle: mode == .create ? "Add" : "Save", title: titleBinding, titlePlaceholder: model.autoTitle,
                                 sort: sortBinding, selectedID: selectedTraktID, canAdd: selectedTraktID != nil,
                                 select: { model.setSource(.traktList($0.reference(sort: model.traktSort))) }, commit: save)
        }
        .task { await model.load() }
    }

    // MARK: Bindings and state

    /// The title the user typed, or "" while it follows the source. Writing blank text makes it follow the source again.
    private var titleBinding: Binding<String> {
        Binding(get: { model.customTitle }, set: { model.setCustomTitle($0) })
    }

    private var sortBinding: Binding<TraktListSort?> {
        Binding(get: { model.traktSort }, set: { model.setTraktSort($0) })
    }

    /// The Trakt list the widget shows, by its Trakt id, so the browser can mark it.
    private var selectedTraktID: Int? {
        if case .traktList(let list) = model.row.source { return list.traktID }
        return nil
    }

    // MARK: Saving

    /// Adds the widget or saves the changes, then leaves the screen.
    private func save() {
        Task {
            await model.commit()
            dismiss()
        }
    }

    // MARK: Parts of the screen

    /// The notice that a TMDB list cannot be read until a TMDB token is saved in Settings.
    private var tokenNotice: some View {
        Text("TMDB lists need a TMDB Read Access Token. Add one in Settings › Review services, or choose another source.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }

    /// Takes the widget off Home and leaves the screen.
    private var removeButton: some View {
        Button("Remove Widget", role: .destructive) {
            Task {
                await model.removeWidget()
                dismiss()
            }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("widgetEditor.remove")
    }

    /// The open setting's panel above the pill strip. It is a safe-area inset, so it rises with the keyboard by itself.
    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let field = model.selectedField {
                WidgetFieldPanel(model: model, field: field, isTyping: $isTyping,
                                 openSourcePicker: { showsPicker = true }, openTraktLists: { showsTraktBrowser = true })
                    // A new identity per setting, so each panel starts with its own fields rather than the last setting's.
                    .id(model.selectedField)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !isTyping { PillStrip(model: model) }
        }
        .padding(.bottom, Theme.Spacing.s)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.25), value: model.selectedField)
    }
}

/// The sentence that describes the widget. Its words wrap like text; its tokens are the settings with a value, each a capsule that opens
/// the setting and, when it can be removed, has a cross that takes the value away. The kind is a dropdown.
private struct SentenceCard: View {
    let model: WidgetBuilderModel

    var body: some View {
        GlassEffectContainer(spacing: Theme.Spacing.s) {
            FlowLayout(spacing: 6) {
                ForEach(pieces) { piece in
                    pieceView(piece)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Not glass: the tokens inside are glass, and glass on glass does not read.
        .translucentPanelSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("widgetBuilder.sentence")
    }

    /// One drawn piece of the sentence: a word, the kind dropdown or a token. `trailing` is punctuation drawn glued to it.
    private struct Piece: Identifiable {
        enum Content {
            case word(String)
            case kind(TMDbDiscoverQuery.Kind)
            case token(WidgetBuilderModel.Token)
        }

        let id: String
        let content: Content
        var trailing: String? = nil
    }

    /// The sentence as drawn pieces: each word of the plain text on its own, and punctuation glued to the piece before it, so a line never
    /// starts with a comma or a full stop.
    private var pieces: [Piece] {
        var pieces: [Piece] = []
        for item in model.sentence {
            switch item.part {
            case .text(let text) where Self.isPunctuation(text):
                if let last = pieces.indices.last {
                    pieces[last].trailing = (pieces[last].trailing ?? "") + text
                } else {
                    pieces.append(Piece(id: "\(item.id)", content: .word(text)))
                }
            case .text(let text):
                for (index, word) in text.split(whereSeparator: \.isWhitespace).enumerated() {
                    pieces.append(Piece(id: "\(item.id).\(index)", content: .word(String(word))))
                }
            case .kind(let kind):
                pieces.append(Piece(id: "\(item.id)", content: .kind(kind)))
            case .token(let token):
                pieces.append(Piece(id: "\(item.id)", content: .token(token)))
            }
        }
        return pieces
    }

    /// True for text that is only punctuation, such as "," or ".".
    private static func isPunctuation(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isPunctuation)
    }

    @ViewBuilder
    private func pieceView(_ piece: Piece) -> some View {
        HStack(spacing: 0) {
            switch piece.content {
            case .word(let word):
                Text(word)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .kind(let kind):
                kindMenu(kind)
            case .token(let token):
                tokenView(token)
            }
            if let trailing = piece.trailing {
                Text(trailing)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A token: a capsule that opens its setting, with a cross beside it when the value can be taken away.
    private func tokenView(_ token: WidgetBuilderModel.Token) -> some View {
        HStack(spacing: 0) {
            Button { model.select(token.field) } label: {
                Text(token.text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            if token.isRemovable {
                Button { model.remove(token) } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(token.text)")
            }
        }
        .tokenCapsule()
        .overlay {
            if model.selectedField == token.field { Capsule().strokeBorder(.white, lineWidth: 1.5) }
        }
    }

    /// The movie-or-series choice: a capsule that opens a menu of the kinds, the current one checked.
    private func kindMenu(_ kind: TMDbDiscoverQuery.Kind) -> some View {
        Menu {
            ForEach(TMDbDiscoverQuery.Kind.allCases, id: \.self) { option in
                Button { model.setKind(option) } label: {
                    if option == kind {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(kind.noun)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .tokenCapsule()
        }
        .menuIndicator(.hidden)
    }
}

/// The settings strip: every setting as a pill, in two rows that scroll sideways. The open setting's pill is brought into view.
private struct PillStrip: View {
    let model: WidgetBuilderModel
    @Environment(\.layoutMetrics) private var metrics

    private static let rows = [GridItem(.fixed(PillButton.height), spacing: Theme.Spacing.s),
                               GridItem(.fixed(PillButton.height), spacing: Theme.Spacing.s)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Theme.Spacing.s) {
                    LazyHGrid(rows: Self.rows, spacing: Theme.Spacing.s) {
                        ForEach(model.pills) { pill in
                            PillButton(model: model, pill: pill)
                                .id(pill.field)
                        }
                    }
                }
                .padding(.horizontal, metrics.contentMargin)
            }
            .shelfIndicators()
            .scrollClipDisabled()
            .onChange(of: model.selectedField) { _, field in
                guard let field else { return }
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(field) }
            }
        }
    }
}

/// One setting in the strip: its icon, its name over its value, and a chevron that shows whether its editor is open. A pill that cannot
/// be used now is faded and does nothing.
private struct PillButton: View {
    let model: WidgetBuilderModel
    let pill: WidgetBuilderModel.Pill

    /// The height of every pill, so the strip's two rows line up.
    static let height: CGFloat = 52
    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        let isOpen = model.selectedField == pill.field
        Button {
            Haptics.tap()
            model.select(pill.field)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: pill.systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pill.title)
                        .font(.subheadline.weight(.bold))
                    Text(pill.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .leading)
                }
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Self.height)
            .glassEffect(.regular.interactive(), in: Self.shape)
            .overlay {
                if isOpen { Self.shape.strokeBorder(.white, lineWidth: 1.5) }
            }
            .opacity(pill.isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!pill.isEnabled)
        .pointerFeedback()
        .accessibilityLabel("\(pill.title), \(pill.value)")
        .accessibilityIdentifier("widgetBuilder.pill.\(pill.field.rawValue)")
    }
}

private extension View {
    /// The capsule a token and the kind dropdown sit in: interactive glass with the sentence's padding.
    func tokenCapsule() -> some View {
        padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}
#endif
