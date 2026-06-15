import AppKit
import SwiftUI

/// NSSplitViewController-backed split view: unlike SwiftUI's HSplitView,
/// the divider position persists across launches via the split view's
/// autosave, and the sidebar collapses with animation for focus mode.
struct PersistentSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    var sidebarCollapsed: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    final class Coordinator {
        var isFirstUpdate = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()

        let sidebarItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: sidebar()))
        sidebarItem.minimumThickness = 330
        sidebarItem.maximumThickness = 520
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .init(260)  // detail flexes on resize
        // Initial collapse state set without animation (restore case)
        sidebarItem.isCollapsed = sidebarCollapsed

        let detailItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: detail()))
        detailItem.minimumThickness = 480

        controller.addSplitViewItem(sidebarItem)
        controller.addSplitViewItem(detailItem)
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        controller.splitView.autosaveName = "MainSplitView"
        return controller
    }

    func updateNSViewController(
        _ controller: NSSplitViewController, context: Context
    ) {
        if let sidebarHost = controller.splitViewItems[0].viewController
            as? NSHostingController<Sidebar> {
            sidebarHost.rootView = sidebar()
        }
        if let detailHost = controller.splitViewItems[1].viewController
            as? NSHostingController<Detail> {
            detailHost.rootView = detail()
        }
        let item = controller.splitViewItems[0]
        if context.coordinator.isFirstUpdate {
            // First layout: match the restored state with no slide
            item.isCollapsed = sidebarCollapsed
            context.coordinator.isFirstUpdate = false
        } else if item.isCollapsed != sidebarCollapsed {
            item.animator().isCollapsed = sidebarCollapsed
        }
    }
}
