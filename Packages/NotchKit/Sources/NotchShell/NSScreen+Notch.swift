import AppKit
import NotchCore

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Stable across reconnects and arrangement changes, unlike `NSScreen` identity or display IDs.
    var displayUUID: String {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return localizedName
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    var hardwareNotchSize: CGSize? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea, safeAreaInsets.top > 0 else {
            return nil
        }
        return NotchGeometry.hardwareNotchSize(screenWidth: frame.width, leftAreaWidth: left.width,
                                               rightAreaWidth: right.width, safeAreaTop: safeAreaInsets.top)
    }

    var menuBarHeight: CGFloat {
        let height = frame.maxY - visibleFrame.maxY
        return height > 0 ? height : NSStatusBar.system.thickness
    }
}
