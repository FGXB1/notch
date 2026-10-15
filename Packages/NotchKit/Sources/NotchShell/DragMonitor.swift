import AppKit
import NotchCore

/// Notices a drag from another app (Finder, Safari, Photos, ...) approaching the notch and opens the tray
/// so there's somewhere to drop it. A drag is under way when the system's drag pasteboard changes after
/// the mouse goes down; the mouse events themselves go to the app being dragged from, so this watches them
/// with a global monitor (mouse monitors don't need Accessibility).
///
/// macOS only delivers drops to windows below the drag image and outside private spaces; anywhere else they
/// fall through to the Desktop. So for the length of a drag the notch steps down to just under the drag
/// image and out of the private space that keeps it above the lock screen. Its collection behavior keeps
/// it on every space, full-screen ones included, in the meantime.
@MainActor
final class DragMonitor {
    private let controller: NotchController
    private let space: PrivateSpace
    private weak var panel: NSWindow?
    private var monitors: [Any] = []
    private let pasteboard = NSPasteboard(name: .drag)
    private var changeCountAtMouseDown = 0
    private var isDragging = false
    private var isNear = false
    private var rejoinSpaceTask: Task<Void, Never>?

    /// Room around the notch where an approaching drag already counts.
    private static let approachMargin = CGSize(width: 60, height: 44)

    init(controller: NotchController, panel: NSWindow, space: PrivateSpace) {
        self.controller = controller
        self.panel = panel
        self.space = space
        // A drag already under way at launch isn't ours to react to.
        changeCountAtMouseDown = pasteboard.changeCount
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event.type) }
        }) {
            monitors.append(global)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            changeCountAtMouseDown = pasteboard.changeCount
        case .leftMouseDragged:
            if !isDragging {
                guard pasteboard.changeCount != changeCountAtMouseDown, carriesDroppableContent else { return }
                isDragging = true
                rejoinSpaceTask?.cancel()
                if let panel {
                    space.remove(panel)
                    panel.level = NotchPanel.dragLevel
                }
                Log.tray.info("Drag seen: \(self.pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "", privacy: .public)")
            }
            let near = approachZone.contains(NSEvent.mouseLocation)
            guard near != isNear else { return }
            isNear = near
            Log.tray.info("Drag \(near ? "approached" : "left", privacy: .public) the notch")
            near ? controller.fileDragEntered() : controller.fileDragExited()
        case .leftMouseUp:
            guard isDragging else { return }
            isDragging = false
            isNear = false
            let inside = shellFrame.contains(NSEvent.mouseLocation)
            Log.tray.info("Drag ended \(inside ? "on" : "off", privacy: .public) the notch")
            controller.fileDragEnded(pointerInside: inside)
            // Back on top once the drop (delivered around the same time as this mouse-up) has landed.
            rejoinSpaceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, !self.isDragging, let panel = self.panel else { return }
                panel.level = NotchPanel.restingLevel
                self.space.add(panel)
            }
        default:
            break
        }
    }

    private var carriesDroppableContent: Bool {
        let types = pasteboard.types ?? []
        return types.contains(.fileURL) || types.contains(.URL) || types.contains(.string)
            || types.contains(.png) || types.contains(.tiff)
    }

    /// The notch as it is now (closed or open), in screen coordinates.
    private var shellFrame: CGRect {
        guard let frame = panel?.frame else { return .null }
        let size = controller.isExpanded ? controller.metrics.expanded : controller.hitSize
        return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width,
                      height: size.height)
    }

    private var approachZone: CGRect {
        let margin = Self.approachMargin
        let shell = shellFrame
        guard !shell.isNull else { return .null }
        // Includes the strip above the notch: the pointer can reach the very top edge of the screen.
        return CGRect(x: shell.minX - margin.width, y: shell.minY - margin.height,
                      width: shell.width + 2 * margin.width, height: shell.height + margin.height + 1)
    }
}
