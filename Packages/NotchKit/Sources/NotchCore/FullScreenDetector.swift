import CoreGraphics
import Foundation

/// Which displays an app is showing full screen on, from the window server's window list. Window bounds,
/// layers and owners are readable without screen-recording permission (only titles need it).
public enum FullScreenDetector {
    public struct Window: Equatable, Sendable {
        public var ownerPID: Int32
        public var layer: Int
        /// Global display coordinates (top-left origin), as the window list reports them.
        public var bounds: CGRect
        public var alpha: Double

        public init(ownerPID: Int32, layer: Int, bounds: CGRect, alpha: Double) {
            self.ownerPID = ownerPID
            self.layer = layer
            self.bounds = bounds
            self.alpha = alpha
        }
    }

    /// A normal-level, visible window covering a whole display, menu bar included, is full screen there.
    /// A zoomed window stops at the menu bar, so it doesn't count.
    public static func fullScreenDisplays<ID: Hashable>(windows: [Window], displays: [(id: ID, bounds: CGRect)],
                                                        excludingPID: Int32? = nil) -> Set<ID> {
        var result = Set<ID>()
        for window in windows where window.layer == 0 && window.alpha > 0 && window.ownerPID != excludingPID {
            for display in displays where covers(window.bounds, display.bounds) {
                result.insert(display.id)
            }
        }
        return result
    }

    private static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        let tolerance: CGFloat = 1
        return window.minX <= display.minX + tolerance && window.minY <= display.minY + tolerance
            && window.maxX >= display.maxX - tolerance && window.maxY >= display.maxY - tolerance
    }

    /// The current on-screen windows.
    public static func onScreenWindows() -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
            return Window(ownerPID: pid, layer: layer, bounds: bounds,
                          alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
}
