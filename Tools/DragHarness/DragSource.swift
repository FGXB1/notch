// Test drag source for the file tray: a small orange window that starts a drag when the mouse is dragged
// on it. Pair it with `notchcmd drag:sim:360,969` (its centre, in top-left screen coordinates), which makes
// Notch post the mouse events. Prints how the drag ended (operation 0 = nobody accepted the drop).
//
//   DragSource <file>            drags the file
//   DragSource --text <string>   drags text, as from a web page
import AppKit

final class SourceView: NSView, NSDraggingSource {
    let writer: any NSPasteboardWriting
    let image: NSImage
    var started = false

    init(frame: NSRect, writer: any NSPasteboardWriting, image: NSImage) {
        self.writer = writer
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard !started else { return }
        started = true
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
        print("source: drag began")
        fflush(stdout)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        print("source: drag ended, operation=\(operation.rawValue) at \(point)")
        fflush(stdout)
        // Stay alive a while, as a real app would: a source quitting while the destination is still tearing
        // the drag down trips a use-after-free in the destination's CoreDrag (HIServices).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}

let arguments = CommandLine.arguments
let writer: any NSPasteboardWriting
let image: NSImage
if arguments.count > 2, arguments[1] == "--text" {
    writer = arguments[2] as NSString
    image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage()
} else if arguments.count > 1 {
    let url = URL(fileURLWithPath: arguments[1])
    writer = url as NSURL
    image = NSWorkspace.shared.icon(forFile: url.path)
} else {
    print("usage: DragSource <file> | DragSource --text <string>")
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 120, height: 120), styleMask: [.borderless],
                      backing: .buffered, defer: false)
window.level = .floating
window.contentView = SourceView(frame: NSRect(x: 0, y: 0, width: 120, height: 120), writer: writer, image: image)
window.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    print("source: timed out")
    exit(1)
}
app.run()
