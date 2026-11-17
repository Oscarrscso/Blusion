#if canImport(UIKit)
import Persistence
import PlayerKit
import StremioKit
import SwiftUI
import UIKit

extension StreamPickerView {
    // MARK: the main action

    /// How much the switch is scaled so it is as tall as the Auto Pick button. 1 until both have been measured.
    private var autoPickSwitchScale: CGFloat {
        guard autoPickButtonHeight > 0, autoPickSwitchSize.height > 0 else { return 1 }
        return autoPickButtonHeight / autoPickSwitchSize.height
    }

    /// Embedded in a title page: a small round X, as tall as Auto Pick, that takes the streams away and puts the details back.
    @ViewBuilder
    private var closeButton: some View {
        if isEmbedded, let onClose {
            let side = autoPickButtonHeight > 0 ? autoPickButtonHeight : 34
            let radius = side / 2 * min(metrics.cornerScale(for: .actionButtons), 1)
            Button {
                Haptics.play(.buttons)
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(Theme.faintText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(HoverGlassButtonStyle())
            .buttonBorderShape(.roundedRectangle(radius: radius))
            // swiftlint:disable:next fixed_view_corner_shape -- Radius above uses the actionButtons cornerScale.
            .buttonOutline(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .controlSize(.small)
            .frame(width: side, height: side)
            .accessibilityLabel("Back to details")
            .help("Back to details")
            .accessibilityIdentifier("streams.close")
        }
    }

    @ViewBuilder
    var playBestButton: some View {
        let autoPickInfo = model.recommendedStreamLabel ?? (model.isLoading ? Self.lastAutoPickInfo : nil)
        if model.listing.items.isEmpty && !model.isLoading {
            // With no stream to pick, the X still stands where the row would, so the details are one tap away.
            closeButton.padding(.horizontal, streamMargin)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.m) {
                    closeButton
                    Button {
                        // The same swipe check as a stream card: a swipe that ends on Auto Pick plays nothing.
                        guard !SwipeRecord.latest.isSwipe(at: ContinuousClock.now) else { return }
                        autoPick()
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            if model.isAutoPicking || preparingViaAutoPick {
                                Spinner()
                            } else {
                                Image(systemName: "sparkles").foregroundStyle(.secondary)
                            }
                            Text("Auto Pick")
                            // Keep the previous recommendation until the new streams have loaded.
                            if let kind = autoPickInfo {
                                Text("- \(kind)")
                                    .fontWeight(.regular)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryActionCompact)
                    .controlSize(.small)
                    .disabled(model.isAutoPicking || preparingViaAutoPick)
                    .accessibilityLabel(autoPickInfo.map { "Auto Pick, \($0)" } ?? "Auto Pick")
                    .accessibilityIdentifier("streams.playBest")
                    .onChange(of: model.recommendedStreamLabel, initial: true) { _, info in
                        if let info { Self.lastAutoPickInfo = info }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        autoPickButtonHeight = $0
                        Self.lastAutoPickHeight = $0
                    }
                    // Saves the choice to start the best stream at once next time; it starts nothing itself.
                    Toggle("Always pick the best stream", isOn: Binding(get: { model.autoPlaysBestStream }, set: { value in
                        Task { await model.setAutoPlaysBestStream(value) }
                        // Turning it on picks now, as Auto Pick does, so the switch does what it says the moment it is tapped.
                        if value { autoPick() }
                    }))
                    .labelsHidden()
                    #if targetEnvironment(macCatalyst)
                    // The Mac's own switch at its own size (its default there is a checkbox, which scaled up read as an empty box).
                    .toggleStyle(.switch)
                    .buttonCursor()
                    .fixedSize()
                    .help("Always pick the best stream")
                    #else
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { autoPickSwitchSize = $0 }
                    // The switch has one size of its own, so it is scaled to stand exactly as tall as the button beside it.
                    .scaleEffect(autoPickSwitchScale)
                    .frame(width: autoPickSwitchSize.width > 0 ? autoPickSwitchSize.width * autoPickSwitchScale : nil,
                           height: autoPickSwitchSize.height > 0 ? autoPickSwitchSize.height * autoPickSwitchScale : nil)
                    #endif
                    .accessibilityLabel("Always pick the best stream")
                    .accessibilityHint("Starts the best stream at once whenever you open a title's streams")
                    .accessibilityIdentifier("streams.autoPickAlways")
                }
                if let message = model.autoPickMessage { Text(message).appFont(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, streamMargin)
        }
    }

    // MARK: filtering

    /// Sharpness bands the chips filter by. Anything under 720 lines is one band, "SD".
    enum Band: Int, CaseIterable {
        case uhd = 2160, fullHD = 1080, hd = 720, sd = 480

        init(_ resolution: Int) {
            self = resolution >= 2160 ? .uhd : resolution >= 1080 ? .fullHD : resolution >= 720 ? .hd : .sd
        }

        var title: String {
            switch self {
            case .uhd: "4K"
            case .fullHD: "1080p"
            case .hd: "720p"
            case .sd: "SD"
            }
        }
    }

    private func band(of item: RankedStream) -> Band? { item.quality.resolution.map(Band.init) }

    /// Keep the previous addons while waiting for streams, then use the addons actually returned.
    var availableAddons: [AddonSummary] {
        var seen = Set<UUID>()
        let addons = model.addonSections.map(\.addon).filter { seen.insert($0.id).inserted }
        if addons.isEmpty && model.isLoading { return Self.lastAvailableAddons }
        return addons
    }

    /// The chosen addon, while it still has streams listed. One that has gone falls back to all.
    var chosenAddon: UUID? {
        guard let addonFilter, availableAddons.contains(where: { $0.id == addonFilter }) else { return nil }
        return addonFilter
    }

    /// The sections of the chosen addon, or every section.
    var addonSections: [StreamPickerViewModel.AddonSection] {
        guard let chosenAddon else { return model.addonSections }
        return model.addonSections.filter { $0.addon.id == chosenAddon }
    }

    /// Keep the previous bar while waiting for streams, then use the resolutions actually returned.
    private var availableBands: [Band] {
        let present = Set(addonSections.flatMap(\.streams).compactMap(band(of:)))
        if present.isEmpty && model.isLoading { return Self.lastResolutionBands }
        return Band.allCases.filter(present.contains)
    }

    /// The sections with only the chosen addon's and band's streams. A band that has gone (a refresh found fewer streams, or another
    /// addon was chosen) falls back to all.
    var visibleSections: [StreamPickerViewModel.AddonSection] {
        guard let band = resolutionFilter, availableBands.contains(band) else { return addonSections }
        return addonSections.compactMap { section in
            let streams = section.streams.filter { self.band(of: $0) == band }
            return streams.isEmpty ? nil : StreamPickerViewModel.AddonSection(addon: section.addon, streams: streams)
        }
    }

    /// "All  4K  1080p  720p": visible immediately, then adjusted as stream resolutions arrive.
    @ViewBuilder
    var resolutionChips: some View {
        if !availableBands.isEmpty {
            QualitySelector(titles: ["All"] + availableBands.map(\.title), selection: Binding {
                resolutionFilter.flatMap { availableBands.firstIndex(of: $0).map { $0 + 1 } } ?? 0
            } set: { index in
                resolutionFilter = index > 0 && index <= availableBands.count ? availableBands[index - 1] : nil
            })
            .onChange(of: availableBands, initial: true) { _, bands in
                if !bands.isEmpty { Self.lastResolutionBands = bands }
            }
        }
    }

    /// "All  Torrentio  Comet": shown once more than one addon has streams, so one addon's streams can be listed on their own.
    @ViewBuilder
    var addonChips: some View {
        let addons = availableAddons
        if addons.count > 1 {
            QualitySelector(titles: ["All"] + addons.map(\.name), selection: Binding {
                chosenAddon.flatMap { id in addons.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
            } set: { index in
                addonFilter = index > 0 && index <= addons.count ? addons[index - 1].id : nil
            }, accessibilityID: "streams.addonFilter")
        }
    }
}
#endif
