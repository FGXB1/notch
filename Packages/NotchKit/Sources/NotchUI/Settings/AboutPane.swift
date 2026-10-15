import AppKit
import SwiftUI

struct AboutPane: View {
    let actions: SettingsActions

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            MiniNotch()
                .padding(28)
                .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
            Text("Notch")
                .font(.system(size: 30, weight: .bold))
            Text(version)
                .foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if let updates = actions.updates {
                        Button("Check for Updates…", systemImage: "arrow.down.circle", action: updates.checkNow)
                    }
                    Button("Show Welcome…", systemImage: "hand.wave", action: actions.showWelcome)
                    Button("Preview Lock Screen", systemImage: "lock", action: actions.previewLockScreen)
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 8)
            if let updates = actions.updates {
                AutomaticUpdatesToggle(updates: updates)
            }
            VStack(spacing: 6) {
                Text("Now Playing uses mediaremote-adapter by Jonas van den Berg (BSD 3-Clause). Weather data by Open-Meteo.com.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                if let acknowledgements = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                    Button("Acknowledgements") {
                        NSWorkspace.shared.open(acknowledgements)
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}

private struct AutomaticUpdatesToggle: View {
    let updates: UpdateControls
    @State private var isOn: Bool

    init(updates: UpdateControls) {
        self.updates = updates
        _isOn = State(initialValue: updates.automaticallyChecks())
    }

    var body: some View {
        Toggle("Check for updates automatically", isOn: $isOn)
            .toggleStyle(.checkbox)
            .onChange(of: isOn) { _, isOn in
                updates.setAutomaticallyChecks(isOn)
            }
    }
}
