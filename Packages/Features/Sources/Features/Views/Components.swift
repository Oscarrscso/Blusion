#if canImport(SwiftUI)
import SwiftUI
import StremioKit

/// A capsule that names a failing addon without hiding the rest of the screen.
struct ErrorChip: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .accessibilityElement(children: .combine)
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

struct PosterImage: View {
    let url: URL?
    let title: String

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Text(title)
            .font(.caption)
            .multilineTextAlignment(.center)
            .padding(6)
            .foregroundStyle(.secondary)
    }
}

struct PosterCard: View {
    let item: MetaPreview
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: item.poster, title: item.name)
            Text(item.name)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if let year = item.releaseInfo {
                Text(year).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.name, item.releaseInfo].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("poster.\(item.id)")
    }
}

/// Poster that opens Detail.
struct PosterLink: View {
    let item: MetaPreview

    var body: some View {
        NavigationLink(value: item) { PosterCard(item: item) }
            .buttonStyle(.plain)
    }
}

struct PosterGrid: View {
    let items: [MetaPreview]
    var onLastAppear: (() -> Void)?

    @ScaledMetric(relativeTo: .body) private var minimum: CGFloat = 110

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: minimum * 1.4), spacing: 12, alignment: .top)], alignment: .leading, spacing: 16) {
            ForEach(items) { item in
                PosterLink(item: item)
                    .onAppear { if item.id == items.last?.id { onLastAppear?() } }
            }
        }
        .padding(.horizontal)
    }
}

struct EmptyAddonsView: View {
    let onOpenAddons: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No addons yet", systemImage: "puzzlepiece.extension")
        } description: {
            Text("Blusion works with Stremio addons but doesn't include any. Paste an addon's link (it starts with https:// or stremio://) on the Addons tab to get catalogs and streams.")
        } actions: {
            Button("Add an addon", action: onOpenAddons)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("empty.addAddon")
        }
        .accessibilityIdentifier("empty.noAddons")
    }
}

/// Where each kind of value in a stack leads. Every tab's stack uses the same set.
struct AppDestinations: ViewModifier {
    let services: AppServices

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: MetaPreview.self) { DetailView(preview: $0, services: services) }
    }
}

extension View {
    func appDestinations(services: AppServices) -> some View {
        modifier(AppDestinations(services: services))
    }
}
#endif
