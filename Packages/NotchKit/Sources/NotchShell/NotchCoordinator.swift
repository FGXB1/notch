import AppKit
import Defaults
import NotchCore

/// Owns one notch per selected display and keeps that set in sync with screens and settings.
@MainActor
public final class NotchCoordinator {
    public var onOpenSettings: () -> Void = {}

    private var windows: [String: NotchWindowController] = [:]
    private lazy var space = PrivateSpace()
    private lazy var lockScreen = LockScreenController(space: space)
    private var screenObserver: NSObjectProtocol?
    private var settingsTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private let fullScreen = FullScreenMonitor()
    private var fullScreenDisplays: Set<String> = []
    private let backdrop = BackdropMonitor()
    private var darkBackdrops: [String: Bool] = [:]

    public init() {}

    /// The notch on the menu-bar display, used for previews from Settings.
    public var primaryController: NotchController? {
        let primary = NSScreen.screens.first?.displayUUID
        return primary.flatMap { windows[$0]?.controller } ?? windows.values.first?.controller
    }

    public func start() {
        rebuild()
        lockScreen.onLock = { [weak self] in
            self?.windows.values.forEach { $0.controller.collapse() }
        }
        lockScreen.start()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        settingsTask = Task { [weak self] in
            let keys: [Defaults._AnyKey] = [.displayTarget, .forceSimulatedNotch, .notchAdjustedWidth,
                                            .notchAdjustedHeight]
            for await _ in Defaults.updates(keys, initial: false) {
                self?.rebuild()
            }
        }

        fullScreen.onChange = { [weak self] displays in
            guard let self else { return }
            fullScreenDisplays = displays
            for (uuid, window) in windows {
                window.controller.setFullScreen(displays.contains(uuid))
            }
        }
        fullScreen.start()
        applyCaptureSharing()

        backdrop.onChange = { [weak self] darkness in
            guard let self else { return }
            darkBackdrops = darkness
            for (uuid, window) in windows {
                window.controller.setBackdropDark(darkness[uuid] ?? false)
            }
        }
        backdrop.start()

        captureTask = Task { [weak self] in
            for await _ in Defaults.updates(.hideFromScreenCapture, initial: false) {
                self?.applyCaptureSharing()
            }
        }
    }

    /// Leaves the notch (and the lock-screen widgets) out of screenshots and recordings if asked to.
    private func applyCaptureSharing() {
        let sharing: NSWindow.SharingType = Defaults[.hideFromScreenCapture] ? .none : .readOnly
        for window in windows.values {
            window.sharingType = sharing
        }
        lockScreen.sharingType = sharing
    }

    /// Shows the lock-screen widgets on the desktop briefly (Settings › Lock Screen › Preview).
    public func previewLockScreen() {
        lockScreen.preview()
    }

    private func rebuild() {
        let screens = NSScreen.screens
        let primaryUUID = screens.first?.displayUUID
        let descriptors = screens.map { screen in
            ScreenDescriptor(uuid: screen.displayUUID, isBuiltIn: screen.isBuiltIn,
                             isPrimary: screen.displayUUID == primaryUUID, hardwareNotch: screen.hardwareNotchSize,
                             menuBarHeight: screen.menuBarHeight)
        }
        let options = ScreenSelectionOptions(target: Defaults[.displayTarget],
                                             forceSimulatedNotch: Defaults[.forceSimulatedNotch],
                                             adjustedWidth: Defaults[.notchAdjustedWidth],
                                             adjustedHeight: Defaults[.notchAdjustedHeight])
        let selected = ScreenSelection.select(descriptors, options: options)

        let selectedUUIDs = Set(selected.map(\.uuid))
        for (uuid, window) in windows where !selectedUUIDs.contains(uuid) {
            space.remove(window.panel)
            window.close()
            windows[uuid] = nil
        }

        for (uuid, metrics) in selected {
            guard let screen = screens.first(where: { $0.displayUUID == uuid }) else { continue }
            if let existing = windows[uuid] {
                existing.update(screen: screen, metrics: metrics)
            } else {
                let window = NotchWindowController(screen: screen, metrics: metrics, space: space,
                                                   onOpenSettings: { [weak self] in self?.onOpenSettings() })
                space.add(window.panel)
                window.sharingType = Defaults[.hideFromScreenCapture] ? .none : .readOnly
                window.controller.setFullScreen(fullScreenDisplays.contains(uuid))
                window.controller.setBackdropDark(darkBackdrops[uuid] ?? false)
                windows[uuid] = window
            }
        }
        Log.shell.info("Notches on \(self.windows.count) display(s)")
    }
}
