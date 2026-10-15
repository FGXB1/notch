import AppKit
import CoreGraphics
import Defaults
import Observation

/// How lock-screen widgets are drawn.
public enum LockWidgetStyle: String, CaseIterable, Sendable, Defaults.Serializable {
    /// The wallpaper behind the widget, blurred and dimmed.
    case frosted
    /// Liquid Glass over the wallpaper.
    case glass
    /// No backdrop: content straight on the wallpaper, with a shadow for legibility.
    case clear
}

public extension Defaults.Keys {
    static let enableLockScreen = Key<Bool>("enableLockScreen", default: true)
    static let lockScreenWidgetStyle = Key<LockWidgetStyle>("lockScreenWidgetStyle", default: .frosted)
    static let showVolumeControl = Key<Bool>("showVolumeControl", default: true)
    /// Vertical offset of the widgets, in points.
    static let nowPlayingWidgetOffset = Key<Double>("nowPlayingWidgetOffset", default: 0)
    static let playSoundOnLock = Key<Bool>("playSoundOnLock", default: false)
    static let playSoundOnUnlock = Key<Bool>("playSoundOnUnlock", default: false)
    /// Keep the display on while locked and music is playing.
    static let keepAwake = Key<Bool>("keepAwake", default: false)
    static let showOnScreenSaver = Key<Bool>("showOnScreenSaver", default: false)
    static let showLockIndicator = Key<Bool>("showLockIndicator", default: true)

    // Widgets on the lock screen
    static let allowNowPlayingWidgetWhenLocked = Key<Bool>("allowNowPlayingWidgetWhenLocked", default: true)
    static let allowBatteryWidgetWhenLocked = Key<Bool>("allowBatteryWidgetWhenLocked", default: true)
    static let allowFocusWidgetWhenLocked = Key<Bool>("allowFocusWidgetWhenLocked", default: true)
    static let allowConnectivityWidgetWhenLocked = Key<Bool>("allowConnectivityWidgetWhenLocked", default: true)
    /// Off by default: anyone at the Mac could read your next meeting.
    static let allowCalendarWidgetWhenLocked = Key<Bool>("allowCalendarWidgetWhenLocked", default: false)

    // What the notch itself may show while locked
    static let allowVolumeWhenLocked = Key<Bool>("allowVolumeWhenLocked", default: true)
    static let allowBrightnessWhenLocked = Key<Bool>("allowBrightnessWhenLocked", default: true)
    static let allowBatteryWhenLocked = Key<Bool>("allowBatteryWhenLocked", default: true)
    static let allowConnectivityWhenLocked = Key<Bool>("allowConnectivityWhenLocked", default: true)
    static let allowFocusWhenLocked = Key<Bool>("allowFocusWhenLocked", default: true)
}

public enum LockEvent: Sendable {
    case locked
    case unlocked
    case screenSaverStarted
    case screenSaverStopped
}

/// Whether the session is locked, from loginwindow's distributed notifications.
@MainActor
@Observable
public final class LockMonitor {
    public static let shared = LockMonitor()

    public private(set) var isLocked: Bool
    public private(set) var isScreenSaverActive = false
    /// The notch padlock's state; it lags `isLocked` so the unlock morph is visible.
    public var isIndicatorOpen = false

    @ObservationIgnored private var handlers: [(LockEvent) -> Void] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init() {
        isLocked = Self.sessionIsLocked
    }

    /// The lock state right now, asked of the window server (used at launch, before any notification).
    public static var sessionIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    public func onEvent(_ handler: @escaping (LockEvent) -> Void) {
        handlers.append(handler)
    }

    public func start() {
        guard observers.isEmpty else { return }
        let events: [(String, LockEvent)] = [
            ("com.apple.screenIsLocked", .locked),
            ("com.apple.screenIsUnlocked", .unlocked),
            ("com.apple.screensaver.didstart", .screenSaverStarted),
            ("com.apple.screensaver.didstop", .screenSaverStopped),
        ]
        let center = DistributedNotificationCenter.default()
        for (name, event) in events {
            observers.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(event) }
            })
        }
    }

    private func handle(_ event: LockEvent) {
        switch event {
        case .locked:
            guard !isLocked else { return }
            isLocked = true
        case .unlocked:
            guard isLocked else { return }
            isLocked = false
        case .screenSaverStarted:
            guard !isScreenSaverActive else { return }
            isScreenSaverActive = true
        case .screenSaverStopped:
            guard isScreenSaverActive else { return }
            isScreenSaverActive = false
        }
        handlers.forEach { $0(event) }
    }

    /// While locked, whether an alert governed by `key` may appear in the notch.
    public static func allows(_ key: Defaults.Key<Bool>) -> Bool {
        !shared.isLocked || Defaults[key]
    }
}
