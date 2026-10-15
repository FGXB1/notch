import Activities
import AppKit
import Defaults
import IOKit.ps
import NotchCore
import Observation

public struct BatteryStatus: Equatable, Sendable {
    /// 0...1
    public var level: Double
    public var isPluggedIn: Bool
    public var isCharging: Bool
    public var isLowPowerMode: Bool

    public init(level: Double, isPluggedIn: Bool, isCharging: Bool, isLowPowerMode: Bool) {
        self.level = level
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
    }
}

/// Which battery notices a status change deserves. Pure, so the edge cases are testable.
public enum BatteryAlerts {
    public struct Rules: Sendable {
        public var notifyOnCharging: Bool
        public var warnOnLow: Bool
        /// 0...1
        public var lowThreshold: Double
        public var notifyOnLowPowerMode: Bool

        public init(notifyOnCharging: Bool, warnOnLow: Bool, lowThreshold: Double, notifyOnLowPowerMode: Bool) {
            self.notifyOnCharging = notifyOnCharging
            self.warnOnLow = warnOnLow
            self.lowThreshold = lowThreshold
            self.notifyOnLowPowerMode = notifyOnLowPowerMode
        }
    }

    /// At launch (`previous` nil) only an already-low battery is news; charging and Low Power aren't.
    public static func events(from previous: BatteryStatus?, to current: BatteryStatus, rules: Rules) -> [BatteryEvent] {
        guard let previous else {
            return rules.warnOnLow && !current.isPluggedIn && current.level <= rules.lowThreshold ? [.low] : []
        }
        var events: [BatteryEvent] = []
        if rules.notifyOnCharging, current.isPluggedIn, !previous.isPluggedIn {
            events.append(.charging)
        }
        // Crossing the threshold on battery, or unplugging while already below it.
        let wasAbove = previous.level > rules.lowThreshold || previous.isPluggedIn
        if rules.warnOnLow, !current.isPluggedIn, current.level <= rules.lowThreshold, wasAbove {
            events.append(.low)
        }
        if rules.notifyOnLowPowerMode, current.isLowPowerMode, !previous.isLowPowerMode {
            events.append(.lowPowerMode)
        }
        return events
    }
}

/// Internal battery state from IOKit power sources (pushed, not polled) plus Low Power Mode.
@MainActor
@Observable
public final class BatteryMonitor {
    public static let shared = BatteryMonitor()

    /// nil on Macs without a battery.
    public private(set) var status: BatteryStatus?

    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var observer: NSObjectProtocol?

    public init(activities: ActivityCenter = .shared) {
        self.activities = activities
    }

    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    private func update() {
        guard let current = Self.readStatus() else { return }
        let previous = status
        guard current != previous else { return }
        status = current

        let rules = BatteryAlerts.Rules(notifyOnCharging: Defaults[.notifyOnCharging],
                                        warnOnLow: Defaults[.warnOnLowBattery],
                                        lowThreshold: Defaults[.lowBatteryThreshold] / 100,
                                        notifyOnLowPowerMode: Defaults[.notifyOnLowPowerMode])
        let events = BatteryAlerts.events(from: previous, to: current, rules: rules)
        if previous == nil, !events.isEmpty {
            // Let launch settle (windows, other notices) before warning.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.announce(events, status: current)
            }
        } else {
            announce(events, status: current)
        }
    }

    private func announce(_ events: [BatteryEvent], status current: BatteryStatus) {
        guard LockMonitor.allows(.allowBatteryWhenLocked) else { return }
        for event in events {
            // The charger is in before IOKit reports charging; show the bolt straight away.
            activities.post(.battery(level: current.level, isCharging: current.isCharging || event == .charging,
                                     event: event))
            if event == .low, Defaults[.playSoundOnLowBattery] {
                NSSound(named: "Funk")?.play()
            }
            Log.system.info("Battery \(String(describing: event), privacy: .public) at \(Int(current.level * 100))%")
        }
    }

    private static func readStatus() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryStatus(level: min(1, Double(current) / Double(max)),
                                 isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                                 isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                                 isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        return nil
    }
}
