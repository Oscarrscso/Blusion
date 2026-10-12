#if canImport(UIKit)
import SwiftUI
import StremioKit
import UIKit

/// The title's metadata line, its main action with the round actions beside it, and the note when only basic details are known. Beneath
/// the logo in portrait, beside the artwork in landscape.
struct DetailActions: View {
    let model: DetailViewModel
    @Binding var isConfirmingUnmarkShow: Bool
    /// False leaves only the metadata line, while the page shows its streams in place of the actions.
    var showsActions = true
    /// True while the streams Play asked for are on their way: Play shows a spinner in place of its label, as the trailer button does.
    var isLoadingStreams = false
    /// The main action's tap: the page shows this title's streams.
    let play: (StreamRequest) -> Void
    @Environment(\.isLandscape) private var isLandscape
    @Environment(TitleActions.self) private var titleActions

    var body: some View {
        VStack(alignment: isLandscape ? .leading : .center, spacing: Theme.Spacing.s) {
            MetaLine(metaParts, identifier: "detail.metaLine", spreads: true)
                .multilineTextAlignment(isLandscape ? .leading : .center)
            if showsActions {
                VStack(alignment: isLandscape ? .leading : .center, spacing: Theme.Spacing.s) {
                    actionRow
                    if model.isFallback && !model.isLoading {
                        Label("Only basic details are available for this title.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("detail.fallbackNote")
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// The metadata line, the same text as the spotlight's. It sits above the actions.
    private var metaParts: [String?] { model.heroMetaLine }

    /// The one main action. A movie plays itself; a series plays its next episode. While its streams load it shows a spinner, and a
    /// tap then calls them off. While a series' episodes are still arriving, a placeholder holds the place.
    @ViewBuilder
    private var primaryAction: some View {
        if let request = model.primaryRequest {
            Button {
                play(request)
            } label: {
                // The label keeps its place under the spinner, so the button keeps its size.
                Label(model.primaryActionTitle, systemImage: "play.fill")
                    .opacity(isLoadingStreams ? 0 : 1)
                    .overlay {
                        if isLoadingStreams {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white.opacity(0.6))
                                .transition(.opacity)
                        }
                    }
                    .animation(.smooth(duration: 0.25), value: isLoadingStreams)
            }
            .buttonStyle(.primaryAction)
            .accessibilityLabel(isLoadingStreams ? "\(model.primaryActionTitle), loading" : model.primaryActionTitle)
            .accessibilityIdentifier("detail.playButton")
        } else if model.isLoading {
            Capsule()
                .fill(Theme.surfaceStrong)
                .frame(height: CircleActionButton.diameter)
                .shimmering()
                .accessibilityHidden(true)
        }
    }

    /// Play fills the remaining width beside the circle actions, on one line. The label shrinks before the row ever stacks, so a long
    /// "Resume S3 · E12" stays beside Save, Watched and Trailer.
    @ViewBuilder
    private var actionRow: some View {
        #if !targetEnvironment(macCatalyst)
        if isLandscape {
            GlassEffectContainer(spacing: TitleHero.actionGap / 2) {
                HStack(alignment: .center, spacing: TitleHero.actionGap) {
                    primaryAction
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: TitleHero.actionGap) {
                        saveAction
                        watchedAction
                        trailerAction
                    }
                    .fixedSize()
                    .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            portraitActionRow
        }
        #else
        portraitActionRow
        #endif
    }

    private var portraitActionRow: some View {
        HStack(alignment: .center, spacing: TitleHero.actionGap) {
            primaryAction
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            secondaryActions
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: isLandscape ? .leading : .center)
    }

    private var secondaryActions: some View {
        GlassEffectContainer(spacing: TitleHero.actionGap) {
            HStack(spacing: TitleHero.actionGap) {
                saveAction
                watchedAction
                trailerAction
            }
        }
        .fixedSize()
    }

    private var saveAction: some View {
        CircleActionButton(title: "Save", systemImage: "bookmark", isOn: model.isInLibrary, onTitle: "Saved", onSystemImage: "bookmark.fill") {
            Task {
                await model.toggleLibrary()
                await titleActions.refresh()
            }
        }
        .accessibilityValue(model.isInLibrary ? "Saved" : "Not saved")
        .accessibilityIdentifier("detail.libraryButton")
    }

    /// A movie is marked on its own. A show is marked as a whole: every episode that has aired. Clearing a whole show asks first,
    /// because it removes the mark from every episode at once.
    @ViewBuilder
    private var watchedAction: some View {
        if model.isSeries {
            let watched = model.isSeriesWatched
            CircleActionButton(title: "Watched", systemImage: "eye", isOn: watched) {
                if watched {
                    isConfirmingUnmarkShow = true
                } else {
                    Task {
                        await model.setSeriesWatched(true)
                        await titleActions.refresh()
                    }
                }
            }
            .disabled(model.detail.videos.isEmpty)
            .opacity(model.detail.videos.isEmpty ? 0.4 : 1)
            .accessibilityValue(watched ? "Every episode watched" : "Not watched")
            .accessibilityHint(watched ? "Clears the watched mark from every episode" : "Marks every episode that has aired as watched")
            .accessibilityIdentifier("detail.watchedButton")
            .confirmationDialog("Mark every episode as not watched?", isPresented: $isConfirmingUnmarkShow, titleVisibility: .visible) {
                Button("Mark Show as Not Watched", role: .destructive) {
                    Task {
                        await model.setSeriesWatched(false)
                        await titleActions.refresh()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            let request = model.movieRequest
            let watched = model.isWatched(request)
            CircleActionButton(title: "Watched", systemImage: "eye", isOn: watched) {
                Task {
                    await model.setWatched(!watched, for: request)
                    await titleActions.refresh()
                }
            }
            .accessibilityValue(watched ? "Watched" : "Not watched")
            .accessibilityIdentifier("detail.watchedButton")
        }
    }

    /// Loads the title's trailer into the page and plays it there, with a spinner while it loads. While it plays the symbol is filled,
    /// and a tap closes the player. A YouTube trailer opens in the YouTube app instead. It is there from the start, so the row does not
    /// change when the page loads; when no trailer can be had it is dimmed and does nothing.
    private var trailerAction: some View {
        CircleActionButton(title: "Trailer", systemImage: "play.rectangle", isOn: model.trailer.isPlaying, onTitle: "Close Trailer",
                           action: { model.toggleTrailer() }, isLoading: model.trailer.phase == .loading)
        .disabled(!model.canPlayTrailer)
        .opacity(model.canPlayTrailer ? 1 : 0.4)
        .accessibilityIdentifier("detail.trailerButton")
    }
}
#endif
