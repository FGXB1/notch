import CoreGraphics
import Foundation
import ImageIO

/// How bright the desktop picture is under the notch, for deciding whether the black notch needs an outline.
public enum WallpaperSampler {
    /// Below this the backdrop counts as dark (0 black ... 1 white).
    public static let darkThreshold = 0.3

    /// The area the open notch covers, in points from the screen's top-left.
    public static func notchRegion(screenSize: CGSize) -> CGRect {
        let width = min(screenSize.width, 640)
        return CGRect(x: (screenSize.width - width) / 2, y: 0, width: width, height: min(screenSize.height, 220))
    }

    /// Mean luminance of `image` inside `region` of a screen of `screenSize`, with the image laid out
    /// aspect-fill the way the desktop draws it. Nil if the region misses the image.
    public static func luminance(of image: CGImage, in region: CGRect, screenSize: CGSize) -> Double? {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0, screenSize.width > 0, screenSize.height > 0 else {
            return nil
        }
        let scale = max(screenSize.width / imageSize.width, screenSize.height / imageSize.height)
        let offset = CGPoint(x: (imageSize.width * scale - screenSize.width) / 2,
                             y: (imageSize.height * scale - screenSize.height) / 2)
        let pixels = CGRect(x: (region.minX + offset.x) / scale, y: (region.minY + offset.y) / scale,
                            width: region.width / scale, height: region.height / scale)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard !pixels.isEmpty, let cropped = image.cropping(to: pixels) else { return nil }
        return meanLuminance(cropped)
    }

    /// Loads the picture small (only the average matters) and samples the notch's region.
    public static func luminance(ofImageAt url: URL, screenSize: CGSize) -> Double? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return luminance(of: image, in: notchRegion(screenSize: screenSize), screenSize: screenSize)
    }

    /// Averages by drawing into a small bitmap and reading it back.
    private static func meanLuminance(_ image: CGImage) -> Double? {
        let side = 16
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let red = Double(bytes[pixel]) / 255
            let green = Double(bytes[pixel + 1]) / 255
            let blue = Double(bytes[pixel + 2]) / 255
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return total / Double(side * side)
    }
}
