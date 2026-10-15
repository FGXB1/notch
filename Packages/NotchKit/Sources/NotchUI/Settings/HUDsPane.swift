import AppKit
import Defaults
import NotchCore
import SwiftUI
import SystemKit

struct HUDsPane: View {
    @Default(.enableVolume) private var enableVolume
    @Default(.enableBrightness) private var enableBrightness
    @Default(.volumeProgressStyle) private var volumeStyle
    @Default(.brightnessProgressStyle) private var brightnessStyle
    @Default(.showVolumePercentage) private var showVolumePercentage
    @Default(.showBrightnessPercentage) private var showBrightnessPercentage
    @Default(.volumeOutputDevice) private var volumeSymbol
    @Default(.showHUDForExternalChanges) private var showExternalChanges
    @Default(.hudDuration) private var duration
    @Default(.hudSpeed) private var speed
    private let hud = HUDController.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(hud.isTrusted ? (hud.isTapActive ? "Allowed" : "Allowed, keys not intercepted") : "Not allowed")
                        if !hud.isTrusted {
                            Button("Allow…", action: hud.requestAccessibility)
                            Button("Open Settings…") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("Notch intercepts the volume and brightness keys to show its own HUD in place of the system's. "
                    + "Hold ⌥ to reach Sound or Displays settings as usual; ⇧⌥ adjusts in finer steps.")
                    .foregroundStyle(.secondary)
            }

            Section("Volume") {
                Toggle("Volume HUD", isOn: $enableVolume)
                Group {
                    stylePicker($volumeStyle)
                    Picker("Icon", selection: $volumeSymbol) {
                        Text("Show symbol").tag(VolumeSymbol.speaker)
                        Text("Show device").tag(VolumeSymbol.device)
                    }
                    Toggle("Show percentage", isOn: $showVolumePercentage)
                    Toggle("Also for changes made in Control Center", isOn: $showExternalChanges)
                }
                .disabled(!enableVolume)
            }

            Section("Brightness") {
                Toggle("Brightness HUD", isOn: $enableBrightness)
                Group {
                    stylePicker($brightnessStyle)
                    Toggle("Show percentage", isOn: $showBrightnessPercentage)
                }
                .disabled(!enableBrightness)
                if !hud.canControlBrightness {
                    Text("Brightness control isn't available on this Mac, so the system HUD stays.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behaviour") {
                LabeledSlider(title: "Duration", value: $duration, range: 0.5...4, format: "%.1f s")
                Picker("Speed", selection: $speed) {
                    Text("Instant").tag(HUDSpeed.instant)
                    Text("Fast").tag(HUDSpeed.fast)
                    Text("Smooth").tag(HUDSpeed.smooth)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("HUDs")
    }

    private func stylePicker(_ selection: Binding<HUDProgressStyle>) -> some View {
        Picker("Style", selection: selection) {
            Text("White").tag(HUDProgressStyle.white)
            Text("Accent").tag(HUDProgressStyle.accent)
            Text("Stylized").tag(HUDProgressStyle.stylized)
        }
    }
}
