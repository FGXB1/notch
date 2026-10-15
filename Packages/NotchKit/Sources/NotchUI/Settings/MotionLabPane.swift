import Defaults
import NotchCore
import SwiftUI

/// Live tuning for every spring the notch uses. Changes apply to the next transition.
struct MotionLabPane: View {
    let actions: SettingsActions
    @Default(.motion) private var motion
    @Default(.slowAnimations) private var slowAnimations

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Preview Open / Close", systemImage: "play.fill", action: actions.togglePreview)
                    Spacer()
                    Toggle("Slow ×5", isOn: $slowAnimations)
                }
            }
            Section("Hover") {
                SpringEditor(title: "Swell", spec: $motion.hoverBump)
                SpringEditor(title: "Settle", spec: $motion.hoverRelease)
            }
            Section("Shell") {
                SpringEditor(title: "Open", spec: $motion.open)
                SpringEditor(title: "Close", spec: $motion.close)
                LabeledSlider(title: "Exit grace", value: $motion.exitGrace, range: 0...0.5, format: "%.2f s")
            }
            Section("Activities & gestures") {
                SpringEditor(title: "Activity change", spec: $motion.activity)
                SpringEditor(title: "Swipe release", spec: $motion.gestureRelease)
            }
            Section("Content") {
                SpringEditor(title: "In", spec: $motion.contentIn)
                LabeledSlider(title: "In delay", value: $motion.contentDelay, range: 0...0.3, format: "%.2f s")
                LabeledSlider(title: "Out duration", value: $motion.contentOutDuration, range: 0.04...0.4,
                              format: "%.2f s")
            }
            Section {
                Button("Reset to Defaults", role: .destructive) { motion = .standard }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Motion Lab")
    }
}

private struct SpringEditor: View {
    let title: String
    @Binding var spec: SpringSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            LabeledSlider(title: "Duration", value: $spec.duration, range: 0.1...1.5, format: "%.2f s")
            LabeledSlider(title: "Bounce", value: $spec.bounce, range: -0.3...0.8, format: "%.2f")
        }
        .padding(.vertical, 2)
    }
}
