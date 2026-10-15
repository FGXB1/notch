import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Accent color pulled from album art, tuned to read well on the notch's black background.
public struct ArtworkPalette: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let neutral = ArtworkPalette(red: 1, green: 1, blue: 1)

    public var accent: Color { Color(red: red, green: green, blue: blue) }
}

/// Decoded artwork plus its palette. Produced off the main thread.
struct DecodedArtwork: @unchecked Sendable {
    let image: CGImage
    let palette: ArtworkPalette

    /// Decodes base64 artwork at display size (never full resolution) and extracts its accent color.
    static func decode(base64: String) -> DecodedArtwork? {
        guard let data = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return DecodedArtwork(image: image, palette: accent(of: image))
    }

    /// Vibrance-weighted average of a 24×24 downsample: saturated, mid-bright pixels dominate, so a muted
    /// background doesn't drown out the artwork's actual color.
    static func accent(of image: CGImage) -> ArtworkPalette {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .neutral }

        var total = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            let weight = 0.05 + saturation * saturation * (1 - abs(maxC - 0.65))
            total = (total.r + r * weight, total.g + g * weight, total.b + b * weight, total.weight + weight)
        }
        guard total.weight > 0 else { return .neutral }
        return readable(r: total.r / total.weight, g: total.g / total.weight, b: total.b / total.weight)
    }

    /// Lifts dark colors and tames neon ones so the accent stays legible on black.
    static func readable(r: Double, g: Double, b: Double) -> ArtworkPalette {
        let maxC = max(r, g, b), minC = min(r, g, b)
        var saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
        let brightness = max(maxC, 0.82)
        saturation = min(saturation, 0.7)
        guard maxC > 0, maxC != minC else {
            return ArtworkPalette(red: brightness, green: brightness, blue: brightness)
        }
        // Rebuild the color from its hue with the adjusted saturation/brightness.
        let scale = { (channel: Double) in
            let normalized = (channel - minC) / (maxC - minC) // 0...1 position between min and max
            return brightness * (1 - saturation * (1 - normalized))
        }
        return ArtworkPalette(red: scale(r), green: scale(g), blue: scale(b))
    }
}
