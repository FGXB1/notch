import CoreGraphics
import Foundation
import Testing
@testable import NotchCore

struct BlurMaskTests {
    // The open notch is 560 x 196 with a 37 pt menu bar; the view starts below the menu bar and reaches
    // 60 pt past the notch on the sides and bottom.
    let reach: CGFloat = 60
    let menuBar: CGFloat = 37
    var size: CGSize { CGSize(width: 560 + 2 * reach, height: 196 - menuBar + reach) }
    var notch: CGRect { CGRect(x: reach, y: -menuBar, width: 560, height: 196) }

    private func mask() throws -> CGImage {
        try #require(BlurMask.make(size: size, notch: notch, cornerRadius: 32, reach: reach, topFade: 20))
    }

    /// Alpha (0...255) at a point in view coordinates (top-left origin).
    private func alpha(_ image: CGImage, x: CGFloat, y: CGFloat) -> UInt8 {
        let data = image.dataProvider!.data! as Data
        let px = min(image.width - 1, Int(x * BlurMask.scale))
        let py = min(image.height - 1, Int(y * BlurMask.scale))
        return data[py * image.bytesPerRow + px * 4 + 3]
    }

    @Test func fullUnderTheNotchAndGoneAtTheEdges() throws {
        let image = try mask()
        // Just inside the notch's bottom edge.
        #expect(alpha(image, x: size.width / 2, y: notch.maxY - 2) >= 250)
        // The bottom row and the bottom corners.
        #expect(alpha(image, x: size.width / 2, y: size.height - 1) <= 2)
        #expect(alpha(image, x: 0, y: size.height - 1) == 0)
    }

    @Test func halfwayIsHalfStrength() throws {
        let value = alpha(try mask(), x: size.width / 2, y: notch.maxY + reach / 2)
        #expect((110...145).contains(value))
    }

    @Test func easesInBelowTheMenuBar() throws {
        let image = try mask()
        let besideNotch = notch.maxX + 10
        // The view's top row, right under the menu bar: nothing yet.
        #expect(alpha(image, x: besideNotch, y: 0) <= 2)
        // Further down beside the notch: blurred.
        #expect(alpha(image, x: besideNotch, y: 80) > 150)
    }

    @Test func fadesTheSameDistanceAroundTheCorners() {
        let straight = BlurMask.distanceToRoundedRect(x: 0, y: 128, halfWidth: 280, halfHeight: 98, radius: 32)
        let offset = 30 / sqrt(2.0)
        let diagonal = BlurMask.distanceToRoundedRect(x: 280 - 32 + 32 / sqrt(2.0) + offset,
                                                      y: 98 - 32 + 32 / sqrt(2.0) + offset,
                                                      halfWidth: 280, halfHeight: 98, radius: 32)
        #expect(abs(straight - 30) < 0.01)
        #expect(abs(diagonal - 30) < 0.01)
    }
}
