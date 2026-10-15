import AppKit
import NotchCore
import QuickLookThumbnailing
import Quartz

/// What can be done with tray files. Anything that shows a window activates Notch first: it's a
/// background app, and its panels would otherwise open behind the frontmost app.
@MainActor
public enum FileActions {
    public static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Text and links copy as themselves, everything else as files (see `TrayItem.pasteboardWriter`).
    public static func copy(_ items: [TrayItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map(\.pasteboardWriter))
    }

    public static var canAirDrop: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    /// The system's own AirDrop icon (there's no SF Symbol for it).
    public static var airDropIcon: NSImage? {
        NSSharingService(named: .sendViaAirDrop)?.image
    }

    /// The files among dropped items (AirDrop only sends files).
    public static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            switch await DropContent.load(from: provider) {
            case let .file(url), let .copiedFile(url): urls.append(url)
            default: break
            }
        }
        return urls
    }

    public static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }
}

public extension TrayItem {
    /// What goes on the pasteboard when this item is dragged or copied. Files go as a file URL only, the
    /// way Finder does it, so apps receive the file itself (Messages attaches it) rather than its contents
    /// (an `NSItemProvider(contentsOf:)` leads with the data: an .html file arrived as a page of markup).
    /// Dropped text and links go back out as text and as the link, so they paste the way they came in.
    @MainActor var pasteboardWriter: any NSPasteboardWriting {
        switch kind {
        case .text:
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text as NSString }
        case .link:
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let string = plist["URL"] as? String, let link = URL(string: string) {
                return link as NSURL
            }
        case .file, .copiedFile, .image:
            break
        }
        return url as NSURL
    }
}

/// Dragging tray items into other apps, as Finder drags files (see `TrayItem.pasteboardWriter`).
@MainActor
public enum TrayDrag {
    /// Starts the drag from the mouse-drag event being handled. False if there isn't one.
    @discardableResult
    public static func begin(_ trayItems: [TrayItem]) -> Bool {
        guard !trayItems.isEmpty, let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView else { return false }

        let point = view.convert(event.locationInWindow, from: nil)
        let side: CGFloat = 54
        let items = trayItems.enumerated().map { index, trayItem in
            let url = trayItem.url
            let item = NSDraggingItem(pasteboardWriter: trayItem.pasteboardWriter)
            let image = Thumbnails.shared.cached(for: url) ?? NSWorkspace.shared.icon(forFile: url.path)
            // A slight fan, so several files read as a pile under the pointer.
            let fan = CGFloat(min(index, 3)) * 5
            item.setDraggingFrame(NSRect(x: point.x - side / 2 + fan, y: point.y - side / 2 + fan,
                                         width: side, height: side), contents: image)
            return item
        }
        let session = view.beginDraggingSession(with: items, event: event, source: Source.shared)
        session.draggingFormation = trayItems.count > 1 ? .pile : .none
        session.animatesToStartingPositionsOnCancelOrFail = true
        Log.tray.info("Tray: dragging out \(trayItems.count) item(s)")
        return true
    }

    @MainActor private final class Source: NSObject, NSDraggingSource {
        static let shared = Source()

        /// Copy, never move: dropping in a folder duplicates the file rather than taking the original away.
        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .generic]
        }
    }
}

/// Thumbnails for tray tiles, made by Quick Look (the same images Finder shows) and cached per file version.
@MainActor
public final class Thumbnails {
    public static let shared = Thumbnails()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // Small images (54 pt), but a tray can hold a lot over a long session.
        cache.countLimit = 300
        return cache
    }()

    public func cached(for url: URL) -> NSImage? {
        cache.object(forKey: Self.key(for: url))
    }

    public func thumbnail(for url: URL, side: CGFloat) async -> NSImage {
        let key = Self.key(for: url)
        if let cached = cache.object(forKey: key) { return cached }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: .all)
        let image: NSImage
        if let cgImage = await Self.generate(request) {
            image = NSImage(cgImage: cgImage, size: CGSize(width: CGFloat(cgImage.width) / scale,
                                                           height: CGFloat(cgImage.height) / scale))
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private nonisolated static func generate(_ request: QLThumbnailGenerator.Request) async -> CGImage? {
        try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }

    /// Path plus modification date, so an edited file gets a new thumbnail.
    private static func key(for url: URL) -> NSString {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)" as NSString
    }
}

/// The system Quick Look panel for tray files. Notch's app delegate forwards the panel-controller calls
/// here (QLPreviewPanel looks for a controller up the responder chain, which ends at the app delegate).
@MainActor
public final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLook()

    private var urls: [URL] = []
    private var index = 0

    /// Opens the panel on `urls[index]`, or closes it if it's already showing that file.
    public func toggle(_ urls: [URL], index: Int) {
        guard let panel = QLPreviewPanel.shared(), urls.indices.contains(index) else { return }
        if panel.isVisible, self.urls == urls, panel.currentPreviewItemIndex == index {
            panel.orderOut(nil)
            return
        }
        self.urls = urls
        self.index = index
        NSApp.activate()
        if panel.isVisible {
            panel.reloadData()
            panel.currentPreviewItemIndex = index
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Controller (forwarded from the app delegate)

    public func beginControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = index
    }

    public func endControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: QLPreviewPanelDataSource

    public nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    public nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
