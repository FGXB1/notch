import Observation
import ServiceManagement

/// Opening Notch at login, as a login item of the app itself (System Settings › General › Login Items).
@MainActor
@Observable
public final class LaunchAtLogin {
    public static let shared = LaunchAtLogin()

    public private(set) var isEnabled = false
    /// Registered, but the user switched it off in Login Items; only they can turn it back on there.
    public private(set) var needsApproval = false

    private init() {
        refresh()
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.shell.error("Launch at login: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    public func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
