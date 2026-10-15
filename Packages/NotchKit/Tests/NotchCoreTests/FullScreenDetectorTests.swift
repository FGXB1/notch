import CoreGraphics
import Testing
@testable import NotchCore

struct FullScreenDetectorTests {
    // Built-in display at the origin; an external one to its right. Top-left coordinates.
    let displays: [(id: String, bounds: CGRect)] = [
        ("builtin", CGRect(x: 0, y: 0, width: 2056, height: 1329)),
        ("external", CGRect(x: 2056, y: 0, width: 2560, height: 1440)),
    ]

    @Test func windowCoveringADisplayIsFullScreenThere() {
        let video = FullScreenDetector.Window(ownerPID: 10, layer: 0, bounds: displays[1].bounds, alpha: 1)
        #expect(FullScreenDetector.fullScreenDisplays(windows: [video], displays: displays) == ["external"])
    }

    @Test func zoomedWindowsStopAtTheMenuBar() {
        let zoomed = FullScreenDetector.Window(ownerPID: 10, layer: 0,
                                               bounds: CGRect(x: 0, y: 38, width: 2056, height: 1291), alpha: 1)
        #expect(FullScreenDetector.fullScreenDisplays(windows: [zoomed], displays: displays).isEmpty)
    }

    @Test func overlaysAndInvisibleWindowsDontCount() {
        let shield = FullScreenDetector.Window(ownerPID: 10, layer: 25, bounds: displays[0].bounds, alpha: 1)
        let invisible = FullScreenDetector.Window(ownerPID: 11, layer: 0, bounds: displays[0].bounds, alpha: 0)
        let own = FullScreenDetector.Window(ownerPID: 99, layer: 0, bounds: displays[0].bounds, alpha: 1)
        let found = FullScreenDetector.fullScreenDisplays(windows: [shield, invisible, own], displays: displays,
                                                          excludingPID: 99)
        #expect(found.isEmpty)
    }

    @Test func toleratesRounding() {
        let nearly = FullScreenDetector.Window(ownerPID: 10, layer: 0,
                                               bounds: CGRect(x: 0.5, y: 0, width: 2055.5, height: 1329), alpha: 1)
        #expect(FullScreenDetector.fullScreenDisplays(windows: [nearly], displays: displays) == ["builtin"])
    }
}
