import AppKit
import Defaults
import NotchCore

/// Feeds two-finger trackpad swipes that start on the notch into its controller. It needs both monitors: a local one for scrolls over the black notch (delivered to
/// this app) and a global one for scrolls over the transparent slop around it (delivered to the app below).
@MainActor
final class SwipeMonitor {
    private let controller: NotchController
    private weak var panel: NSWindow?
    private var monitors: [Any] = []
    private var isTracking = false

    init(controller: NotchController, panel: NSWindow) {
        self.controller = controller
        self.panel = panel
    }

    func start() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        // Trackpad gestures only: mouse wheels have no phases, and momentum would re-trigger actions.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }

        let phase: SwipeTracker.Phase
        if event.phase.contains(.began) {
            guard pointerIsOnNotch else { return }
            isTracking = true
            phase = .began
        } else if event.phase.contains(.changed), isTracking {
            phase = .changed
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled), isTracking {
            isTracking = false
            phase = .ended
        } else {
            return
        }

        // Natural scrolling already reports deltas in finger direction; otherwise flip them, unless the user
        // wants gestures to follow their scroll-direction preference instead.
        let flip = Defaults[.naturalMovement] && !event.isDirectionInvertedFromDevice
        let dx = flip ? -event.scrollingDeltaX : event.scrollingDeltaX
        let dy = flip ? -event.scrollingDeltaY : event.scrollingDeltaY
        controller.handleScroll(dx: dx, dy: dy, phase: phase)
    }

    private var pointerIsOnNotch: Bool {
        guard let frame = panel?.frame else { return false }
        let hit = controller.hitSize
        let padding: CGFloat = 4
        let zone = CGRect(x: frame.midX - hit.width / 2, y: frame.maxY - hit.height - padding,
                          width: hit.width, height: hit.height + padding)
        return zone.contains(NSEvent.mouseLocation)
    }
}
