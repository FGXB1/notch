import Foundation

/// A source that can occupy the closed notch's wings for as long as it's relevant.
/// One live activity per kind; the kind doubles as its identity.
public enum ActivityKind: Hashable, Sendable {
    case nowPlaying
    case calendarEvent(id: String)
    case battery
    case connectivity
    case focus
    /// The padlock under the camera while the Mac is locked, and its unlock animation.
    case lock
    /// Playground activity identified by its SF Symbol.
    case demo(symbol: String)

    /// Not shown while the Mac is locked: anyone at the screen could read it.
    public var isPrivate: Bool {
        if case .calendarEvent = self { true } else { false }
    }
}

public struct LiveActivity: Identifiable, Equatable, Sendable {
    public var id: ActivityKind
    /// Higher priority wins over recency (e.g. an ongoing meeting over background music).
    public var priority: Int
    public var startedAt: Date
    public var updatedAt: Date

    public init(id: ActivityKind, priority: Int = 0, startedAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.priority = priority
        self.startedAt = startedAt
        self.updatedAt = updatedAt ?? startedAt
    }
}

/// A transient message that briefly enlarges the notch ("quick peek"), then gets out of the way.
public struct Notice: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case nowPlaying(title: String, artist: String?)
        case calendarEvent(id: String, title: String, start: Date, moment: EventMoment)
        /// `level` 0...1.
        case battery(level: Double, isCharging: Bool, event: BatteryEvent)
        /// Headphones and speakers. `battery` 0...1 when the device reports it.
        case device(name: String, symbol: String, battery: Double?, event: DeviceEvent)
        /// `tint` is a color name ("indigo", "mint", ...), resolved by the UI.
        case focus(name: String, symbol: String, tint: String, isOn: Bool)
        case demo(symbol: String, title: String, subtitle: String)

        /// Status updates sit in the wings like a HUD (nil: the notch drops down instead). Battery needs
        /// the wide wings for "Low Battery" plus a percentage.
        public var wingWidth: WingWidth? {
            switch self {
            case .battery: .wide
            case .device, .focus: .regular
            case .nowPlaying, .calendarEvent, .demo: nil
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var postedAt: Date
    public var duration: TimeInterval
    /// Carries a button (e.g. Join). Hovering then keeps the peek instead of expanding over it.
    public var hasActions: Bool

    public init(id: UUID = UUID(), kind: Kind, postedAt: Date, duration: TimeInterval, hasActions: Bool = false) {
        self.id = id
        self.kind = kind
        self.postedAt = postedAt
        self.duration = duration
        self.hasActions = hasActions
    }

    public var expiresAt: Date { postedAt.addingTimeInterval(duration) }
}

/// Why a calendar event is announcing itself.
public enum EventMoment: Hashable, Sendable {
    /// A few minutes before the start.
    case startingSoon
    /// At the start.
    case starting
    /// The event has a location and it's time to set off; carries the estimated travel time.
    case timeToLeave(travelTime: TimeInterval)
}

public enum WingWidth: Hashable, Sendable {
    /// As wide as a HUD's wings.
    case regular
    /// Room for a word beside a glyph.
    case wide
}

public enum BatteryEvent: Hashable, Sendable {
    /// Plugged in.
    case charging
    /// Fell to the low-battery threshold.
    case low
    /// Low Power Mode turned on.
    case lowPowerMode
}

public enum DeviceEvent: Hashable, Sendable {
    case connected
    case lowBattery
}

public enum HUDKind: Hashable, Sendable {
    case volume
    case brightness
    case keyboardBacklight
}

/// Replacement for a system HUD (volume, brightness...). Each key press re-posts it, extending its life.
public struct HUDEvent: Equatable, Sendable {
    public var kind: HUDKind
    /// 0...1
    public var level: Double
    public var isMuted: Bool
    /// Replaces the kind's own symbol, e.g. AirPods while they're the output device.
    public var symbol: String?
    /// Wider wings with the level as a number.
    public var showsPercentage: Bool
    public var postedAt: Date
    public var duration: TimeInterval

    public init(kind: HUDKind, level: Double, isMuted: Bool = false, symbol: String? = nil, showsPercentage: Bool = false,
                postedAt: Date, duration: TimeInterval) {
        self.kind = kind
        self.level = min(1, max(0, level))
        self.isMuted = isMuted
        self.symbol = symbol
        self.showsPercentage = showsPercentage
        self.postedAt = postedAt
        self.duration = duration
    }

    public var expiresAt: Date { postedAt.addingTimeInterval(duration) }
}

/// What the closed notch should show right now.
public enum ActivityDisplay: Equatable, Sendable {
    case idle
    case compact(LiveActivity)
    case peek(Notice)
    case hud(HUDEvent)
}
