#if canImport(UIKit)
import SwiftUI
import StremioKit

/// The title's information: its release, runtime, genres, director and writers, and the average of its ratings, each as a label and a
/// value. Blank rows are left out.
struct DetailInformation: View {
    let model: DetailViewModel
    @Environment(PosterRatingsStore.self) private var ratings: PosterRatingsStore?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Information")
            information("Released", model.detail.preview.releaseInfo)
            information("Runtime", model.detail.preview.runtime)
            information("Genres", model.detail.preview.genres.joined(separator: ", "))
            information("Director", model.detail.director.joined(separator: ", "))
            information("Writers", model.detail.writers.joined(separator: ", "))
            information("Average rating", averageRating)
        }
    }

    /// The average of the scores in the ratings row, out of 100 as every score in the app reads; nil (no line) with fewer than two.
    private var averageRating: String? {
        ratings?.ratings(for: model.detail.preview).averageScore.map { "\($0)/100" }
    }

    @ViewBuilder
    private func information(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) { Text(value).foregroundStyle(.primary) }
                .font(.footnote)
        }
    }
}
#endif
