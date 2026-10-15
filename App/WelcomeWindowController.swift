import AppKit
import NotchUI
import SwiftUI

/// The first-launch welcome. Finishing it or closing it counts as done, so it never nags; quitting Notch
/// while it's up doesn't, so it comes back next launch.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: WelcomeView { [weak self] in
            Welcome.markComplete()
            self?.window?.close()
        })
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Size to the content now, so centring uses the real size rather than an empty window's.
        window.setContentSize(hosting.view.fittingSize)
        return window
    }

    /// Only the close button asks this; quitting the app closes windows without asking.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Welcome.markComplete()
        return true
    }
}
