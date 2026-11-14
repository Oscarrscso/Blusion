#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The title's cast and crew, with photos from TMDb when it has them and the addon's plain names when it does not.
struct DetailCredits: View {
    let model: DetailViewModel
    let contentMargin: CGFloat
    /// The page's width, used to size the cast cards.
    let pageWidth: CGFloat
    @Environment(\.layoutMetrics) private var metrics
    /// Appearance's Cast & Crew visibility.
    @Environment(\.appAppearance) private var appearance

    var body: some View {
        Group {
            if !appearance.showsCast {
                EmptyView()
            } else if let group = model.shownCreditGroup, let people = model.shownCredits, !people.isEmpty {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    // TMDb's cast and crew, one part at a time, with photos. The heading is the part shown and the menu of the others.
                    // Smaller than the four-across layout and the shelf's usual cards.
                    let cardWidth = CastCardLayout.cardWidth(pageWidth: pageWidth, margin: contentMargin, spacing: metrics.cardSpacing,
                                                             maximum: metrics.posterWidth) * 0.8
                    // As wide as a card under it.
                    CreditGroupMenu(groups: model.creditGroups, shown: group, playColourHex: model.playColourHex, width: cardWidth) {
                        model.creditGroup = $0
                    }
                    .padding(.horizontal, contentMargin)
                    // Keyed on the width, so the row measures its height again when the cards change size (the phone turned). Each
                    // photo loads as its card scrolls on, behind the rest of the page. A part has a row of its own, so it starts at its
                    // first card.
                    ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing, resetKey: "\(Int(cardWidth))") {
                        ForEach(people) { PersonCardLink(person: $0, width: cardWidth).reportsShelfEdge(id: $0.id) }
                    }
                    .id(group)
                    .accessibilityIdentifier("detail.castCarousel")
                }
                .onChange(of: model.creditGroup) { _, _ in Haptics.play(.choices) }
            } else if model.isLoadingCredits {
                let width = CastCardLayout.cardWidth(pageWidth: pageWidth, margin: contentMargin,
                                                     spacing: metrics.cardSpacing, maximum: metrics.posterWidth) * 0.8
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    CreditGroupMenuSkeleton(width: width)
                        .padding(.horizontal, contentMargin)
                    ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing) {
                        ForEach(0..<6, id: \.self) { index in
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                Theme.placeholder
                                    .frame(width: width, height: width * 1.5)
                                    .mediaArtwork(cornerRadius: Theme.Radius.poster)
                                    .loadingCardSpinner()
                                VStack(alignment: .leading, spacing: 2) {
                                    DetailSkeletonLine(font: width < metrics.posterWidth ? .caption.weight(.semibold) : Theme.Typography.cardTitle,
                                                       width: width * 0.85)
                                    DetailSkeletonLine(font: width < metrics.posterWidth ? .caption2 : Theme.Typography.cardSubtitle,
                                                       width: width * 0.6)
                                }
                                .frame(width: width, alignment: .leading)
                            }
                            .reportsShelfEdge(id: index)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading cast and crew")
                .transition(.opacity)
            } else if !model.detail.cast.isEmpty {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    // Without TMDb (no read token, or it did not answer) the addon's names still show, as initials, and open nothing.
                    SectionHeader("Cast & Crew")
                        .padding(.horizontal, contentMargin)
                    ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing) {
                            ForEach(model.detail.cast, id: \.self) { name in
                                VStack(spacing: 8) {
                                    Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined())
                                        .appFont(style: .title2, weight: .medium, role: .display)
                                        .frame(width: metrics.avatarSize, height: metrics.avatarSize)
                                        .background(Theme.surfaceStrong, in: ScaledCapsule(scale: metrics.circularButtonScale(for: .actionButtons)))
                                    Text(name).appFont(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(width: metrics.avatarSize + 12)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(name)
                                .reportsShelfEdge(id: name)
                            }
                    }
                }
            }
        }
        .detailLoadingTransition(model.isLoadingCredits)
        .environment(\.showsArtworkLoadingSpinner, true)
    }
}

/// The compact coloured glass control for Cast and the other credit groups. Picking one shows its people.
private struct CreditGroupMenu: View {
    @Environment(\.layoutMetrics) private var metrics
    let groups: [TitleCreditGroup]
    let shown: TitleCreditGroup
    let playColourHex: String?
    /// The cast cards' width.
    let width: CGFloat
    let pick: (TitleCreditGroup) -> Void

    /// The control's height and corner radius, before Appearance's corners; its loading skeleton draws the same.
    static let height: CGFloat = 28
    static let cornerRadius: CGFloat = 14

    @ViewBuilder
    var body: some View {
        if groups.count > 1 {
            menu
        } else {
            // Keep the coloured glass when there is only one group; only the menu and its chevron are unnecessary.
            groupLabel
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var menu: some View {
        Menu {
            ForEach(groups) { group in
                Button {
                    // The part already shown stays as it is, without a tick.
                    if group != shown { pick(group) }
                } label: {
                    if group == shown { Label(group.title, systemImage: "checkmark") } else { Text(group.title) }
                }
            }
        } label: {
            groupLabel
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: Self.cornerRadius * metrics.circularButtonScale(for: .actionButtons)))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Still the section's heading, so the headings rotor finds it.
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Cast and Crew")
        .accessibilityValue(shown.title)
        .accessibilityHint("Shows another part of the cast and crew")
        .accessibilityIdentifier("detail.creditsMenu")
    }

    private var groupLabel: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius * metrics.circularButtonScale(for: .actionButtons), style: .continuous)
        return HStack(spacing: 4) {
            Text(shown.title)
                .appFont(.mediumStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if groups.count > 1 {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(width: width, height: Self.height)
        // The tint belongs to the glass inside the label, just like Sort and AI, so it travels with the system menu animation.
        .buttonSurface(.regular.interactive().tint((Theme.playControlColour(hex: playColourHex) ?? .clear)), in: shape)
        .animation(Theme.Motion.standard, value: playColourHex)
        .contentShape(shape)
        .contentShape(.contextMenuPreview, shape)
        .clipShape(shape)
        .glassHover(shape)
    }
}

/// The Cast control while the credits load: the control's own width, height and corners, with a bar centred where its name will be.
private struct CreditGroupMenuSkeleton: View {
    @Environment(\.layoutMetrics) private var metrics
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: CreditGroupMenu.cornerRadius * metrics.circularButtonScale(for: .actionButtons), style: .continuous)
            .fill(Theme.placeholder)
            .frame(width: width, height: CreditGroupMenu.height)
            .overlay {
                DetailSkeletonLine(font: Theme.Typography.mediumStrong, width: min(48, max(0, width - 16)))
            }
            .accessibilityHidden(true)
    }
}
#endif
