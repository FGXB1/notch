// Draws the layers of Notch's app icon and writes App/AppIcon.icon, an Icon Composer document that Xcode
// compiles into the app (open it in Icon Composer to fine-tune the glass). Run from the repo root:
//
//   swift Tools/AppIcon/make-icon.swift
//
// The icon: the open notch hanging from the top edge with a live waveform inside, over the soft glow of
// album art. Every layer is a full 1024-point canvas so Icon Composer needs no positioning.

import AppKit
import CoreImage

let side: CGFloat = 1024
let center = side / 2

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A transparent canvas with a top-left origin, like the icon's own coordinates.
func render(_ draw: (CGContext) -> Void) -> CGImage {
    let context = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)
    draw(context)
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: Layers

/// The open notch: flared into the top edge, rounded at the bottom.
func notchPath() -> CGPath {
    let width: CGFloat = 600, height: CGFloat = 252, flare: CGFloat = 40, radius: CGFloat = 118
    let left = center - width / 2, right = center + width / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left - flare, y: -20))
    path.addLine(to: CGPoint(x: left - flare, y: 0))
    path.addQuadCurve(to: CGPoint(x: left, y: flare), control: CGPoint(x: left, y: 0))
    path.addLine(to: CGPoint(x: left, y: height - radius))
    path.addArc(tangent1End: CGPoint(x: left, y: height), tangent2End: CGPoint(x: left + radius, y: height),
                radius: radius)
    path.addLine(to: CGPoint(x: right - radius, y: height))
    path.addArc(tangent1End: CGPoint(x: right, y: height), tangent2End: CGPoint(x: right, y: height - radius),
                radius: radius)
    path.addLine(to: CGPoint(x: right, y: flare))
    path.addQuadCurve(to: CGPoint(x: right + flare, y: 0), control: CGPoint(x: right, y: 0))
    path.addLine(to: CGPoint(x: right + flare, y: -20))
    path.closeSubpath()
    return path
}

let notch = render { context in
    context.addPath(notchPath())
    context.setFillColor(color(0x000000))
    context.fillPath()
}

/// Five rounded bars, coral to violet, centred in the notch.
let bars = render { context in
    let heights: [CGFloat] = [64, 122, 164, 108, 72]
    let width: CGFloat = 34, gap: CGFloat = 24, midline: CGFloat = 128
    let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
    let path = CGMutablePath()
    for (index, height) in heights.enumerated() {
        let x = center - total / 2 + CGFloat(index) * (width + gap)
        path.addRoundedRect(in: CGRect(x: x, y: midline - height / 2, width: width, height: height),
                            cornerWidth: width / 2, cornerHeight: width / 2)
    }
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0xFF8A6B), color(0xFF5C93), color(0xA77BFF)] as CFArray,
                              locations: [0, 0.5, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: center - total / 2, y: 0),
                               end: CGPoint(x: center + total / 2, y: 0), options: [])
}

/// Album-art glow spilling out from under the notch, fading to dark at the bottom.
let glow: CGImage = {
    let blobs = render { context in
        for (x, y, radius, hex, alpha) in [(360.0, 430.0, 230.0, 0xFF4F6D as UInt32, 1.0),
                                           (670.0, 450.0, 220.0, 0xFFA94D, 0.95),
                                           (512.0, 330.0, 250.0, 0x8A5CFF, 1.0)] {
            context.setFillColor(color(hex, alpha))
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
        }
    }
    let input = CIImage(cgImage: blobs).clampedToExtent()
    let blurred = input.applyingGaussianBlur(sigma: 95).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    return CIContext().createCGImage(blurred, from: blurred.extent, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
}()

// MARK: Document

let document = URL(fileURLWithPath: "App/AppIcon.icon")
let assets = document.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: document)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
write(bars, to: assets.appendingPathComponent("bars.png"))
write(notch, to: assets.appendingPathComponent("notch.png"))
write(glow, to: assets.appendingPathComponent("glow.png"))

// Groups run front to back.
let json = """
{
  "fill" : {
    "linear-gradient" : [
      "srgb:0.11765,0.09020,0.20000,1.00000",
      "srgb:0.03529,0.03137,0.06275,1.00000"
    ],
    "orientation" : {
      "start" : { "x" : 0.5, "y" : 0 },
      "stop" : { "x" : 0.5, "y" : 1 }
    }
  },
  "groups" : [
    {
      "layers" : [ { "image-name" : "bars.png", "name" : "bars", "glass" : false } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "translucency" : { "enabled" : false, "value" : 0 }
    },
    {
      "layers" : [ { "image-name" : "notch.png", "name" : "notch", "glass" : true } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.6 },
      "translucency" : { "enabled" : false, "value" : 0 }
    },
    {
      "layers" : [ { "image-name" : "glow.png", "name" : "glow", "glass" : false } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : {
    "squares" : [ "macOS" ]
  }
}
"""
try! json.write(to: document.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(document.path)")
