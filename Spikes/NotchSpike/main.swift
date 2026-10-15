// Phase 0 spike: verifies the risky platform assumptions before the real app is built.
//  1. Clicks/hover over the transparent part of the notch canvas reach the apps underneath.
//  2. A private CGS space at absolute level 400 keeps the notch visible on the lock screen.
//  3. A CGEventTap can swallow the volume keys so the system HUD never appears.
//  4. `log stream` exposes Focus mode changes (format is logged for later parsing).
// Everything observed is appended to ~/Library/Logs/NotchSpike.log.

import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI

// MARK: - Logging

enum SpikeLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NotchSpike.log")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message)\n"
        print(line, terminator: "")
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Private CGS spaces

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSpaceCreate") func CGSSpaceCreate(_ cid: Int32, _ flags: Int32, _ options: CFDictionary?) -> UInt64
@_silgen_name("CGSSpaceSetAbsoluteLevel") func CGSSpaceSetAbsoluteLevel(_ cid: Int32, _ space: UInt64, _ level: Int32)
@_silgen_name("CGSAddWindowsToSpaces") func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSShowSpaces") func CGSShowSpaces(_ cid: Int32, _ spaces: CFArray)

final class PrivateSpace {
    let id: UInt64

    init(level: Int32) {
        let cid = CGSMainConnectionID()
        id = CGSSpaceCreate(cid, 1, nil)
        CGSSpaceSetAbsoluteLevel(cid, id, level)
        CGSShowSpaces(cid, [NSNumber(value: id)] as CFArray)
        SpikeLog.write("[space] created private space \(id) at absolute level \(level)")
    }

    func add(_ window: NSWindow) {
        CGSAddWindowsToSpaces(CGSMainConnectionID(), [NSNumber(value: window.windowNumber)] as CFArray,
                              [NSNumber(value: id)] as CFArray)
        SpikeLog.write("[space] added window \(window.windowNumber)")
    }
}

// MARK: - State

@Observable
final class SpikeModel {
    var expanded = false
    var status = "spike ready"
}

// MARK: - Panel

final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        canBecomeVisibleWithoutLogin = true
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // If clicks on the transparent canvas reach this method, click-through failed.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            SpikeLog.write("[click] panel received leftMouseDown at window point \(event.locationInWindow)")
        }
        super.sendEvent(event)
    }
}

final class NoSafeAreaHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
}

struct SpikeView: View {
    @Bindable var model: SpikeModel
    let notch: CGSize

    var body: some View {
        let size = model.expanded ? CGSize(width: 420, height: 150) : notch
        UnevenRoundedRectangle(bottomLeadingRadius: model.expanded ? 28 : 10,
                               bottomTrailingRadius: model.expanded ? 28 : 10)
            .fill(.black)
            .overlay(alignment: .bottom) {
                Text(model.status)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(model.expanded ? 1 : 0)
                    .padding(.bottom, 14)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onHover { inside in
                SpikeLog.write("[hover] notch \(inside ? "entered" : "exited")")
                withAnimation(.spring(duration: 0.35, bounce: inside ? 0.3 : 0.05)) { model.expanded = inside }
            }
            .onTapGesture { SpikeLog.write("[click] notch shape tapped") }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Volume key tap

enum AuxKey: Int {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case illuminationUp = 21, illuminationDown = 22
}

enum SystemVolume {
    static func defaultOutputDevice() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    static func step(by delta: Float32) -> Float32 {
        let device = defaultOutputDevice()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        volume = min(1, max(0, volume + delta))
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
        return volume
    }
}

final class MediaKeyTap {
    private var tap: CFMachPort?
    var onKey: ((AuxKey?, Int) -> Void)?

    func start() {
        let mask: CGEventMask = 0x4C00 // keyDown | keyUp | NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<MediaKeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            let code = (nsEvent.data1 & 0xFFFF0000) >> 16
            let isDown = ((nsEvent.data1 & 0xFF00) >> 8) == 0xA
            let key = AuxKey(rawValue: code)
            if isDown { me.onKey?(key, code) }
            switch key {
            case .soundUp, .soundDown:
                return nil // swallow: the system HUD must not appear
            default:
                return Unmanaged.passUnretained(event)
            }
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            SpikeLog.write("[keys] CGEventTap creation FAILED (Accessibility not granted?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        SpikeLog.write("[keys] event tap installed")
    }
}

// MARK: - Focus log stream

final class FocusLogProbe {
    private let process = Process()
    private var buffer = Data()

    func start() {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--level", "info",
                             "--predicate", "subsystem == \"com.apple.donotdisturb\" AND category != \"Resolver\" AND category != \"BehaviorResolution\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        do {
            try process.run()
            SpikeLog.write("[focus] log stream started (toggle a Focus mode now)")
        } catch {
            SpikeLog.write("[focus] log stream failed: \(error)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = json["eventMessage"] as? String else { continue }
            let category = json["category"] as? String ?? "?"
            let process = (json["processImagePath"] as? String)?.split(separator: "/").last ?? "?"
            SpikeLog.write("[focus] \(process)/\(category): \(message.prefix(400))")
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SpikeModel()
    var panel: NotchPanel?
    var space: PrivateSpace?
    let keys = MediaKeyTap()
    let focus = FocusLogProbe()
    var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SpikeLog.write("===== NotchSpike launched =====")
        let screen = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main!
        let notch: CGSize
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            notch = CGSize(width: 185, height: 32)
        }
        SpikeLog.write("[geometry] screen \(screen.localizedName) frame \(screen.frame) notch \(notch)")

        let canvas = CGSize(width: 760, height: 360)
        let frame = NSRect(x: screen.frame.midX - canvas.width / 2, y: screen.frame.maxY - canvas.height,
                           width: canvas.width, height: canvas.height)
        let panel = NotchPanel(frame: frame)
        panel.contentView = NoSafeAreaHostingView(rootView: SpikeView(model: model, notch: notch))
        panel.orderFrontRegardless()
        self.panel = panel

        let space = PrivateSpace(level: 400)
        space.add(panel)
        self.space = space

        observeLockScreen()
        keys.onKey = { [weak self] key, code in
            guard let self else { return }
            switch key {
            case .soundUp, .soundDown:
                let volume = SystemVolume.step(by: key == .soundUp ? 1 / 16 : -1 / 16)
                SpikeLog.write("[keys] \(key!) swallowed, our volume = \(Int(volume * 100))%")
                self.flash("Volume \(Int(volume * 100))%")
            default:
                SpikeLog.write("[keys] aux key code \(code) (\(key.map { "\($0)" } ?? "unknown")) passed through")
                self.flash("Key \(code)")
            }
        }
        startKeyTapWhenTrusted()
        focus.start()
    }

    private func flash(_ text: String) {
        model.status = text
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { model.expanded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            withAnimation(.spring(duration: 0.35, bounce: 0.05)) { self?.model.expanded = false }
        }
    }

    private func startKeyTapWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            keys.start()
            return
        }
        SpikeLog.write("[keys] waiting for Accessibility permission...")
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.keys.start()
        }
    }

    private func observeLockScreen() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "com.apple.screenLockUIIsShown",
                     "com.apple.screenLockUIIsHidden", "com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
            center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                SpikeLog.write("[lock] \(name)")
                self?.model.status = name.replacingOccurrences(of: "com.apple.", with: "")
                if name == "com.apple.screenIsLocked" {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { self?.model.expanded = true }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
