// Test drop target for the file tray: a small teal window (centre 400,929 in top-left screen coordinates)
// that accepts any drag and prints what each dropped item carried, to check what other apps would receive.
// Pair it with `notchcmd drag:sim:<tile x>,<tile y>,400,929`.
import AppKit

final class TargetView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .html, .rtf, .png, .tiff,
                                 NSPasteboard.PasteboardType("public.data"),
                                 NSPasteboard.PasteboardType("public.item")])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemTeal.setFill()
        bounds.fill()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let items = sender.draggingPasteboard.pasteboardItems ?? []
        print("target: \(items.count) item(s), source operation mask \(sender.draggingSourceOperationMask.rawValue)")
        for (index, item) in items.enumerated() {
            let path = item.string(forType: .fileURL).flatMap { URL(string: $0)?.path }
            let description = path.map { "file \($0)" } ?? "text \"\(item.string(forType: .string) ?? "-")\""
            print("  item \(index): \(description) types=\(item.types.map(\.rawValue))")
        }
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 200, height: 200), styleMask: [.borderless],
                      backing: .buffered, defer: false)
window.level = .floating
window.contentView = TargetView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
window.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
    print("target: timed out")
    exit(1)
}
app.run()
