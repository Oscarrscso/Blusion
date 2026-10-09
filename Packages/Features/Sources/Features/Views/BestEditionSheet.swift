#if canImport(UIKit)
import StremioKit
import SwiftUI

/// What bestblurays.com names as the best edition of a film, looked up when the sheet opens: the release in large type, what makes it
/// the pick, its notes and 4K tier, and a link to the page for the full comparison. The answer is kept by the title page's model, so
/// reopening the sheet is instant.
struct BestEditionSheet: View {
    let model: DetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    content
                    Text("From Best Blurays, a guide to film releases that its community keeps up to date. The page has the full comparison.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .screenBackground()
            .navigationTitle("Best Blu-ray edition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("bestEdition.close")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .task { await model.findBestEdition() }
        .accessibilityIdentifier("bestEdition.sheet")
    }

    @ViewBuilder
    private var content: some View {
        switch model.bestEdition {
        case .idle, .loading:
            HStack(spacing: Theme.Spacing.m) {
                ProgressView()
                Text("Checking Best Blurays for \(model.detail.name)…")
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
            message("Best Blurays has no page for \(model.detail.name) yet.", link: searchURL, linkTitle: "Search Best Blurays")
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
                .font(.title2.bold())
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
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityIdentifier("bestEdition.message")
    }
}
#endif
