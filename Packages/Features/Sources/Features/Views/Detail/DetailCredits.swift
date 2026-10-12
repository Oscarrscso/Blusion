#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The title's cast and crew, with photos from TMDb when it has them and the addon's plain names when it does not. On iPhone the information
/// block follows them; on Mac it sits at the top of the page instead.
struct DetailCredits: View {
    let model: DetailViewModel
    let contentMargin: CGFloat
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.titleSectionSpacing) {
            if let people = model.castAndCrew, !people.isEmpty {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    // TMDb's cast and key crew, with photos. Each photo loads as its card scrolls on, behind the rest of the page.
                    SectionHeader("Cast & Crew")
                        .padding(.horizontal, contentMargin)
                    ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing) {
                        ForEach(people) { PersonCardLink(person: $0).reportsShelfEdge(id: $0.id) }
                    }
                    .accessibilityIdentifier("detail.castCarousel")
                }
            } else if !model.detail.cast.isEmpty {
                VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                    // Without TMDb (no read token, or it did not answer) the addon's names still show, as initials, and open nothing.
                    SectionHeader("Cast & Crew")
                        .padding(.horizontal, contentMargin)
                    ShelfScroll(margin: contentMargin, spacing: metrics.cardSpacing) {
                            ForEach(model.detail.cast, id: \.self) { name in
                                VStack(spacing: 8) {
                                    Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined())
                                        .font(.title2.weight(.medium))
                                        .frame(width: metrics.avatarSize, height: metrics.avatarSize)
                                        .background(Theme.surfaceStrong, in: Circle())
                                    Text(name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(width: metrics.avatarSize + 12)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(name)
                                .reportsShelfEdge(id: name)
                            }
                    }
                }
            }
            #if !targetEnvironment(macCatalyst)
            // The Mac page shows its information beside the synopsis, at the top of the page (see DesktopDetailHero).
            DetailInformation(model: model)
                .frame(maxWidth: metrics.readableWidth, alignment: .leading)
                .padding(.horizontal, contentMargin)
            #endif
        }
    }
}
#endif
