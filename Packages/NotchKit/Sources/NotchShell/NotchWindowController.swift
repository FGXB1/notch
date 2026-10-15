import AppKit
import MediaKit
import NotchCore
import NotchUI
import SwiftUI

/// One display's notch: its state, the window that renders it, and its gesture input.
@MainActor
final class NotchWindowController {
    let controller: NotchController
    let panel: NotchPanel
    private let swipes: SwipeMonitor
    private let drags: DragMonitor
    private let blur: BlurBackdrop

    init(screen: NSScreen, metrics: NotchMetrics, space: PrivateSpace, onOpenSettings: @escaping () -> Void) {
        controller = NotchController(metrics: metrics)
        controller.onHorizontalSwipe = { MediaController.shared.handleSwipe($0) }
        panel = NotchPanel(frame: NotchGeometry.canvasFrame(in: screen.frame))
        swipes = SwipeMonitor(controller: controller, panel: panel)
        drags = DragMonitor(controller: controller, panel: panel, space: space)
        blur = BlurBackdrop(controller: controller, frame: panel.frame)

        let hostingView = NoSafeAreaHostingView(
            rootView: NotchRootView(controller: controller, onOpenSettings: onOpenSettings))
        // The canvas size is fixed; letting the hosting view drive window constraints would add an AppKit
        // layout pass to every animation frame (the stutter seen in the Phase 0 spike).
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        swipes.start()
        drags.start()
    }

    func update(screen: NSScreen, metrics: NotchMetrics) {
        let frame = NotchGeometry.canvasFrame(in: screen.frame)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        controller.update(metrics: metrics)
        blur.update(frame: frame)
    }

    /// Whether screenshots and recordings can see this notch.
    var sharingType: NSWindow.SharingType {
        get { panel.sharingType }
        set {
            panel.sharingType = newValue
            blur.sharingType = newValue
        }
    }

    func close() {
        swipes.stop()
        drags.stop()
        blur.close()
        panel.orderOut(nil)
        panel.close()
    }
}
