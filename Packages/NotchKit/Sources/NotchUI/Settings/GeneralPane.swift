import AppKit
import Defaults
import NotchCore
import SwiftUI

struct GeneralPane: View {
    @Default(.expandNotchOnHover) private var expandOnHover
    @Default(.hoverDuration) private var hoverDuration
    @Default(.enableHaptics) private var haptics
    @Default(.displayTarget) private var displayTarget
    @Default(.forceSimulatedNotch) private var forceSimulatedNotch
    @Default(.notchAdjustedWidth) private var adjustedWidth
    @Default(.notchAdjustedHeight) private var adjustedHeight
    @Default(.swipeToToggle) private var swipeToToggle
    @Default(.swipeToDismiss) private var swipeToDismiss
    @Default(.swipeToSkip) private var swipeToSkip
    @Default(.swipeToCycleActivity) private var swipeToCycle
    @Default(.naturalMovement) private var naturalMovement
    @Default(.peekDuration) private var peekDuration
    @Default(.hideInFullScreen) private var hideInFullScreen
    @Default(.showHUDsInFullScreen) private var showHUDsInFullScreen
    @Default(.hideFromScreenCapture) private var hideFromScreenCapture
    @Default(.contrastOutline) private var contrastOutline
    @Default(.progressiveBlur) private var progressiveBlur
    private let launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin.isEnabled },
                                                     set: { launchAtLogin.setEnabled($0) }))
                if launchAtLogin.needsApproval {
                    LabeledContent("Turned off in Login Items") {
                        Button("Open Login Items…", action: launchAtLogin.openLoginItemsSettings)
                    }
                }
                // There's no Dock icon or menu bar to quit from.
                LabeledContent("Notch keeps running with no Dock icon") {
                    Button("Quit Notch") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                }
            }
            Section("Behaviour") {
                Toggle("Expand on hover", isOn: $expandOnHover)
                LabeledSlider(title: "Hover duration", value: $hoverDuration, range: 0...1, format: "%.2f s")
                    .disabled(!expandOnHover)
                LabeledSlider(title: "Quick peek duration", value: $peekDuration, range: 1...6, format: "%.1f s")
                Toggle("Haptic feedback", isOn: $haptics)
            }
            Section("Gestures") {
                Toggle("Swipe down to open, up to close", isOn: $swipeToToggle)
                Toggle("Swipe up to dismiss activity", isOn: $swipeToDismiss)
                Toggle("Swipe sideways to skip media", isOn: $swipeToSkip)
                Toggle("Swipe sideways to cycle activities", isOn: $swipeToCycle)
                Toggle("Natural swipe direction", isOn: $naturalMovement)
            }
            Section("Display") {
                Picker("Display on", selection: $displayTarget) {
                    Text("Built-in display").tag(DisplayTarget.builtIn)
                    Text("Main display").tag(DisplayTarget.main)
                    Text("All displays").tag(DisplayTarget.all)
                }
                Toggle("Draw a notch on displays without one", isOn: $forceSimulatedNotch)
                Picker("Contrast outline", selection: $contrastOutline) {
                    Text("Automatic").tag(ContrastOutline.automatic)
                    Text("Always").tag(ContrastOutline.always)
                    Text("Never").tag(ContrastOutline.never)
                }
                Toggle("Blur around the open notch", isOn: $progressiveBlur)
            }
            Section {
                Toggle("Hide in full-screen apps", isOn: $hideInFullScreen)
                Toggle("Still show volume and brightness", isOn: $showHUDsInFullScreen)
                    .disabled(!hideInFullScreen)
                Toggle("Hide from screenshots and recordings", isOn: $hideFromScreenCapture)
            } header: {
                Text("Hiding")
            } footer: {
                Text("Hidden from screenshots, the notch still shows on screen; it just won't appear in captures or screen sharing.")
                    .foregroundStyle(.secondary)
            }
            Section("Tuning") {
                LabeledSlider(title: "Notch width", value: $adjustedWidth, range: -40...40, format: "%+.0f pt")
                LabeledSlider(title: "Notch height", value: $adjustedHeight, range: -10...10, format: "%+.0f pt")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { launchAtLogin.refresh() }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: format, value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}
