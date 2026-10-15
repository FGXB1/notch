import CoreGraphics
import Testing
@testable import NotchCore

struct WallpaperSamplerTests {
    /// A picture whose top half is `top` and bottom half `bottom` (grey levels 0...1).
    private func image(width: Int, height: Int, top: CGFloat, bottom: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Core Graphics draws bottom-up.
        context.setFillColor(CGColor(gray: bottom, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(gray: top, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return context.makeImage()!
    }

    let screen = CGSize(width: 2056, height: 1329)

    @Test func samplesOnlyTheTopOfThePicture() throws {
        let picture = image(width: 400, height: 260, top: 0.05, bottom: 0.95)
        let value = try #require(WallpaperSampler.luminance(of: picture, in: WallpaperSampler.notchRegion(screenSize: screen),
                                                            screenSize: screen))
        #expect(value < WallpaperSampler.darkThreshold)
    }

    @Test func brightTopReadsLight() throws {
        let picture = image(width: 400, height: 260, top: 0.95, bottom: 0.05)
        let value = try #require(WallpaperSampler.luminance(of: picture, in: WallpaperSampler.notchRegion(screenSize: screen),
                                                            screenSize: screen))
        #expect(value > 0.8)
    }

    @Test func aspectFillCropsTheSidesOfAWidePicture() throws {
        // Twice as wide as the screen's aspect: the sides are cut off, the middle-top is what's under the notch.
        let picture = image(width: 1000, height: 200, top: 0.9, bottom: 0.1)
        let value = try #require(WallpaperSampler.luminance(of: picture, in: WallpaperSampler.notchRegion(screenSize: screen),
                                                            screenSize: screen))
        #expect(value > 0.8)
    }

    @Test func notchRegionIsCentredAtTheTop() {
        let region = WallpaperSampler.notchRegion(screenSize: screen)
        #expect(region.midX == screen.width / 2)
        #expect(region.minY == 0)
    }
}
