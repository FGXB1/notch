import Activities
import Foundation

/// The user's calendar settings, reduced to what the scheduling rules need.
public struct ScheduleRules: Equatable, Sendable {
    /// Show the next event in the wings this long before it starts (0 = only once it has started).
    public var lead: TimeInterval
    /// Keep an event in the wings while it's in progress (the inverse of "Hide once it starts").
    public var showDuringEvents: Bool
    /// Peek this long before the start; nil = off.
    public var reminder: TimeInterval?
    public var peekAtStart: Bool
    /// Peek when it's time to leave, this long before you'd need to set off; nil = off.
    public var leaveBuffer: TimeInterval?

    public init(lead: TimeInterval, showDuringEvents: Bool, reminder: TimeInterval?, peekAtStart: Bool,
                leaveBuffer: TimeInterval?) {
        self.lead = lead
        self.showDuringEvents = showDuringEvents
        self.reminder = reminder
        self.peekAtStart = peekAtStart
        self.leaveBuffer = leaveBuffer
    }

    /// Around the start, the event outranks other live activities so you don't miss it.
    public static let urgency: TimeInterval = 5 * 60
    /// Longer "events" are usually blocks (a conference day, a trip) that shouldn't hold the wings.
    public static let longestLiveEvent: TimeInterval = 8 * 3600
}

/// The event that owns the wings right now.
public struct FeaturedEvent: Equatable, Sendable {
    public var event: CalendarEvent
    /// Within `ScheduleRules.urgency` of the start.
    public var isUrgent: Bool

    public init(event: CalendarEvent, isUrgent: Bool) {
        self.event = event
        self.isUrgent = isUrgent
    }
}

public struct DueNotice: Equatable, Sendable {
    public var event: CalendarEvent
    public var moment: EventMoment
    public var fireDate: Date
}

/// Pure timing rules for calendar events: what the wings show, when to peek, when anything next changes.
public enum EventSchedule {
    static func drivesNotch(_ event: CalendarEvent) -> Bool {
        !event.isAllDay && !event.isDeclined
    }

    /// Order of preference: an event about to start (you need to move), then the one in progress, then the
    /// next one within the lead time.
    public static func featured(in events: [CalendarEvent], at now: Date, rules: ScheduleRules) -> FeaturedEvent? {
        let candidates = events.filter(drivesNotch)
        let upcoming = candidates
            .filter { $0.start > now && $0.start.timeIntervalSince(now) <= rules.lead }
            .sorted { $0.start < $1.start }
        let ongoing = candidates
            .filter { rules.showDuringEvents && $0.isOngoing(at: now) && $0.duration <= ScheduleRules.longestLiveEvent }
            .sorted { $0.start != $1.start ? $0.start > $1.start : $0.end < $1.end }

        func featured(_ event: CalendarEvent) -> FeaturedEvent {
            FeaturedEvent(event: event, isUrgent: abs(event.start.timeIntervalSince(now)) < ScheduleRules.urgency)
        }
        if let next = upcoming.first, next.start.timeIntervalSince(now) <= ScheduleRules.urgency {
            return featured(next)
        }
        return (ongoing.first ?? upcoming.first).map(featured)
    }

    /// Peeks whose moment falls in `(after, through]`.
    public static func notices(for events: [CalendarEvent], travelTimes: [String: TimeInterval],
                               rules: ScheduleRules, after start: Date, through end: Date) -> [DueNotice] {
        events.filter(drivesNotch).flatMap { event in
            moments(for: event, travelTime: travelTimes[event.id], rules: rules)
                .filter { $0.date > start && $0.date <= end }
                .map { DueNotice(event: event, moment: $0.moment, fireDate: $0.date) }
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    /// The next instant at which `featured` or `notices` can change on their own.
    public static func nextBoundary(for events: [CalendarEvent], travelTimes: [String: TimeInterval],
                                    rules: ScheduleRules, after now: Date) -> Date? {
        events.filter(drivesNotch).flatMap { event in
            [event.start.addingTimeInterval(-rules.lead),
             event.start.addingTimeInterval(-ScheduleRules.urgency),
             event.start.addingTimeInterval(ScheduleRules.urgency),
             event.end]
                + moments(for: event, travelTime: travelTimes[event.id], rules: rules).map(\.date)
        }
        .filter { $0 > now }
        .min()
    }

    private static func moments(for event: CalendarEvent, travelTime: TimeInterval?,
                                rules: ScheduleRules) -> [(moment: EventMoment, date: Date)] {
        var moments: [(EventMoment, Date)] = []
        if let reminder = rules.reminder, reminder > 0 {
            moments.append((.startingSoon, event.start.addingTimeInterval(-reminder)))
        }
        if rules.peekAtStart {
            moments.append((.starting, event.start))
        }
        if let buffer = rules.leaveBuffer, let travelTime {
            moments.append((.timeToLeave(travelTime: travelTime), event.start.addingTimeInterval(-travelTime - buffer)))
        }
        return moments
    }
}
