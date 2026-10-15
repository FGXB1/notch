import CoreGraphics

/// Size of the notch on one display, plus the fixed transparent canvas the notch animates inside.
public struct NotchMetrics: Equatable, Sendable {
    /// The black body that covers the hardware notch when closed (flares excluded).
    public var closed: CGSize
    public var hasHardwareNotch: Bool

    public init(closed: CGSize, hasHardwareNotch: Bool) {
        self.closed = closed
        self.hasHardwareNotch = hasHardwareNotch
    }

    /// The window never resizes; every presentation must fit inside this canvas.
    public static let canvas = CGSize(width: 760, height: 360)
    /// How much the closed notch swells while hovered.
    public static let hoverBump = CGSize(width: 14, height: 4)
    /// How much the notch gives while pressed.
    public static let pressInset = CGSize(width: 8, height: 3)
    /// Extra hit area around the notch so the pointer doesn't have to be pixel-perfect.
    public static let hitSlop: CGFloat = 4
    /// Width of each side wing around the hardware notch. Derived from the notch height so a centered
    /// glyph sits as far from the outer edge as from the top and bottom (iPhone's compact island proportions).
    public var compactWing: CGFloat { max(34, closed.height + 6) }
    /// HUD wings carry a level bar on the trailing side, so they're a little wider.
    public var hudWing: CGFloat { compactWing + 22 }
    /// Wings that hold a word or a number beside a glyph (status notices, HUD with percentage).
    public var wideWing: CGFloat { hudWing + 18 }
    /// Glyph/artwork size inside a wing.
    public var wingGlyph: CGFloat { max(14, min(22, closed.height - 16)) }

    public var compact: CGSize {
        CGSize(width: closed.width + 2 * compactWing, height: closed.height)
    }

    public var hud: CGSize {
        CGSize(width: closed.width + 2 * hudWing, height: closed.height)
    }

    public var wide: CGSize {
        CGSize(width: closed.width + 2 * wideWing, height: closed.height)
    }

    /// Depth of the lock chin below the camera: room for the padlock with clear space above and below.
    public static let lockChin: CGFloat = 34

    /// A short chin under the camera holding the padlock while locked.
    public var lock: CGSize {
        CGSize(width: closed.width + 12, height: closed.height + Self.lockChin)
    }

    public var peek: CGSize {
        CGSize(width: max(closed.width + 220, 400), height: closed.height + 56)
    }

    public var expanded: CGSize {
        CGSize(width: 560, height: closed.height + 160)
    }
}

/// Concave flare where the notch meets the top edge, and the convex bottom corners.
public struct NotchRadii: Equatable, Sendable {
    public var top: CGFloat
    public var bottom: CGFloat

    public static let closed = NotchRadii(top: 6, bottom: 10)
    public static let compact = NotchRadii(top: 6, bottom: 14)
    public static let peek = NotchRadii(top: 10, bottom: 22)
    public static let expanded = NotchRadii(top: 14, bottom: 32)
}

public enum NotchGeometry {
    /// Simulated notch for displays without one: wide enough to read as a notch, as tall as the menu bar.
    public static let simulatedWidth: CGFloat = 200

    /// The hardware notch is whatever the menu bar can't use between its left and right auxiliary areas.
    public static func hardwareNotchSize(screenWidth: CGFloat, leftAreaWidth: CGFloat, rightAreaWidth: CGFloat,
                                         safeAreaTop: CGFloat) -> CGSize {
        CGSize(width: max(0, screenWidth - leftAreaWidth - rightAreaWidth), height: max(0, safeAreaTop))
    }

    /// Applies the user's width/height tuning without ever going below a usable size.
    public static func tuned(_ size: CGSize, width: Double, height: Double) -> CGSize {
        CGSize(width: max(80, size.width + width), height: max(18, size.height + height))
    }

    /// Canvas frame in screen coordinates: horizontally centered, flush with the top edge.
    public static func canvasFrame(in screenFrame: CGRect, canvas: CGSize = NotchMetrics.canvas) -> CGRect {
        CGRect(x: (screenFrame.midX - canvas.width / 2).rounded(), y: screenFrame.maxY - canvas.height,
               width: canvas.width, height: canvas.height)
    }
}
