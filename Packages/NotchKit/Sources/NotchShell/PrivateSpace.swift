import AppKit
import NotchCore
import PrivateAPI

/// A window-server space above everything, including the lock screen: one at absolute level 400, with the
/// notch windows moved into it.
@MainActor
final class PrivateSpace {
    private let connection = CGSMainConnectionID()
    private let id: CGSSpaceID

    init(level: Int32 = 400) {
        id = CGSSpaceCreate(connection, 1, nil)
        CGSSpaceSetAbsoluteLevel(connection, id, level)
        CGSShowSpaces(connection, [NSNumber(value: id)] as CFArray)
        Log.shell.info("Created private space \(self.id) at level \(level)")
    }

    func add(_ window: NSWindow) {
        CGSAddWindowsToSpaces(connection, [NSNumber(value: window.windowNumber)] as CFArray,
                              [NSNumber(value: id)] as CFArray)
    }

    func remove(_ window: NSWindow) {
        CGSRemoveWindowsFromSpaces(connection, [NSNumber(value: window.windowNumber)] as CFArray,
                                   [NSNumber(value: id)] as CFArray)
    }
}
