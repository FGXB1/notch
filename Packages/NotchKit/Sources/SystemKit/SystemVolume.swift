import AudioToolbox
import CoreAudio
import Foundation

/// The default output device's volume and mute, through CoreAudio's "virtual main volume" (the same
/// control the volume keys and the menu bar slider drive).
enum SystemVolume {
    struct Output: Equatable {
        var device: AudioObjectID
        var name: String
        var uid: String
        var transport: UInt32
    }

    static var defaultOutputDevice: AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    static var output: Output {
        let device = defaultOutputDevice
        var name: Unmanaged<CFString>?
        var nameAddress = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)

        var uid: Unmanaged<CFString>?
        var uidAddress = address(kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal)
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid)

        var transport: UInt32 = 0
        var transportAddress = address(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transport)

        return Output(device: device, name: name?.takeRetainedValue() as String? ?? "",
                      uid: uid?.takeRetainedValue() as String? ?? "", transport: transport)
    }

    /// Some outputs (HDMI to a TV, most displays) have no software volume; the keys must then reach macOS,
    /// which shows its own "not available" bezel.
    static func canSetVolume(_ device: AudioObjectID = defaultOutputDevice) -> Bool {
        var address = volumeAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    static func volume(_ device: AudioObjectID = defaultOutputDevice) -> Float {
        var address = volumeAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    static func setVolume(_ value: Float, _ device: AudioObjectID = defaultOutputDevice) {
        var address = volumeAddress
        var value = min(1, max(0, value))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func isMuted(_ device: AudioObjectID = defaultOutputDevice) -> Bool {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value != 0
    }

    static func setMuted(_ muted: Bool, _ device: AudioObjectID = defaultOutputDevice) {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: Addresses

    static var volumeAddress: AudioObjectPropertyAddress {
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    }

    static var muteAddress: AudioObjectPropertyAddress {
        address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }

    static var defaultOutputAddress: AudioObjectPropertyAddress {
        address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

/// Pure stepping rules, matching the keys' behaviour in macOS.
public enum VolumeStep {
    /// 16 steps per key press, 64 with ⇧⌥ held. Snaps onto the grid first, so a level set elsewhere
    /// (e.g. 0.37) lands on a step instead of keeping its odd offset forever.
    public static func next(from level: Float, up: Bool, fine: Bool) -> Float {
        let steps: Float = fine ? 64 : 16
        let current = (level * steps).rounded()
        return min(1, max(0, (current + (up ? 1 : -1)) / steps))
    }
}

/// A symbol for the output device, for the HUD's "Show device" style.
public enum OutputSymbol {
    /// Bluetooth output UIDs start with the device address: "68-3E-C0-AF-8B-3B:output".
    public static func bluetoothAddress(fromUID uid: String) -> String? {
        let candidate = String(uid.prefix(17))
        return candidate.wholeMatch(of: #/([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}/#) != nil ? candidate : nil
    }

    public static func symbol(name: String, transport: UInt32) -> String {
        if let symbol = DeviceSymbol.symbol(name: name) { return symbol }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}
