import Defaults
import NotchCore
import SwiftUI

struct LockScreenPane: View {
    let actions: SettingsActions

    @Default(.enableLockScreen) private var enabled
    @Default(.allowNowPlayingWidgetWhenLocked) private var nowPlayingWidget
    @Default(.allowBatteryWidgetWhenLocked) private var batteryWidget
    @Default(.allowConnectivityWidgetWhenLocked) private var headphonesWidget
    @Default(.allowFocusWidgetWhenLocked) private var focusWidget
    @Default(.allowCalendarWidgetWhenLocked) private var calendarWidget
    @Default(.lockScreenWidgetStyle) private var style
    @Default(.showVolumeControl) private var showVolumeControl
    @Default(.nowPlayingWidgetOffset) private var offset
    @Default(.showLockIndicator) private var showLockIndicator
    @Default(.allowVolumeWhenLocked) private var allowVolume
    @Default(.allowBrightnessWhenLocked) private var allowBrightness
    @Default(.allowBatteryWhenLocked) private var allowBattery
    @Default(.allowConnectivityWhenLocked) private var allowConnectivity
    @Default(.allowFocusWhenLocked) private var allowFocus
    @Default(.playSoundOnLock) private var playSoundOnLock
    @Default(.playSoundOnUnlock) private var playSoundOnUnlock
    @Default(.keepAwake) private var keepAwake
    @Default(.showOnScreenSaver) private var showOnScreenSaver

    var body: some View {
        Form {
            Section {
                Toggle("Lock Screen", isOn: $enabled)
                LabeledContent("Preview") {
                    Button("Show Widgets", systemImage: "eye", action: actions.previewLockScreen)
                }
            } footer: {
                Text("Lock with ⌃⌘Q to see the real thing. Preview shows the widgets on the desktop for 8 seconds.")
                    .foregroundStyle(.secondary)
            }

            Section("Widgets") {
                Toggle("Now Playing", isOn: $nowPlayingWidget)
                Toggle("Battery", isOn: $batteryWidget)
                Toggle("Headphones", isOn: $headphonesWidget)
                Toggle("Focus", isOn: $focusWidget)
                Toggle("Next event", isOn: $calendarWidget)
            }
            .disabled(!enabled)

            Section("Appearance") {
                Picker("Style", selection: $style) {
                    Text("Frosted").tag(LockWidgetStyle.frosted)
                    Text("Glass").tag(LockWidgetStyle.glass)
                    Text("Clear").tag(LockWidgetStyle.clear)
                }
                Toggle("Volume slider", isOn: $showVolumeControl)
                LabeledSlider(title: "Vertical offset", value: $offset, range: -200...200, format: "%+.0f pt")
            }
            .disabled(!enabled)

            Section("In the notch while locked") {
                Toggle("Show lock indicator", isOn: $showLockIndicator)
                Toggle("Volume HUD", isOn: $allowVolume)
                Toggle("Brightness HUD", isOn: $allowBrightness)
                Toggle("Battery alerts", isOn: $allowBattery)
                Toggle("Headphone alerts", isOn: $allowConnectivity)
                Toggle("Focus alerts", isOn: $allowFocus)
            }

            Section("Behaviour") {
                Toggle("Sound on lock", isOn: $playSoundOnLock)
                Toggle("Sound on unlock", isOn: $playSoundOnUnlock)
                Toggle("Keep awake while music plays", isOn: $keepAwake)
                Toggle("Show over the screen saver", isOn: $showOnScreenSaver)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lock Screen")
    }
}
