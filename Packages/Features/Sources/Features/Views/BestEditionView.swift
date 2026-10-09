#if canImport(UIKit)
import StremioKit
import SwiftUI

/// Best Blurays' recommendation, shown beside the stream results after Play. Folded into one row, with the release named on it, so
/// it reads as a single line until someone opens it.
struct BestEditionView: View {
    let model: StreamPickerViewModel
    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.canFindBestEdition {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "opticaldisc")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Best Blu-ray")
                            .font(.subheadline.weight(.semibold))
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(summaryColor)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Spacing.s)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("streams.bestEdition")
                if isExpanded {
                    content
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.bottom, Theme.Spacing.m)
                        .padding(.top, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .glassCardSurface()
        }
    }

    /// The one line the row shows while it is folded: the release it names, or where the lookup stands.
    private var summary: String {
        switch model.bestEdition {
        case .idle, .loading: "Checking…"
        case .found(let edition): edition.release
        case .listedWithoutEdition: "No best release named yet"
        case .notListed: "No page yet"
        case .failed: "Couldn’t load · tap to retry"
        }
    }

    private var summaryColor: Color {
        if case .failed = model.bestEdition { return .orange }
        return .secondary
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
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
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
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
