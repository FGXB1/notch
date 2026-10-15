import Defaults
import SwiftUI
import SystemKit

struct StatusPane: View {
    @Default(.notifyOnCharging) private var notifyOnCharging
    @Default(.warnOnLowBattery) private var warnOnLowBattery
    @Default(.lowBatteryThreshold) private var lowBatteryThreshold
    @Default(.playSoundOnLowBattery) private var playSoundOnLowBattery
    @Default(.notifyOnLowPowerMode) private var notifyOnLowPowerMode
    @Default(.hideBatteryPercentage) private var hideBatteryPercentage
    @Default(.notifyOnDeviceConnect) private var notifyOnDeviceConnect
    @Default(.warnOnLowConnectBattery) private var warnOnLowConnectBattery
    @Default(.lowConnectBatteryThreshold) private var lowConnectBatteryThreshold
    @Default(.playSoundOnLowConnectBattery) private var playSoundOnLowConnectBattery
    @Default(.notifyOnFocusChange) private var notifyOnFocusChange
    @Default(.replaceWaveformDuringFocus) private var replaceWaveformDuringFocus
    @Default(.playSoundOnSleepFocus) private var playSoundOnSleepFocus
    private let battery = BatteryMonitor.shared
    private let focus = FocusMonitor.shared

    var body: some View {
        Form {
            Section("Battery") {
                if let status = battery.status {
                    LabeledContent("Now", value: "\(Int((status.level * 100).rounded()))%"
                        + (status.isCharging ? " · Charging" : status.isPluggedIn ? " · Plugged in" : "")
                        + (status.isLowPowerMode ? " · Low Power Mode" : ""))
                }
                Toggle("Notify when charging", isOn: $notifyOnCharging)
                Toggle("Low battery alert", isOn: $warnOnLowBattery)
                Group {
                    thresholdPicker("Alert at", $lowBatteryThreshold)
                    Toggle("Play a sound", isOn: $playSoundOnLowBattery)
                }
                .disabled(!warnOnLowBattery)
                Toggle("Notify when Low Power Mode turns on", isOn: $notifyOnLowPowerMode)
                Toggle("Hide percentage", isOn: $hideBatteryPercentage)
            }

            Section("Headphones") {
                Toggle("Notify when connected", isOn: $notifyOnDeviceConnect)
                Toggle("Low battery alert", isOn: $warnOnLowConnectBattery)
                Group {
                    thresholdPicker("Alert at", $lowConnectBatteryThreshold)
                    Toggle("Play a sound", isOn: $playSoundOnLowConnectBattery)
                }
                .disabled(!warnOnLowConnectBattery)
            }

            Section {
                LabeledContent("Now", value: focus.active?.name ?? "Off, or not changed since launch")
                Toggle("Notify on Focus change", isOn: $notifyOnFocusChange)
                Toggle("Show Focus in place of the waveform", isOn: $replaceWaveformDuringFocus)
                Toggle("Sound when Sleep Focus starts", isOn: $playSoundOnSleepFocus)
            } header: {
                Text("Focus")
            } footer: {
                Text("macOS has no public API for Focus; Notch follows the Do Not Disturb service's log, "
                    + "so it learns the current Focus at its first change after launch.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Battery & Devices")
    }

    private func thresholdPicker(_ title: String, _ selection: Binding<Double>) -> some View {
        Picker(title, selection: selection) {
            ForEach([10.0, 15, 20, 30], id: \.self) { Text("\(Int($0))%").tag($0) }
        }
    }
}
