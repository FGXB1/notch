import CoreGraphics

/// What the notch needs to know about a display, independent of AppKit so selection is testable.
public struct ScreenDescriptor: Equatable, Sendable {
    public var uuid: String
    public var isBuiltIn: Bool
    /// The display carrying the menu bar.
    public var isPrimary: Bool
    public var hardwareNotch: CGSize?
    public var menuBarHeight: CGFloat

    public init(uuid: String, isBuiltIn: Bool, isPrimary: Bool, hardwareNotch: CGSize?, menuBarHeight: CGFloat) {
        self.uuid = uuid
        self.isBuiltIn = isBuiltIn
        self.isPrimary = isPrimary
        self.hardwareNotch = hardwareNotch
        self.menuBarHeight = menuBarHeight
    }
}

public struct ScreenSelectionOptions: Equatable, Sendable {
    public var target: DisplayTarget
    public var forceSimulatedNotch: Bool
    public var adjustedWidth: Double
    public var adjustedHeight: Double

    public init(target: DisplayTarget, forceSimulatedNotch: Bool, adjustedWidth: Double, adjustedHeight: Double) {
        self.target = target
        self.forceSimulatedNotch = forceSimulatedNotch
        self.adjustedWidth = adjustedWidth
        self.adjustedHeight = adjustedHeight
    }
}

public enum ScreenSelection {
    /// Decides which displays get a notch and how big it is. Displays without a hardware notch only get a
    /// simulated one when forced, except as a last resort so the app is never invisible (e.g. lid closed).
    public static func select(_ screens: [ScreenDescriptor], options: ScreenSelectionOptions)
        -> [(uuid: String, metrics: NotchMetrics)] {
        let candidates: [ScreenDescriptor] = switch options.target {
        case .builtIn: screens.filter(\.isBuiltIn)
        case .main: screens.filter(\.isPrimary)
        case .all: screens
        }

        var chosen = candidates.filter { $0.hardwareNotch != nil || options.forceSimulatedNotch }
        if chosen.isEmpty, let fallback = screens.first(where: \.isPrimary) ?? screens.first {
            chosen = [fallback]
        }

        return chosen.map { screen in
            let base = screen.hardwareNotch
                ?? CGSize(width: NotchGeometry.simulatedWidth, height: screen.menuBarHeight)
            let size = NotchGeometry.tuned(base, width: options.adjustedWidth, height: options.adjustedHeight)
            return (screen.uuid, NotchMetrics(closed: size, hasHardwareNotch: screen.hardwareNotch != nil))
        }
    }
}
