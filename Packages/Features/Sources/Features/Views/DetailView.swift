#if canImport(SwiftUI)
import SwiftUI
import StremioKit

struct DetailView: View {
    @State private var model: DetailViewModel

    init(preview: MetaPreview, services: AppServices) {
        _model = State(initialValue: DetailViewModel(preview: preview, services: services))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.isFallback && !model.isLoading {
                    Label("Only basic details are available for this title.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("detail.fallbackNote")
                }
                playSection
                libraryButtons
                if let description = model.detail.preview.description {
                    Text(description).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                facts
            }
            .padding()
        }
        .navigationTitle(model.detail.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onAppear { Task { await model.refreshUserState() } }
        .accessibilityIdentifier("detail.scroll")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(url: model.detail.preview.poster, title: model.detail.name)
                .frame(maxWidth: 140)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.detail.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.title")
                if !model.subtitle.isEmpty {
                    Text(model.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                if !model.detail.preview.genres.isEmpty {
                    Text(model.detail.preview.genres.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                }
                if model.isLoading { ProgressView() }
            }
        }
    }

    @ViewBuilder
    private var playSection: some View {
        if model.isSeries {
            seriesSection
        } else {
            NavigationLink(value: model.movieRequest) {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("detail.playButton")
        }
    }

    private var libraryButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.toggleLibrary() }
            } label: {
                Label(model.isInLibrary ? "Saved" : "Save to Library", systemImage: model.isInLibrary ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("detail.libraryButton")
            .accessibilityValue(model.isInLibrary ? "Saved" : "Not saved")
            if !model.isSeries {
                let request = model.movieRequest
                let watched = model.isWatched(request)
                Button {
                    Task { await model.setWatched(!watched, for: request) }
                } label: {
                    Label(watched ? "Watched" : "Mark Watched", systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("detail.watchedButton")
                .accessibilityValue(watched ? "Watched" : "Not watched")
            }
        }
    }

    @ViewBuilder
    private var seriesSection: some View {
        if model.seasons.count > 1 {
            Picker("Season", selection: Binding(get: { model.selectedSeason ?? model.seasons[0] }, set: { model.selectedSeason = $0 })) {
                ForEach(model.seasons, id: \.self) { Text($0 == 0 ? "Specials" : "Season \($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("detail.seasonPicker")
        }
        ForEach(model.episodes) { video in
            NavigationLink(value: model.request(for: video)) {
                HStack {
                    Text("\(video.episode.map(String.init) ?? "•")").font(.headline).frame(minWidth: 28)
                    Text(video.title).multilineTextAlignment(.leading)
                    Spacer()
                    if let rating = video.ratingText {
                        Label(rating, systemImage: "star.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("IMDb rating \(rating) out of 10")
                    }
                    if model.isWatched(model.request(for: video)) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Watched")
                    }
                    Image(systemName: "play.circle")
                }
            }
            .contextMenu {
                let request = model.request(for: video)
                let watched = model.isWatched(request)
                Button(watched ? "Mark as not watched" : "Mark as watched", systemImage: watched ? "xmark.circle" : "checkmark.circle") {
                    Task { await model.setWatched(!watched, for: request) }
                }
            }
            .accessibilityIdentifier("detail.episode.\(video.id)")
        }
    }

    @ViewBuilder
    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            fact("Director", model.detail.director)
            fact("Cast", model.detail.cast)
            fact("Writers", model.detail.writers)
        }
    }

    @ViewBuilder
    private func fact(_ title: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(values.joined(separator: ", ")).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
