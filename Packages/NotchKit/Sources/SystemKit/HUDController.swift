import AppKit
import ApplicationServices
import CoreAudio
import Defaults
import NotchCore
import Observation
import PrivateAPI

/// Replaces the system volume and brightness bezels: the key tap swallows the keys, this applies the
/// change itself (CoreAudio, DisplayServices) and shows the notch HUD instead. Volume changes made
/// elsewhere (Control Center, the menu bar) show the HUD too.
@MainActor
@Observable
public final class HUDController {
    public static let shared = HUDController()

    /// Accessibility granted, so the key tap can exist.
    public private(set) var isTrusted = AXIsProcessTrusted()
    public private(set) var isTapActive = false
    public let canControlBrightness = DisplayServices.isAvailable
    /// Output volume 0...1, kept current for the lock-screen slider.
    public private(set) var volume = Double(SystemVolume.volume())

    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private lazy var tap = MediaKeyTap { [weak self] press in self?.handle(press) ?? false }
    @ObservationIgnored private var trustTask: Task<Void, Never>?
    @ObservationIgnored private var listenedDevice: AudioObjectID?
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    /// Our own writes echo back through the CoreAudio listener; ignore that echo.
    @ObservationIgnored private var ignoreListenerUntil = Date.distantPast
    @ObservationIgnored private var feedbackSound = NSSound(
        contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        byReference: true)

    public init(activities: ActivityCenter = .shared) {
        self.activities = activities
    }

    // MARK: Lifecycle

    public func start() {
        Task { [weak self] in
            for await _ in Defaults.updates([.enableVolume, .enableBrightness]) {
                self?.updateTap()
            }
        }
        listenForVolumeChanges()
    }

    private func updateTap() {
        guard Defaults[.enableVolume] || Defaults[.enableBrightness] else {
            tap.stop()
            isTapActive = false
            return
        }
        isTrusted = AXIsProcessTrusted()
        if isTrusted {
            isTapActive = tap.start()
            Log.system.info("Media key tap \(self.isTapActive ? "installed" : "failed", privacy: .public)")
            return
        }
        if !Defaults[.hasPromptedAccessibility], Defaults[.hasCompletedOnboarding] {
            requestAccessibility()
        } else {
            waitForTrust()
        }
    }

