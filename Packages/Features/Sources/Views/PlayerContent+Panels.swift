#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI

extension PlayerContent {
    /// The episodes, in a glass panel like the options menu, hanging from the Episodes button at the top trailing corner. It sits under
    /// the top bar and takes the height down to the screen's bottom margin, with the transport and timeline hidden behind it.
    var episodePanel: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                if showsEpisodes && model.failureMessage == nil {
                    PlayerEpisodePicker(current: model.plan.request, services: services,
                                        prepare: { await model.prepareEpisode($0) }, onPlay: playChosenEpisode,
                                        onClose: closeEpisodes)
                        .frame(width: min(Self.episodePanelWidth, max(0, proxy.size.width - 40)))
                        .frame(maxHeight: min(Self.episodePanelHeight, max(0, proxy.size.height - Self.episodePanelTop - 12)))
                        .padding(.top, Self.episodePanelTop)
                        .padding(.trailing, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
                }
            }
            #if targetEnvironment(macCatalyst)
            // The controls are at most 900 wide on Mac, so the panel lines up with their trailing edge.
            .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topTrailing)
            #endif
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
        .animation(.snappy(duration: 0.24), value: showsEpisodes)
    }

    var streamPanel: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                if showsStreams && model.failureMessage == nil {
                    PlayerStreamPicker(candidates: model.plan.candidates, currentIndex: model.currentStreamIndex,
                                       onSelect: { index in
                                           closeMenus()
                                           Task { await model.selectStream(at: index) }
                                       }, onClose: closeMenus)
                        .frame(width: min(Self.episodePanelWidth, max(0, proxy.size.width - 40)))
                        .frame(height: min(Self.episodePanelHeight, max(0, proxy.size.height - Self.episodePanelTop - 12)))
                        .padding(.top, Self.episodePanelTop)
                        .padding(.trailing, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
                }
            }
            #if targetEnvironment(macCatalyst)
            .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topTrailing)
            #endif
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
        .animation(.snappy(duration: 0.24), value: showsStreams)
    }

    private static let episodePanelWidth: CGFloat = 360

    private static let episodePanelHeight: CGFloat = 560

    /// Below the top bar: its 12 pt margin, the 44 pt buttons and a small gap.
    private static let episodePanelTop: CGFloat = 12 + 44 + 8

    func toggleEpisodes() {
        guard !model.plan.isOffline else { return }
        if showsEpisodes {
            closeEpisodes()
        } else {
            popOut = .episodes
        }
    }

    func closeEpisodes() {
        guard showsEpisodes else { return }
        popOut = .closed
        model.showControls()
    }

    func closeMenus() {
        popOut = .closed
        model.showControls()
    }
}
#endif
