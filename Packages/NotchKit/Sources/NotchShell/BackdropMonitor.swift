import AppKit
import NotchCore

/// Whether what's behind each notch is dark: the desktop picture under it, or Dark Mode (where the windows
/// below the menu bar are dark too). Re-checked when the space, displays or appearance change, and every so
/// often for rotating wallpapers. Decoding happens off the main thread.
@MainActor
final class BackdropMonitor {
    /// Display UUID → dark.
    var onChange: ([String: Bool]) -> Void = { _ in }

    private var observers: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var current: [String: Bool] = [:]

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        })
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    private func check() {
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let pictures = NSScreen.screens.map { screen in
            (uuid: screen.displayUUID, url: NSWorkspace.shared.desktopImageURL(for: screen), size: screen.frame.size)
        }
        task?.cancel()
        task = Task { [weak self] in
            let darkness = await Task.detached(priority: .utility) {
                var result: [String: Bool] = [:]
                for picture in pictures {
                    let luminance = picture.url.flatMap {
                        WallpaperSampler.luminance(ofImageAt: $0, screenSize: picture.size)
                    }
                    result[picture.uuid] = isDarkMode || (luminance.map { $0 < WallpaperSampler.darkThreshold } ?? false)
                }
                return result
            }.value
            guard !Task.isCancelled, let self, darkness != self.current else { return }
            self.current = darkness
            Log.shell.info("Dark backdrop on \(darkness.values.filter { $0 }.count) of \(darkness.count) display(s)")
            self.onChange(darkness)
        }
    }
}
