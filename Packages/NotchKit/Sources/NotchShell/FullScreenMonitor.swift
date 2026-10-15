import AppKit
import ApplicationServices
import NotchCore

/// Reports which displays have a full-screen app, re-checking whenever the space or the frontmost app
/// changes. Full-screen transitions animate, so each change is checked again once they've settled.
///
/// Two signals: a window covering a whole display (any app, any display), and the frontmost app's own
/// "full screen" flag over Accessibility. The second is needed on notched MacBooks, where full-screen apps
/// sit below the camera by default and look exactly like a zoomed window to the window list.
@MainActor
final class FullScreenMonitor {
    /// Display UUIDs with a full-screen app.
    var onChange: (Set<String>) -> Void = { _ in }

    private var observers: [NSObjectProtocol] = []
    private var checkTask: Task<Void, Never>?
    private var current: Set<String> = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        })
        check()
    }

    private func scheduleCheck() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            // Once straight away, then after the space-switch animation has finished.
            for delay in [100, 900] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.check()
            }
        }
    }

    private func check() {
        let displays = NSScreen.screens.compactMap { screen -> (id: String, bounds: CGRect)? in
            screen.displayID.map { (screen.displayUUID, CGDisplayBounds($0)) }
        }
        var found = FullScreenDetector.fullScreenDisplays(windows: FullScreenDetector.onScreenWindows(),
                                                          displays: displays, excludingPID: getpid())
        if let frame = Self.frontmostFullScreenWindowFrame(),
           let display = displays.first(where: { $0.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            found.insert(display.id)
        }
        guard found != current else { return }
        current = found
        Log.shell.info("Full-screen apps on \(found.count) display(s)")
        onChange(found)
    }

    /// The frontmost app's focused window, if it says it's full screen; in top-left screen coordinates.
    /// Needs Accessibility (which Notch has for the media keys); without it, nil.
    private static func frontmostFullScreenWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // A hung app mustn't stall the main thread for the default six seconds.
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard let window = attribute(kAXFocusedWindowAttribute, of: element).map({ $0 as! AXUIElement }),
              attribute("AXFullScreen", of: window) as? Bool == true,
              let positionValue = attribute(kAXPositionAttribute, of: window),
              let sizeValue = attribute(kAXSizeAttribute, of: window) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
