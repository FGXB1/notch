import AppKit
import SwiftUI

/// Transparent, non-activating window hosting the notch: one level above the shielding window, present on every space (including full-screen ones), and
/// never key, so hovering or clicking it never steals focus from the frontmost app.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        canBecomeVisibleWithoutLogin = true
        animationBehavior = .none
        level = Self.restingLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    /// One above the shielding window: over full-screen apps and the menu bar.
    static let restingLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
    /// Just under the drag image. Drops are only delivered to windows below it (see `DragMonitor`).
    static let dragLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) - 1)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The notch overlaps the menu bar's safe area; without this SwiftUI would push content below it.
final class NoSafeAreaHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
}
