import Activities
import CalendarKit
import Defaults
import NotchCore
import SwiftUI

/// Drives the activity system by hand, so animations and arbitration can be tested before real
/// integrations exist.
struct PlaygroundPane: View {
    private let center = ActivityCenter.shared
    private static let symbols = ["timer", "figure.run", "flame.fill", "leaf.fill", "bolt.fill", "star.fill"]
    @State private var nextSymbol = 0
    @State private var volume = 0.5

    var body: some View {
        Form {
            Section("Live activities") {
                LabeledContent("Live", value: center.visibleLive.isEmpty ? "None"
                    : center.visibleLive.map { $0.id.placeholderSymbol }.joined(separator: ", "))
                HStack {
                    Button("Start Activity", systemImage: "plus") {
                        center.upsert(.demo(symbol: Self.symbols[nextSymbol % Self.symbols.count]))
                        nextSymbol += 1
                    }
                    Button("End Current", systemImage: "minus") {
                        if case let .compact(activity) = center.display { center.end(activity.id) }
                    }
                    Button("End All", systemImage: "xmark") {
                        center.visibleLive.forEach { center.end($0.id) }
                    }
                }
                HStack {
                    Button("Cycle", systemImage: "arrow.triangle.2.circlepath") { center.cycle() }
                    Button("Dismiss", systemImage: "chevron.up") { center.dismissCurrent() }
                    Button("Restore", systemImage: "chevron.down") { center.restoreDismissed() }
                }
            }
            Section("Quick peek") {
                Button("Post Notification", systemImage: "bell.badge") {
                    center.post(.demo(symbol: "bell.fill", title: "Design review in 5 min",
                                      subtitle: "Room 4 · Zoom link attached"))
                }
            }
            Section {
                HStack {
                    Button("Starting Soon", systemImage: "video") { CalendarController.shared.addDemoEvent(.startingSoon) }
                    Button("In Progress", systemImage: "timer") { CalendarController.shared.addDemoEvent(.inProgress) }
                    Button("Time to Leave", systemImage: "car") { CalendarController.shared.addDemoEvent(.timeToLeave) }
                    Button("Clear", systemImage: "xmark") { CalendarController.shared.clearDemoEvents() }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Adds pretend events alongside your real ones (they never touch your calendar). "
                    + "Starting Soon peeks in about a minute, then again at its start. "
                    + "Time to Leave uses your location and peeks in about a minute.")
                    .foregroundStyle(.secondary)
            }
            Section("Status") {
                HStack {
                    Button("Charging", systemImage: "bolt") {
                        center.post(.battery(level: 0.76, isCharging: true, event: .charging))
                    }
                    Button("Low Battery", systemImage: "battery.25percent") {
                        center.post(.battery(level: 0.12, isCharging: false, event: .low))
                    }
                    Button("Low Power", systemImage: "leaf") {
                        center.post(.battery(level: 0.48, isCharging: false, event: .lowPowerMode))
                    }
                }
                HStack {
                    Button("AirPods", systemImage: "airpods.pro") {
                        center.post(.device(name: "AirPods Pro", symbol: "airpods.pro", battery: 0.8, event: .connected))
                    }
                    Button("Focus On", systemImage: "moon") {
                        center.post(.focus(name: "Do Not Disturb", symbol: "moon.fill", tint: "indigo", isOn: true))
                    }
                    Button("Focus Off", systemImage: "moon.zzz") {
                        center.post(.focus(name: "Do Not Disturb", symbol: "moon.fill", tint: "indigo", isOn: false))
                    }
                }
            }
            Section("HUD") {
                HStack {
                    Button("Volume Down", systemImage: "speaker.wave.1") { stepVolume(-1 / 16) }
                    Button("Volume Up", systemImage: "speaker.wave.3") { stepVolume(1 / 16) }
                    Button("Brightness", systemImage: "sun.max") {
                        center.showHUD(.brightness, level: .random(in: 0.2...1),
                                       showsPercentage: Defaults[.showBrightnessPercentage])
                    }
                }
            }
            Section {
                Text("Swipe on the notch with two fingers: down opens, up dismisses the current activity "
                    + "(or restores one when idle), sideways cycles activities.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Playground")
    }

    private func stepVolume(_ delta: Double) {
        volume = min(1, max(0, volume + delta))
        center.showHUD(.volume, level: volume, isMuted: volume == 0, showsPercentage: Defaults[.showVolumePercentage])
    }
}
