import AppKit
import CoreImage
import ImageIO
import Observation

/// The desktop picture behind the lock screen, sharp and blurred. Widget backdrops cut their slice out of it,
/// so Frosted and Glass look right even where the window server won't blur what's behind the lock screen.
@MainActor
@Observable
public final class LockWallpaper {
    public private(set) var sharp: NSImage?
    public private(set) var blurred: NSImage?

    @ObservationIgnored private var loadedKey: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public func load(for screen: NSScreen) {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            sharp = nil
            blurred = nil
            loadedKey = nil
            return
        }
        let size = screen.frame.size
        let key = "\(url.path)|\(size.width)x\(size.height)"
        guard key != loadedKey else { return }
        loadedKey = key

        task?.cancel()
        task = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) { Self.render(url: url, longestSide: max(size.width, size.height)) }.value
            guard !Task.isCancelled, let self else { return }
            self.sharp = rendered.map { NSImage(cgImage: $0.sharp, size: .zero) }
            self.blurred = rendered.map { NSImage(cgImage: $0.blurred, size: .zero) }
        }
    }

    /// Decoded at about screen size in points (it's only ever seen through blur or glass), then blurred once.
    nonisolated private static func render(url: URL, longestSide: CGFloat) -> (sharp: CGImage, blurred: CGImage)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sharp = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = CIImage(cgImage: sharp)
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: image.extent)
        guard let blurredImage = CIContext().createCGImage(blurred, from: image.extent) else { return nil }
        return (sharp, blurredImage)
    }
}

/// State the shell drives and the lock-screen view renders.
@MainActor
@Observable
public final class LockScreenModel {
    public var isVisible = false
    /// The screen the widgets are on, and where the panel sits in it (top-left origin), to line up wallpaper.
    public var screenSize: CGSize = .zero
    public var panelOrigin: CGPoint = .zero
    public let wallpaper = LockWallpaper()

    public init() {}
}
