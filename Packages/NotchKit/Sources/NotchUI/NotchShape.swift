import SwiftUI

/// The notch silhouette: a body hanging from the top edge, with concave flares where it meets the
/// screen edge and convex bottom corners. All four values animate together, so closed → expanded is one
/// continuous morph rather than a resize. The body is centered horizontally in whatever rect it's given.
public struct NotchShape: Shape {
    public var bodySize: CGSize
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(bodySize: CGSize, topRadius: CGFloat, bottomRadius: CGFloat) {
        self.bodySize = bodySize
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(bodySize.width, bodySize.height), AnimatablePair(topRadius, bottomRadius)) }
        set {
            bodySize = CGSize(width: newValue.first.first, height: newValue.first.second)
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let width = max(0, bodySize.width)
        let height = max(0, bodySize.height)
        let flare = min(max(0, topRadius), height / 2)
        let corner = min(max(0, bottomRadius), width / 2, height - flare)

        let left = rect.midX - width / 2
        let right = rect.midX + width / 2
        let top = rect.minY
        let bottom = top + height

        var path = Path()
        path.move(to: CGPoint(x: left - flare, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top + flare), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom - corner))
        path.addQuadCurve(to: CGPoint(x: left + corner, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - corner, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - corner), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: top + flare))
        path.addQuadCurve(to: CGPoint(x: right + flare, y: top), control: CGPoint(x: right, y: top))
        path.closeSubpath()
        return path
    }
}

/// Non-animating hit region: snaps straight to the target size so hover never flaps mid-animation.
struct TopCenteredRect: Shape {
    var size: CGSize

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: size.height))
    }
}
