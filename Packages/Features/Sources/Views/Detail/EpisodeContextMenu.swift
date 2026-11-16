#if canImport(UIKit)
import SwiftUI
import UIKit

/// UIKit owns placement and dismissal; the stacked preview requests its measured content size.
struct EpisodeContextMenu<Content: View, Preview: View>: UIViewControllerRepresentable {
    let content: Content
    let preview: (CGFloat) -> Preview
    let previewSize: CGSize
    let previewCornerRadius: CGFloat
    let menu: () -> UIMenu
    @Binding var isPresented: Bool
    @Environment(\.self) private var environment

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(content.environment(\.self, environment)))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        context.coordinator.owner = self
        controller.rootView = AnyView(content.environment(\.self, environment))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<AnyView>, context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: proposal.replacingUnspecifiedDimensions(by: UIView.layoutFittingExpandedSize))
    }

    @MainActor
    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var owner: EpisodeContextMenu

        init(_ owner: EpisodeContextMenu) { self.owner = owner }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            let owner = owner
            // Leave room beside the card for the native palette and its separated action.
            let window = interaction.view?.window
            let viewport = window.map { $0.bounds.inset(by: $0.safeAreaInsets).size } ?? owner.previewSize
            let isLandscape = viewport.width > viewport.height
            let maximumHeight = max(1, min(owner.previewSize.height, viewport.height) - (isLandscape ? 64 : 360))
            let width = max(1, min(owner.previewSize.width, viewport.width - (isLandscape ? 320 : 32)))
            let controller = UIHostingController(rootView: AnyView(owner.preview(width).environment(\.self, owner.environment)))
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            let fittedSize = CGSize(width: width, height: min(size.height, maximumHeight))
            // Keep text at its chosen size. Long previews scroll inside the available space.
            controller.rootView = AnyView(GeometryReader { geometry in
                ScrollView {
                    owner.preview(geometry.size.width)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .scrollIndicators(.visible, axes: .vertical)
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: owner.previewCornerRadius, style: .continuous))
            .environment(\.self, owner.environment))
            controller.preferredContentSize = fittedSize
            controller.view.backgroundColor = .clear
            controller.view.frame = CGRect(origin: .zero, size: fittedSize)
            let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: { controller }) { _ in owner.menu() }
            configuration.preferredMenuElementOrder = .fixed
            return configuration
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                    animator: (any UIContextMenuInteractionAnimating)?) {
            owner.isPresented = true
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willEndFor configuration: UIContextMenuConfiguration,
                                    animator: (any UIContextMenuInteractionAnimating)?) {
            owner.isPresented = false
        }
    }
}
#endif
