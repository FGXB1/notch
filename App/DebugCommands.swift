#if DEBUG
import AppKit
import NotchCore
import AudioTap
import FileTray
import NotchShell
import WeatherLite

/// Drives the notch from the command line while developing, e.g.
/// `swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("dev.ishan.notch.debug"), object: "tab:tray", deliverImmediately: true)'`
/// Commands: expand, collapse, tab:home, tab:tray, tray:add:<path>, tray:clear, quicklook:<index>, weather:refresh,
/// lock:preview, welcome, drag:sim:<x>,<y>[,<x2>,<y2>] (drags from a point, in top-left screen coordinates, onto the
/// notch or to the second point), click:<x>,<y>[,cmd|shift].
@MainActor
enum DebugCommands {
    private static var observer: NSObjectProtocol?

    static func listen(coordinator: NotchCoordinator, showWelcome: @escaping @MainActor () -> Void) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("dev.ishan.notch.debug"), object: nil, queue: .main
        ) { [weak coordinator] notification in
            let command = notification.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let controller = coordinator?.primaryController else { return }
                switch command {
                case "expand": controller.expand()
                case "collapse": controller.collapse()
                case "tab:home": controller.select(.home)
                case "tab:tray": controller.select(.tray)
                case "tray:clear": TrayStore.shared.removeAll()
                case "weather:refresh": WeatherController.shared.scheduleRefresh(force: true)
                case "lock:preview": coordinator?.previewLockScreen()
                case "welcome": showWelcome()
                case "permissions":
                    let audio = LiveWaveform.shared.permission.map { "\($0)" } ?? "unknown"
                    Log.shell.info("Permissions: audio capture \(audio, privacy: .public), accessibility \(AXIsProcessTrusted()), location \(String(describing: LocationProvider.shared.authorization), privacy: .public), launch at login \(LaunchAtLogin.shared.isEnabled)")
                case let command where command.hasPrefix("tray:add:"):
                    TrayStore.shared.add(urls: [URL(filePath: String(command.dropFirst("tray:add:".count)))])
                case let command where command.hasPrefix("drag:sim:"):
                    // drag:sim:x,y drags onto the notch; drag:sim:x1,y1,x2,y2 drags between two points.
                    let numbers = command.dropFirst("drag:sim:".count).split(separator: ",").compactMap { Double($0) }
                    guard numbers.count == 2 || numbers.count == 4 else { return }
                    let target = numbers.count == 4 ? CGPoint(x: numbers[2], y: numbers[3]) : nil
                    simulateDrag(from: CGPoint(x: numbers[0], y: numbers[1]), to: target)
                case let command where command.hasPrefix("click:"):
                    // click:x,y or click:x,y,cmd / click:x,y,shift
                    let parts = command.dropFirst("click:".count).split(separator: ",")
                    guard parts.count >= 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return }
                    let flags: CGEventFlags = parts.dropFirst(2).reduce([]) { flags, part in
                        part == "cmd" ? flags.union(.maskCommand) : part == "shift" ? flags.union(.maskShift) : flags
                    }
                    simulateClick(at: CGPoint(x: x, y: y), flags: flags)
                case let command where command.hasPrefix("quicklook:"):
                    let index = Int(command.dropFirst("quicklook:".count)) ?? 0
                    QuickLook.shared.toggle(TrayStore.shared.urls, index: index)
                default:
                    break
                }
            }
        }
    }

    /// Posts a real mouse drag (needs the Accessibility permission Notch already has for media keys):
    /// press at `start`, glide to the notch, hover, release.
    private static func simulateDrag(from start: CGPoint, to end: CGPoint?) {
        guard let screen = NSScreen.screens.first else { return }
        let target = end ?? CGPoint(x: screen.frame.midX, y: 70)
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            // Explicitly none: otherwise a ⌘ from an earlier simulated click can carry over.
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        Task {
            post(.mouseMoved, start)
            try? await Task.sleep(for: .milliseconds(150))
            post(.leftMouseDown, start)
            try? await Task.sleep(for: .milliseconds(150))
            let steps = 40
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                post(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
                try? await Task.sleep(for: .milliseconds(25))
            }
            // Wiggle in place: drag destinations update on movement.
            for step in 0..<30 {
                post(.leftMouseDragged, CGPoint(x: target.x + Double(step % 2 == 0 ? 2 : -2), y: target.y))
                try? await Task.sleep(for: .milliseconds(40))
            }
            post(.leftMouseUp, target)
        }
    }

    private static func simulateClick(at point: CGPoint, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        Task {
            post(.mouseMoved)
            try? await Task.sleep(for: .milliseconds(80))
            post(.leftMouseDown)
            try? await Task.sleep(for: .milliseconds(60))
            post(.leftMouseUp)
        }
    }
}
#endif
