import AppKit
import NotchUI
import SwiftUI

/// A plain window instead of a SwiftUI `Settings` scene, so the notch's own context menu can open it too.
@MainActor
final class SettingsWindowController {
    private let actions: SettingsActions
    private var window: NSWindow?

    init(actions: SettingsActions) {
        self.actions = actions
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(actions: actions)))
        window.title = "Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        // macOS 26: the toolbar and sidebar float as Liquid Glass over the content.
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()
        return window
    }
}
