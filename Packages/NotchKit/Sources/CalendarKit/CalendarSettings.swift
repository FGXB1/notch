import Defaults
import Foundation
import MapKit

public enum TravelMode: String, CaseIterable, Sendable, Defaults.Serializable {
    case drive
    case transit
    case walk

    public var title: String {
        switch self {
        case .drive: "Driving"
        case .transit: "Transit"
        case .walk: "Walking"
        }
    }

    public var symbol: String {
        switch self {
        case .drive: "car.fill"
        case .transit: "tram.fill"
        case .walk: "figure.walk"
        }
    }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .drive: .automobile
        case .transit: .transit
        case .walk: .walking
        }
    }
}

/// Where "Open in …" sends an event.
public enum CalendarApp: String, CaseIterable, Sendable, Defaults.Serializable {
    case calendar
    case fantastical
    case notionCalendar

    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .fantastical: "Fantastical"
        case .notionCalendar: "Notion Calendar"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .calendar: "com.apple.iCal"
        case .fantastical: "com.flexibits.fantastical2.mac"
        case .notionCalendar: "com.cron.electron"
        }
    }
}

public extension Defaults.Keys {
    static let enableCalendar = Key<Bool>("enableCalendar", default: true)
    static let excludedCalendars = Key<Set<String>>("excludedCalendars", default: [])
    static let showAllDayEvents = Key<Bool>("showAllDayEvents", default: true)

    /// Minutes before an event that it takes over the wings.
    static let upcomingEventLead = Key<Double>("upcomingEventLead", default: 15)
    static let disableActivityDuringEvents = Key<Bool>("disableActivityDuringEvents", default: false)

    static let enableCalendarQuickPeek = Key<Bool>("enableCalendarQuickPeek", default: true)
    static let beforeEventStarts = Key<Bool>("beforeEventStarts", default: true)
    /// Minutes before the start for the "Before it starts" peek.
    static let timeBeforeEvent = Key<Double>("timeBeforeEvent", default: 5)
    static let whenEventIsStarting = Key<Bool>("whenEventIsStarting", default: true)
    /// Seconds an event peek stays up (longer than a track change: it has a Join button).
    static let calendarPeekDuration = Key<Double>("calendarPeekDuration", default: 6)

    static let notifyWhenTimeToLeave = Key<Bool>("notifyWhenTimeToLeave", default: true)
    static let defaultTransportType = Key<TravelMode>("defaultTransportType", default: .drive)
    /// Minutes of slack added to the travel time.
    static let timeToLeaveBuffer = Key<Double>("timeToLeaveBuffer", default: 5)
    static let timeToLeaveDuration = Key<Double>("timeToLeaveDuration", default: 10)

    static let useCalendarColor = Key<Bool>("useCalendarColor", default: true)
    static let useEventIndicators = Key<Bool>("useEventIndicators", default: true)
    static let calendarApp = Key<CalendarApp>("calendarApp", default: .calendar)

    static let playSoundOnCalendarEvent = Key<Bool>("playSoundOnCalendarEvent", default: false)
    static let playHourlyChime = Key<Bool>("playHourlyChime", default: false)
}

extension ScheduleRules {
    @MainActor static var current: ScheduleRules {
        let quickPeek = Defaults[.enableCalendarQuickPeek]
        return ScheduleRules(
            lead: Defaults[.upcomingEventLead] * 60,
            showDuringEvents: !Defaults[.disableActivityDuringEvents],
            reminder: quickPeek && Defaults[.beforeEventStarts] ? Defaults[.timeBeforeEvent] * 60 : nil,
            peekAtStart: quickPeek && Defaults[.whenEventIsStarting],
            leaveBuffer: Defaults[.notifyWhenTimeToLeave] ? Defaults[.timeToLeaveBuffer] * 60 : nil)
    }
}
