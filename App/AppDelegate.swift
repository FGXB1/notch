import AppKit
import AudioTap
import CalendarKit
import FileTray
import MediaKit
import NotchShell
import NotchUI
import Quartz
import SystemKit
import WeatherLite

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = NotchCoordinator()
    private let updater = Updater()
    private lazy var settingsWindow = SettingsWindowController(
        actions: SettingsActions(togglePreview: { [weak self] in self?.coordinator.primaryController?.toggle() },
                                 previewLockScreen: { [weak self] in self?.coordinator.previewLockScreen() },
                                 showWelcome: { [weak self] in self?.welcomeWindow.show() },
                                 updates: updater.controls))
    private let welcomeWindow = WelcomeWindowController()

    private var terminationSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleTerminationSignal()
        coordinator.onOpenSettings = { [weak self] in self?.showSettings() }
        coordinator.start()
        MediaController.shared.start()
        CalendarController.shared.start()
        HUDController.shared.start()
        BatteryMonitor.shared.start()
        DeviceMonitor.shared.start()
        FocusMonitor.shared.start()
        LiveWaveform.shared.start()
        WeatherController.shared.start()
        if Welcome.isNeeded {
            welcomeWindow.show()
        }
        #if DEBUG
        DebugCommands.listen(coordinator: coordinator, showWelcome: { [weak self] in self?.welcomeWindow.show() })
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaController.shared.stop()
        FocusMonitor.shared.stop()
    }

    /// `kill`/`pkill` (as Scripts/run.sh does) becomes a normal quit, so child processes are cleaned up.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSource = source
    }

    /// Launching Notch again (Spotlight, Finder, `open -a Notch`) opens Settings, since there's no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        settingsWindow.show()
    }

    // MARK: Quick Look
    // The tray's previews use the shared QLPreviewPanel, which looks for a controller up the responder
    // chain. Notch's panels never become key, so the chain ends here, at the app delegate. The panel calls
    // these on the main thread; they're just declared without an actor.

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QuickLook.shared.beginControl(panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QuickLook.shared.endControl(panel) }
    }
}
