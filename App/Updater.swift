import AppKit
import NotchUI
import Sparkle

/// Sparkle, for builds that can update themselves: the ones Scripts/release.sh makes, which carry the
/// appcast's address and the public key update archives must be signed with. Other builds (Debug, a plain
/// Release build from Xcode) have neither, and never check.
@MainActor
final class Updater: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        #if !DEBUG
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        if !feed.isEmpty, !key.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: self)
        }
        #endif
    }

    var controls: UpdateControls? {
        guard let controller else { return nil }
        return UpdateControls(checkNow: { controller.checkForUpdates(nil) },
                              automaticallyChecks: { controller.updater.automaticallyChecksForUpdates },
                              setAutomaticallyChecks: { controller.updater.automaticallyChecksForUpdates = $0 })
    }

    // MARK: SPUStandardUserDriverDelegate
    // Notch has no Dock icon to badge, so when a scheduled check finds an update, Sparkle's window is shown
    // and brought forward like one the user asked for.

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        NSApp.activate()
    }
}