    /// Shows the system's Accessibility prompt (it links to System Settings), then waits for the grant.
    public func requestAccessibility() {
        Defaults[.hasPromptedAccessibility] = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            updateTap()
        } else {
            waitForTrust()
        }
    }

    private func waitForTrust() {
        guard trustTask == nil else { return }
        trustTask = Task { [weak self] in
            while !Task.isCancelled, !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(2))
            }
            self?.trustTask = nil
            self?.updateTap()
        }
    }

    // MARK: Keys

    private func handle(_ press: KeyPress) -> Bool {
        Log.system.debug("Key \(String(describing: press.key), privacy: .public) down=\(press.isDown)")
        let flags = press.flags.intersection([.shift, .option, .command, .control])
        // ⌥ alone opens Sound/Displays settings: that's macOS's job.
        if flags.contains(.option), !flags.contains(.shift) { return false }
        let fine = flags.contains([.shift, .option])

        switch press.key {
        case .soundUp, .soundDown, .mute:
            guard Defaults[.enableVolume], LockMonitor.allows(.allowVolumeWhenLocked),
                  SystemVolume.canSetVolume() else { return false }
            if press.isDown {
                changeVolume(press.key, fine: fine)
            } else if press.key != .mute {
                playFeedback(invert: flags.contains(.shift) && !fine)
            }
            return true
        case .brightnessUp, .brightnessDown:
            guard Defaults[.enableBrightness], LockMonitor.allows(.allowBrightnessWhenLocked),
                  let display = Self.builtInDisplay,
                  DisplayServices.canChangeBrightness(display) else { return false }
            if press.isDown {
                changeBrightness(display, up: press.key == .brightnessUp, fine: fine)
            }
            return true
        case .illuminationUp, .illuminationDown:
            return false
        }
    }

    private func changeVolume(_ key: AuxKey, fine: Bool) {
        let device = SystemVolume.defaultOutputDevice
        var level = SystemVolume.volume(device)
        var muted = SystemVolume.isMuted(device)
        ignoreListenerUntil = .now.addingTimeInterval(0.5)

        if key == .mute {
            muted.toggle()
            SystemVolume.setMuted(muted, device)
        } else {
            level = VolumeStep.next(from: level, up: key == .soundUp, fine: fine)
            SystemVolume.setVolume(level, device)
            if muted {
                muted = false
                SystemVolume.setMuted(false, device)
            }
        }
        showVolume(level: level, muted: muted)
    }

    private func changeBrightness(_ display: CGDirectDisplayID, up: Bool, fine: Bool) {
        guard let current = DisplayServices.brightness(display) else { return }
        let level = VolumeStep.next(from: current, up: up, fine: fine)
        DisplayServices.setBrightness(level, for: display)
        activities.showHUD(.brightness, level: Double(level), showsPercentage: Defaults[.showBrightnessPercentage])
    }

    /// From a slider (the lock-screen widget): no HUD, the slider is the feedback.
    public func setVolume(_ level: Double) {
        ignoreListenerUntil = .now.addingTimeInterval(0.5)
        let device = SystemVolume.defaultOutputDevice
        SystemVolume.setVolume(Float(level), device)
        if SystemVolume.isMuted(device), level > 0 {
            SystemVolume.setMuted(false, device)
        }
        volume = level
    }

    private func showVolume(level: Float, muted: Bool) {
        volume = Double(level)
        var symbol: String?
        if Defaults[.volumeOutputDevice] == .device {
            let output = SystemVolume.output
            symbol = OutputSymbol.bluetoothAddress(fromUID: output.uid).flatMap(DeviceMonitor.symbol(forAddress:))
                ?? OutputSymbol.symbol(name: output.name, transport: output.transport)
        }
        activities.showHUD(.volume, level: Double(level), isMuted: muted || level == 0, symbol: symbol,
                           showsPercentage: Defaults[.showVolumePercentage])
    }

    /// The "pop" macOS plays on release when "Play feedback when volume is changed" is on; ⇧ inverts it.
    private func playFeedback(invert: Bool) {
        let enabled = UserDefaults.standard.bool(forKey: "com.apple.sound.beep.feedback")
        guard enabled != invert, let feedbackSound else { return }
        feedbackSound.stop()
        feedbackSound.play()
    }

    private static var builtInDisplay: CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0 }
    }

    // MARK: External changes

    private func listenForVolumeChanges() {
        let defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachDeviceListener() }
        }
        var address = SystemVolume.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main,
                                            defaultDeviceListener)
        self.defaultDeviceListener = defaultDeviceListener
        attachDeviceListener()
    }

    /// Volume and mute listeners follow the default output device.
    private func attachDeviceListener() {
        if let device = listenedDevice, let listener = deviceListener {
            var volume = SystemVolume.volumeAddress
            var mute = SystemVolume.muteAddress
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, listener)
        }
        let device = SystemVolume.defaultOutputDevice
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeChangedElsewhere() }
        }
        var volume = SystemVolume.volumeAddress
        var mute = SystemVolume.muteAddress
        AudioObjectAddPropertyListenerBlock(device, &volume, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener)
        listenedDevice = device
        deviceListener = listener
        self.volume = Double(SystemVolume.volume(device))
    }

    private func volumeChangedElsewhere() {
        let device = SystemVolume.defaultOutputDevice
        let level = SystemVolume.volume(device)
        volume = Double(level)
        // Without the tap the system bezel is showing already; don't stack a second HUD under it.
        guard Defaults[.showHUDForExternalChanges], Defaults[.enableVolume], isTapActive,
              LockMonitor.allows(.allowVolumeWhenLocked), Date() > ignoreListenerUntil else { return }
        showVolume(level: level, muted: SystemVolume.isMuted(device))
    }
}
