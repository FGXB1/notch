import CoreGraphics
import Testing
@testable import NotchCore

struct GeometryTests {
    @Test func hardwareNotchIsTheGapBetweenAuxiliaryAreas() {
        // 16" MacBook Pro at the 2056-pt "more space" setting, measured by the Phase 0 spike.
        let size = NotchGeometry.hardwareNotchSize(screenWidth: 2056, leftAreaWidth: 918, rightAreaWidth: 918,
                                                   safeAreaTop: 38)
        #expect(size == CGSize(width: 220, height: 38))
    }

    @Test func tuningNeverCollapsesTheNotch() {
        #expect(NotchGeometry.tuned(CGSize(width: 220, height: 38), width: 10, height: -2)
            == CGSize(width: 230, height: 36))
        #expect(NotchGeometry.tuned(CGSize(width: 90, height: 20), width: -40, height: -10)
            == CGSize(width: 80, height: 18))
    }

    @Test func canvasIsCenteredAndFlushWithTheTopEdge() {
        let frame = NotchGeometry.canvasFrame(in: CGRect(x: 0, y: 0, width: 2056, height: 1329))
        #expect(frame == CGRect(x: 648, y: 969, width: 760, height: 360))

        let external = NotchGeometry.canvasFrame(in: CGRect(x: 2056, y: 200, width: 1920, height: 1080))
        #expect(external == CGRect(x: 2636, y: 920, width: 760, height: 360))
    }

    @Test func everyPresentationFitsInsideTheCanvas() {
        let metrics = NotchMetrics(closed: CGSize(width: 220, height: 38), hasHardwareNotch: true)
        let presentations: [(CGSize, NotchRadii)] = [
            (metrics.closed + NotchMetrics.hoverBump, .closed),
            (metrics.compact + NotchMetrics.hoverBump, .compact),
            (metrics.hud + NotchMetrics.hoverBump, .compact),
            (metrics.wide + NotchMetrics.hoverBump, .compact),
            (metrics.peek + NotchMetrics.hoverBump, .peek),
            (metrics.expanded, .expanded),
        ]
        for (size, radii) in presentations {
            // Room for the flares plus the largest swipe stretch.
            #expect(size.width + 2 * radii.top + 12 <= NotchMetrics.canvas.width)
            #expect(size.height + 18 <= NotchMetrics.canvas.height)
        }
    }
}

struct ScreenSelectionTests {
    private let builtIn = ScreenDescriptor(uuid: "builtin", isBuiltIn: true, isPrimary: true,
                                           hardwareNotch: CGSize(width: 220, height: 38), menuBarHeight: 38)
    private let external = ScreenDescriptor(uuid: "external", isBuiltIn: false, isPrimary: false,
                                            hardwareNotch: nil, menuBarHeight: 24)

    private func options(_ target: DisplayTarget, forced: Bool = false) -> ScreenSelectionOptions {
        ScreenSelectionOptions(target: target, forceSimulatedNotch: forced, adjustedWidth: 0, adjustedHeight: 0)
    }

    @Test func builtInTargetUsesTheHardwareNotch() {
        let result = ScreenSelection.select([builtIn, external], options: options(.builtIn))
        #expect(result.map(\.uuid) == ["builtin"])
        #expect(result.first?.metrics.closed == CGSize(width: 220, height: 38))
        #expect(result.first?.metrics.hasHardwareNotch == true)
    }

    @Test func allTargetSkipsNotchlessDisplaysUnlessForced() {
        #expect(ScreenSelection.select([builtIn, external], options: options(.all)).map(\.uuid) == ["builtin"])
        let forced = ScreenSelection.select([builtIn, external], options: options(.all, forced: true))
        #expect(forced.map(\.uuid) == ["builtin", "external"])
        #expect(forced.last?.metrics.closed == CGSize(width: NotchGeometry.simulatedWidth, height: 24))
    }

    @Test func lidClosedFallsBackToASimulatedNotchOnThePrimaryDisplay() {
        var primaryExternal = external
        primaryExternal.isPrimary = true
        let result = ScreenSelection.select([primaryExternal], options: options(.builtIn))
        #expect(result.map(\.uuid) == ["external"])
        #expect(result.first?.metrics.hasHardwareNotch == false)
    }
}
