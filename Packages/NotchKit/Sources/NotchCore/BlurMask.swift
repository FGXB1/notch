import CoreGraphics
import Foundation

/// The fade mask for the blur around the open notch.
public enum BlurMask {
    /// Drawn at this fraction of the view's size; it's all gradient, so the stretch doesn't show.
    public static let scale: CGFloat = 0.5

    /// `size`: the blurred view. `notch`: the open notch's rectangle in the view's coordinates (top-left
    /// origin); it may start above the view, which begins below the menu bar.
    ///
    /// Alpha is 1 on and inside the notch's rounded rectangle and eases to 0 at `reach` away, multiplied by
    /// an ease-in over the view's top `topFade` points so it doesn't start on a hard line. Both are
    /// smoothsteps, so every fade starts and ends with zero slope and leaves no visible boundary.
    public static func make(size: CGSize, notch: CGRect, cornerRadius: CGFloat, reach: CGFloat,
                            topFade: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, reach > 0 else { return nil }

        let radius = min(cornerRadius, notch.width / 2, notch.height / 2)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let y = (CGFloat(row) + 0.5) / scale
            let top = smoothstep(0, topFade, y)
            for column in 0..<width {
                let x = (CGFloat(column) + 0.5) / scale
                let distance = distanceToRoundedRect(x: x - notch.midX, y: y - notch.midY, halfWidth: notch.width / 2,
                                                     halfHeight: notch.height / 2, radius: radius)
                let alpha = (1 - smoothstep(0, reach, distance)) * top
                pixels[(row * width + column) * 4 + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// 0 below `edge0`, 1 above `edge1`, easing in between with zero slope at both ends.
    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Signed distance from a point (relative to the rectangle's centre) to its edge; negative inside.
    static func distanceToRoundedRect(x: CGFloat, y: CGFloat, halfWidth: CGFloat, halfHeight: CGFloat,
                                      radius: CGFloat) -> CGFloat {
        let qx = abs(x) - (halfWidth - radius)
        let qy = abs(y) - (halfHeight - radius)
        return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius
    }
}
