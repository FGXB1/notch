import AppKit
import AudioTap
import CalendarKit
import CoreBluetooth
import Defaults
import NotchCore
import PrivateAPI
import SwiftUI
import SystemKit

/// First launch: what Notch does, and each permission it would like, asked one at a time with a reason.
/// Until this is finished nothing prompts on its own (see `hasCompletedOnboarding`).
public enum Welcome {
    public static var isNeeded: Bool { !Defaults[.hasCompletedOnboarding] }

    @MainActor
    public static func markComplete() {
        guard isNeeded else { return }
        Defaults[.hasCompletedOnboarding] = true
    }
}

public struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var permissions = PermissionsModel()
    private let launchAtLogin = LaunchAtLogin.shared

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.bottom, 24)

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(permissions.rows) { row in
                        PermissionRowView(row: row)
                    }
                }
            }
            .padding(.horizontal, 28)

            VStack(spacing: 14) {
                Toggle("Open Notch when you log in", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button(action: onFinish) {
                    Text(permissions.allGranted ? "Get Started" : "Continue")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)

                Text("Every permission is optional, and can be changed any time in System Settings › Privacy & Security.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 22)
            .padding(.horizontal, 40)
            .padding(.bottom, 26)
        }
        .frame(width: 540)
        .task { await permissions.poll() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            MiniNotch()
            Text("Welcome to Notch")
                .font(.system(size: 28, weight: .bold))
            Text("Music, your calendar, weather, HUDs and a file tray, right where the notch is. Each of these needs a permission to work.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }
}

/// The notch as it looks with music playing: artwork on the left, the waveform on the right.
struct MiniNotch: View {
    var body: some View {
        ZStack {
            NotchShape(bodySize: CGSize(width: 190, height: 38), topRadius: 8, bottomRadius: 16)
                .fill(.black)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            HStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                Spacer()
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 2.5) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule()
                                .fill(.pink.gradient)
                                .frame(width: 3, height: 6 + 12 * abs(sin(time * (2.2 + Double(index) * 0.7) + Double(index))))
                        }
                    }
                    .frame(height: 20)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 190, height: 38)
        }
        .frame(width: 206, height: 38)
    }
}

// MARK: - Permissions

private struct PermissionRow: Identifiable {
    enum State {
        case granted
        case denied
        case notDetermined
    }

    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let state: State
    /// Shows the system prompt.
    let request: @MainActor () -> Void
    /// `x-apple.systempreferences` anchor of its Privacy & Security pane, for when it was turned down.
    let settingsAnchor: String
}

@MainActor
@Observable
private final class PermissionsModel {
    private(set) var rows: [PermissionRow] = []

    var allGranted: Bool { rows.allSatisfy { $0.state == .granted } }

    init() {
        refresh()
    }

    /// Statuses change in System Settings with no notification for most of them, so look every second
    /// while the window is up.
    func poll() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func refresh() {
        let calendar = CalendarController.shared
        rows = [
            PermissionRow(
                id: "calendar", symbol: "calendar", tint: .red, title: "Calendar",
                detail: "What's next today, with a Join button for meetings.",
                state: Self.state(calendar.access), request: calendar.requestAccess,
                settingsAnchor: "Privacy_Calendars"),
            PermissionRow(
                id: "accessibility", symbol: "speaker.wave.2.fill", tint: .blue, title: "Volume & Brightness Keys",
                detail: "Shows Notch's HUD instead of the system one. Uses Accessibility.",
                state: AXIsProcessTrusted() ? .granted : Defaults[.hasPromptedAccessibility] ? .denied : .notDetermined,
                request: HUDController.shared.requestAccessibility, settingsAnchor: "Privacy_Accessibility"),
            PermissionRow(
                id: "bluetooth", symbol: "airpods.pro", tint: .teal, title: "Bluetooth",
                detail: "Your AirPods' battery when they connect.",
                state: Self.state(CBManager.authorization), request: DeviceMonitor.shared.requestAccess,
                settingsAnchor: "Privacy_Bluetooth"),
            PermissionRow(
                id: "location", symbol: "location.fill", tint: .indigo, title: "Location",
                detail: "Local weather, and when to leave for events with a place.",
                state: Self.state(LocationProvider.shared.authorization),
                request: LocationProvider.shared.requestAuthorization, settingsAnchor: "Privacy_LocationServices"),
            PermissionRow(
                id: "audio", symbol: "waveform", tint: .pink, title: "System Audio Recording",
                detail: "Makes the waveform move with your music. Nothing is recorded or kept.",
                state: Self.state(LiveWaveform.shared.permission), request: LiveWaveform.shared.requestAccess,
                settingsAnchor: "Privacy_ScreenCapture"),
        ]
    }

    private static func state(_ access: CalendarController.Access) -> PermissionRow.State {
        switch access {
        case .granted: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    private static func state(_ authorization: CBManagerAuthorization) -> PermissionRow.State {
        switch authorization {
        case .allowedAlways: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func state(_ authorization: LocationProvider.Authorization) -> PermissionRow.State {
        switch authorization {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        }
    }

    private static func state(_ status: TCC.Status?) -> PermissionRow.State {
        switch status {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined, nil: .notDetermined
        }
    }
}

private struct PermissionRowView: View {
    let row: PermissionRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(row.tint.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(row.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        .animation(.smooth(duration: 0.3), value: row.state)
    }

    @ViewBuilder private var trailing: some View {
        switch row.state {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .transition(.blurReplace)
        case .notDetermined:
            Button("Allow", action: row.request)
                .buttonStyle(.glass)
                .transition(.blurReplace)
        case .denied:
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(row.settingsAnchor)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.glass)
            .transition(.blurReplace)
        }
    }
}
