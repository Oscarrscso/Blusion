#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// A cast or crew member's page: the portrait and biography, what they are known for, then every credit, newest first, with
/// filters for the kind of title and the role. Credits are laid out a page at a time as the list scrolls.
struct PersonView: View {
    @State private var model: PersonViewModel
    @State private var isBiographyExpanded = false
    @Environment(\.layoutMetrics) private var metrics

    init(destination: PersonDestination, services: AppServices) {
        _model = State(initialValue: PersonViewModel(destination: destination, services: services))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, metrics.pageMargin)
                if !model.photoStrip.isEmpty {
                    photos.padding(.top, Theme.Spacing.xxl).reportsSectionEdge(id: "photos")
                }
                if !model.knownFor.isEmpty {
                    knownFor.padding(.top, Theme.Spacing.xxl).reportsSectionEdge(id: "knownFor")
                }
                credits
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, Theme.Spacing.xxl)
                    .reportsSectionEdge(id: "credits")
            }
            .scrollTargetLayout()
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .verticalScrollFeel()
        .screenBackground()
        .navigationTitle(model.destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .accessibilityIdentifier("person.scroll")
    }

    // MARK: - Header

    private var name: String { model.person?.name ?? model.destination.name }

    /// The portrait while it loads is the one the card already showed, so the page never opens on an empty frame.
    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(name)
                    .font(Theme.Typography.heroTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("person.name")
                if let line = summaryLine {
                    Text(line).font(Theme.Typography.metaLine).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            if let biography = model.person?.biography {
                biographyText(biography)
            }
            if let reason = model.unavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("person.unavailable")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.l)
    }

    /// "Directing · 42 credits". Parts that are not known yet are left out.
    private var summaryLine: String? {
        var parts: [String] = []
        if let department = model.person?.department { parts.append(department) }
        if !model.credits.isEmpty { parts.append("\(model.credits.count) credits") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func biographyText(_ biography: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(biography)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(isBiographyExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
            // Four lines of body text hold about 150 characters at phone width, so anything longer may be cut off.
            if biography.count > 150 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { isBiographyExpanded.toggle() }
                } label: {
                    Text(isBiographyExpanded ? "Less" : "More").font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: metrics.readableWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Photos

    /// Every profile photo TMDb has for the person, best voted first, as a strip of portraits.
    private var photos: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("Photos")
                .padding(.horizontal, metrics.pageMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                    ForEach(model.photoStrip, id: \.self) { url in
                        ArtworkImage(url: url, title: "", maxPixelSize: 360, contentMode: .fill)
                            .frame(width: metrics.posterWidth, height: metrics.posterWidth * 1.5)
                            .mediaArtwork(cornerRadius: Theme.Radius.poster)
                            .reportsShelfEdge(id: url)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
            .scrollClipDisabled()
            .softSnappingScroll(loosened: true)
            .accessibilityIdentifier("person.photos")
        }
    }

    // MARK: - Known For

    /// The titles to remember them by, as wide cards with their backdrops.
    private var knownFor: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("Known For")
                .padding(.horizontal, metrics.pageMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: metrics.cardSpacing) {
                    ForEach(model.knownFor) { credit in
                        NavigationLink(value: credit.titleDestination) {
                            MediaCard(item: credit.preview, aspect: .wide, showsRating: false, subtitle: credit.roleText)
                        }
                        .buttonStyle(PressableCardStyle())
                        .titleTapHaptic()
                        .reportsShelfEdge(id: credit.id)
                        .accessibilityIdentifier("person.knownFor.\(credit.id)")
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, metrics.pageMargin, for: .scrollContent)
            .scrollClipDisabled()
            .softSnappingScroll(loosened: true)
        }
    }

    // MARK: - Credits

    private var credits: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            SectionHeader("Credits")
            filters
            if model.isLoading && model.credits.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.l)
            } else if model.sections.isEmpty {
                Text(model.credits.isEmpty ? "No credits yet." : "No credits match these filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.Spacing.s)
                    .accessibilityIdentifier("person.noCredits")
            }
            // A lazy stack builds a card only when it is about to scroll on screen, so artwork is requested for what is visible.
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text(section.year.map(String.init) ?? "Unknown Date")
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("person.year.\(section.id)")
                        ForEach(section.credits) { credit in
                            CreditRow(credit: credit, isUnreleased: model.isUnreleased(credit))
                        }
                    }
                }
                if model.hasMoreCredits {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.m)
                        .onAppear { model.loadMore() }
                }
            }
        }
    }

    /// Two compact menus side by side: the kind of title, and the role. Each shows what it is set to.
    private var filters: some View {
        HStack(spacing: Theme.Spacing.s) {
            Menu {
                Picker("Titles", selection: $model.mediaFilter) {
                    ForEach(PersonMediaFilter.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                FilterMenuLabel(model.mediaFilter.title, systemImage: "film", isActive: model.mediaFilter != .all)
            }
            .accessibilityIdentifier("person.mediaFilter")
            Menu {
                Picker("Roles", selection: $model.roleFilter) {
                    Text("All Roles").tag(CreditCategory?.none)
                    ForEach(model.availableRoles, id: \.self) { Text($0.title).tag(CreditCategory?.some($0)) }
                }
            } label: {
                FilterMenuLabel(model.roleFilter?.title ?? "All Roles", systemImage: "person.text.rectangle", isActive: model.roleFilter != nil)
            }
            .accessibilityIdentifier("person.roleFilter")
        }
    }
}

// MARK: - Pieces

/// One credit as a row in the filmography: a poster, the title and kind, the role, and the rating when TMDb has one.
private struct CreditRow: View {
    let credit: TMDbPersonCredit
    let isUnreleased: Bool
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        NavigationLink(value: credit.titleDestination) {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                ArtworkImage(url: credit.poster, title: credit.title, maxPixelSize: 240, contentMode: .fill)
                    .frame(width: 60, height: 90)
                    .mediaArtwork(cornerRadius: Theme.Radius.poster)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(credit.title.isEmpty ? "Untitled" : credit.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(kindLine)
                        .font(Theme.Typography.cardSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(credit.roleText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardSurface()
        }
        .buttonStyle(PressableCardStyle())
        .titleTapHaptic()
        .accessibilityIdentifier("person.credit.\(credit.id)")
    }

    /// "Movie", or "TV Show · 10 episodes" when TMDb counts them.
    private var kindLine: String {
        guard !credit.isMovie else { return "Movie" }
        guard let episodes = credit.episodeCount, episodes > 0 else { return "TV Show" }
        return "TV Show · \(episodes) episodes"
    }

    /// The rating, or an "Unreleased" mark for a title that is not out yet. A title with neither shows nothing here.
    @ViewBuilder
    private var footer: some View {
        if isUnreleased {
            Badge("Unreleased", style: .neutral)
        } else if let average = credit.voteAverage {
            Label(average.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// A cast or crew member as a card: a portrait with rounded corners, then the name and the role. Tapping opens their page.
struct PersonCardLink: View {
    let person: TMDbTitlePerson
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let width = metrics.posterWidth
        NavigationLink(value: PersonDestination(id: person.id, name: person.name, profile: person.profile)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ArtworkImage(url: person.profile, title: person.name, maxPixelSize: 360, contentMode: .fill)
                    .frame(width: width, height: width * 1.5)
                    .mediaArtwork(cornerRadius: Theme.Radius.poster)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(person.roleText ?? (person.isCast ? "Actor" : "Crew"))
                        .font(Theme.Typography.cardSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(PressableCardStyle())
        .titleTapHaptic()
        .help(person.name)
        .accessibilityIdentifier("cast.\(person.id)")
    }
}
#endif
