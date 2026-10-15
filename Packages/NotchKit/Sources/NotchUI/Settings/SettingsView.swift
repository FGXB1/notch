import SwiftUI

/// Hooks the settings window needs from the running notch.
public struct SettingsActions {
    /// Opens or closes the notch on the primary display, for previewing motion changes.
    public var togglePreview: () -> Void
    /// Shows the lock-screen widgets on the desktop for a few seconds.
    public var previewLockScreen: () -> Void
    /// Opens the first-launch welcome again.
    public var showWelcome: () -> Void
    /// Software updates, for builds that can update themselves; nil hides them.
    public var updates: UpdateControls?

    public init(togglePreview: @escaping () -> Void, previewLockScreen: @escaping () -> Void,
                showWelcome: @escaping () -> Void, updates: UpdateControls? = nil) {
        self.togglePreview = togglePreview
        self.previewLockScreen = previewLockScreen
        self.showWelcome = showWelcome
        self.updates = updates
    }
}

/// The app's updater, seen from Settings (which doesn't link it).
public struct UpdateControls {
    public var checkNow: () -> Void
    public var automaticallyChecks: () -> Bool
    public var setAutomaticallyChecks: (Bool) -> Void

    public init(checkNow: @escaping () -> Void, automaticallyChecks: @escaping () -> Bool,
                setAutomaticallyChecks: @escaping (Bool) -> Void) {
        self.checkNow = checkNow
        self.automaticallyChecks = automaticallyChecks
        self.setAutomaticallyChecks = setAutomaticallyChecks
    }
}

public struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, nowPlaying, calendar, weather, fileTray, huds, status, lockScreen, motionLab, playground, about

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .nowPlaying: "Now Playing"
            case .calendar: "Calendar"
            case .weather: "Weather"
            case .fileTray: "File Tray"
            case .huds: "HUDs"
            case .status: "Battery & Devices"
            case .lockScreen: "Lock Screen"
            case .motionLab: "Motion Lab"
            case .playground: "Playground"
            case .about: "About"
            }
        }

        /// The sidebar tile's colour, System Settings style.
        var tint: Color {
            switch self {
            case .general: .gray
            case .nowPlaying: .pink
            case .calendar: .red
            case .weather: .cyan
            case .fileTray: .blue
            case .huds: .indigo
            case .status: .green
            case .lockScreen: .orange
            case .motionLab: .purple
            case .playground: .yellow
            case .about: .secondary
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .nowPlaying: "play.fill"
            case .calendar: "calendar"
            case .weather: "cloud.sun.fill"
            case .fileTray: "tray.fill"
            case .huds: "speaker.wave.2.fill"
            case .status: "battery.75percent"
            case .lockScreen: "lock.fill"
            case .motionLab: "waveform.path.ecg"
            case .playground: "sparkles"
            case .about: "info"
            }
        }
    }

    @State private var selection: Pane? = .general
    let actions: SettingsActions

    public init(actions: SettingsActions) {
        self.actions = actions
    }

    public var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(pane.tint.gradient, in: .rect(cornerRadius: 6, style: .continuous))
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            switch selection ?? .general {
            case .general: GeneralPane()
            case .nowPlaying: NowPlayingPane()
            case .calendar: CalendarPane()
            case .weather: WeatherPane()
            case .fileTray: FileTrayPane()
            case .huds: HUDsPane()
            case .status: StatusPane()
            case .lockScreen: LockScreenPane(actions: actions)
            case .motionLab: MotionLabPane(actions: actions)
            case .playground: PlaygroundPane()
            case .about: AboutPane(actions: actions)
            }
        }
        .frame(minWidth: 700, minHeight: 480)
    }
}
