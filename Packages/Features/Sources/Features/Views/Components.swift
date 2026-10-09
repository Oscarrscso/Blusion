#if canImport(UIKit)
import SwiftUI
import StremioKit

/// A capsule that names a failing addon without hiding the rest of the screen. The failure is said by the icon and the text,
/// not by a coloured block.
struct ErrorChip: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surfaceStrong, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Shown instead of a wall of per-addon errors when every request failed because the device is offline.
struct OfflineBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "wifi.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Connectivity.offlineTitle)
                    .font(.headline)
                Text(Connectivity.offlineMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.l)
        .cardSurface()
        .padding(.horizontal, Theme.screenPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline.banner")
    }
}

/// Wraps its children onto several lines instead of clipping them (chips at large Dynamic Type sizes).
struct WrappingStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        // A vertical stack of chips keeps layout trivial and never clips at accessibility sizes.
        VStack(alignment: .leading, spacing: 8, content: content)
    }
}

/// Poster artwork: 2:3 with poster corners. Give it a width (`.frame(width:)`) and the height follows.
struct PosterImage: View {
    let url: URL?
    let title: String

    var body: some View {
        ArtworkImage(url: url, title: title, maxPixelSize: 480)
            .aspectRatio(CardAspect.poster.ratio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A poster with its name and year, sized as a medium poster `MediaCard`.
struct PosterCard: View {
    let item: MetaPreview

    var body: some View {
        MediaCard(item: item)
    }
}

/// Poster that opens Detail.
struct PosterLink: View {
    let item: MetaPreview

    var body: some View {
        MediaCardLink(item: item)
    }
}

struct PosterGrid: View {
    let items: [MetaPreview]
    var onLastAppear: (() -> Void)?

    var body: some View {
        MediaGrid(items: items, aspect: .poster, onLastAppear: onLastAppear)
    }
}

/// The first-run state: no addon is installed, so there is nothing to browse yet.
struct EmptyAddonsView: View {
    let onOpenAddons: () -> Void

    var body: some View {
        EmptyStateLayout(
            title: "No addons yet",
            systemImage: "puzzlepiece.extension",
            message: "Addons bring the catalogs, search and streams. "
                + "Paste an addon's link (it starts with https:// or stremio://) in Settings."
        ) {
            Button("Add an addon", action: onOpenAddons)
                .buttonStyle(.primaryActionCompact)
                .padding(.top, Theme.Spacing.s)
                .accessibilityIdentifier("empty.addAddon")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty.noAddons")
    }
}

/// Where each kind of value in a stack leads. Every tab's stack uses the same set.
struct AppDestinations: ViewModifier {
    let services: AppServices
    @Environment(\.zoomNamespace) private var zoomNamespace

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: MetaPreview.self) { DetailView(preview: $0, services: services) }
            .navigationDestination(for: TitleDestination.self) { destination in
                DetailView(preview: destination.preview, services: services)
                    .zoomDestination(id: destination.sourceID, in: zoomNamespace)
            }
            .navigationDestination(for: StreamRequest.self) { StreamPickerView(request: $0, services: services) }
            .navigationDestination(for: CatalogListRequest.self) { CatalogListView(request: $0, services: services) }
    }
}

extension View {
    func appDestinations(services: AppServices) -> some View {
        modifier(AppDestinations(services: services))
    }
}
#endif
