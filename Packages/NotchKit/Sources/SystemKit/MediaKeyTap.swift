import AppKit
import CoreGraphics

/// Special keys delivered as NX_SYSDEFINED (subtype 8) events; the code sits in the high half of `data1`.
enum AuxKey: Int {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case illuminationUp = 21
    case illuminationDown = 22
}

struct KeyPress {
    var key: AuxKey
    var isDown: Bool
    var isRepeat: Bool
    var flags: NSEvent.ModifierFlags
}

/// A session event tap for the media keys. Swallowing an event (returning nil) is what keeps the system's
/// own bezel from appearing. Needs Accessibility; the tap only asks for NX_SYSDEFINED, so ordinary typing
/// never passes through it.
@MainActor
final class MediaKeyTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Return true to swallow the event.
    private let handler: (KeyPress) -> Bool

    init(handler: @escaping (KeyPress) -> Bool) {
        self.handler = handler
    }

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            // The run-loop source is on the main run loop, so the callback is already on the main thread.
            let swallow = MainActor.assumeIsolated { owner.shouldSwallow(type: type, event: event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << 14), callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    private func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS disables taps that answer slowly; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return false
        }
        let data = nsEvent.data1
        let state = (data & 0xFF00) >> 8
        guard let key = AuxKey(rawValue: (data & 0xFFFF_0000) >> 16), state == 0xA || state == 0xB else { return false }
        return handler(KeyPress(key: key, isDown: state == 0xA, isRepeat: data & 0x1 != 0, flags: nsEvent.modifierFlags))
    }
}
