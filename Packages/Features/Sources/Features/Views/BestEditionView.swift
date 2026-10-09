#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Best Blurays' recommendation, shown beside the stream results after Play.
struct BestEditionView: View {
    let model: StreamPickerViewModel
    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        if model.canFindBestEdition {
            DisclosureGroup(isExpanded: $isExpanded) {
                content.padding(.top, Theme.Spacing.s)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Best Blu-ray edition", systemImage: "opticaldisc")
                        .font(.subheadline.weight(.semibold))
                    if case .found(let edition) = model.bestEdition {
                        Text(edition.release).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if case .loading = model.bestEdition {
                        Text("Checking Best Blurays…").font(.caption).foregroundStyle(.secondary)
                    } else if case .failed = model.bestEdition {
                        Text("Couldn’t load edition · Tap to retry").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .tint(.secondary)
            .padding(Theme.Spacing.m)
            .glassCardSurface()
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
            .accessibilityIdentifier("streams.bestEdition")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.bestEdition {
        case .idle, .loading:
            HStack(spacing: Theme.Spacing.m) {
                ProgressView()
                Text("Checking Best Blurays for \(model.request.title)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bestEdition.loading")
        case .found(let edition):
            found(edition)
        case .listedWithoutEdition(let title, let url):
            message("Best Blurays lists \(title), but has not named a best release for it yet.", link: url, linkTitle: "Open the page")
        case .notListed(let searchURL):
            message("Best Blurays has no page for \(model.request.title) yet.", link: searchURL, linkTitle: "Search Best Blurays")
        case .failed(let text):
            InlineErrorView(text) { Task { await model.findBestEdition() } }
                .accessibilityIdentifier("bestEdition.failed")
        }
    }

    private func found(_ edition: BestBlurayEdition) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(edition.heading)
                .font(Theme.Typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(edition.release)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("bestEdition.release")
            HStack(spacing: Theme.Spacing.s) {
                if edition.is4K { Badge("4K", style: .quality) }
                if let tier = edition.uhdTier { Badge("\(tier) 4K tier") }
                if let updated = edition.updated {
                    Text(updated).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let notes = edition.videoNotes {
                labelled("Video notes", notes)
            }
            if let upcoming = edition.upcoming {
                labelled("Coming", upcoming)
            }
            Button { openURL(edition.pageURL) } label: {
                Label("Open on Best Blurays", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.glassCapsule)
            .padding(.top, Theme.Spacing.xs)
            .accessibilityIdentifier("bestEdition.open")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func message(_ text: String, link: URL, linkTitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button { openURL(link) } label: {
                Label(linkTitle, systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.glassCapsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("bestEdition.message")
    }
}
#endif
