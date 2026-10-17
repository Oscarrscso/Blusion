#if canImport(UIKit)
import SwiftUI
import StremioKit

/// The title's information, each as a label and a value (see `TitleInformation`). Rows TMDb fills in appear once it answers.
struct DetailInformation: View {
    let model: DetailViewModel
    @Environment(PosterRatingsStore.self) private var ratings: PosterRatingsStore?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Information")
            ForEach(TitleInformation.rows(detail: model.detail, facts: model.titleFacts, certification: model.certification,
                                          averageRating: averageRating), id: \.label) { row in
                LabeledContent(row.label) { Text(row.value).foregroundStyle(.primary) }
                    .font(.footnote)
            }
        }
    }

    /// The average of the scores in the ratings row, out of 100 as every score in the app reads; nil (no line) with fewer than two.
    private var averageRating: String? {
        ratings?.ratings(for: model.detail.preview).averageScore.map { "\($0)/100" }
    }
}
#endif
