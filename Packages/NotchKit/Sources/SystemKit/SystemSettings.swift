import Defaults

/// What the volume HUD shows on its left.
public enum VolumeSymbol: String, CaseIterable, Sendable, Defaults.Serializable {
    /// The speaker, filling with the level.
    case speaker
    /// The output device: AirPods, headphones, a display...
    case device
}

public extension Defaults.Keys {
    // HUDs (replacing the system's volume and brightness bezels)
    static let enableVolume = Key<Bool>("enableVolume", default: true)
    static let enableBrightness = Key<Bool>("enableBrightness", default: true)
    static let volumeOutputDevice = Key<VolumeSymbol>("volumeOutputDevice", default: .speaker)
    /// Also show the HUD when the volume changes elsewhere (Control Center, the menu bar, another app).
    static let showHUDForExternalChanges = Key<Bool>("showHUDForExternalChanges", default: true)
    static let hasPromptedAccessibility = Key<Bool>("hasPromptedAccessibility", default: false)

    // Battery
    static let notifyOnCharging = Key<Bool>("notifyOnCharging", default: true)
    static let warnOnLowBattery = Key<Bool>("warnOnLowBattery", default: true)
    /// Percent.
    static let lowBatteryThreshold = Key<Double>("lowBatteryThreshold", default: 20)
    static let playSoundOnLowBattery = Key<Bool>("playSoundOnLowBattery", default: false)
    static let notifyOnLowPowerMode = Key<Bool>("notifyOnLowPowerMode", default: true)
    static let hideBatteryPercentage = Key<Bool>("hideBatteryPercentage", default: false)

    // Headphones
    static let notifyOnDeviceConnect = Key<Bool>("notifyOnDeviceConnect", default: true)
    static let warnOnLowConnectBattery = Key<Bool>("warnOnLowConnectBattery", default: true)
    /// Percent.
    static let lowConnectBatteryThreshold = Key<Double>("lowConnectBatteryThreshold", default: 20)
    static let playSoundOnLowConnectBattery = Key<Bool>("playSoundOnLowConnectBattery", default: false)

    // Focus
    static let notifyOnFocusChange = Key<Bool>("notifyOnFocusChange", default: true)
    /// While a Focus is on, the music wings show its symbol instead of the waveform.
    static let replaceWaveformDuringFocus = Key<Bool>("replaceWaveformDuringFocus", default: false)
    static let playSoundOnSleepFocus = Key<Bool>("playSoundOnSleepFocus", default: false)
}
