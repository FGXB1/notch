import Foundation

/// One occurrence of a calendar event, copied out of EventKit so it can cross actors and be tested.
public struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// Unique per occurrence: recurring events share an `eventIdentifier`, so the start is appended.
    public var id: String
    /// EventKit's identifier, for deep links into Calendar.
    public var eventIdentifier: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var color: EventColor
    /// Free-text location as typed into the event.
    public var location: String?
    /// Geocoded by EventKit when the location was picked from a map suggestion.
    public var coordinate: Coordinate?
    public var meetingLink: MeetingLink?
    /// Declined or cancelled: kept out of the wings, reminders and travel estimates.
    public var isDeclined: Bool

    public init(id: String, eventIdentifier: String? = nil, title: String, start: Date, end: Date,
                isAllDay: Bool = false, calendarID: String = "", color: EventColor = .fallback,
                location: String? = nil, coordinate: Coordinate? = nil, meetingLink: MeetingLink? = nil,
                isDeclined: Bool = false) {
        self.id = id
        self.eventIdentifier = eventIdentifier ?? id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.color = color
        self.location = location
        self.coordinate = coordinate
        self.meetingLink = meetingLink
        self.isDeclined = isDeclined
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public func isOngoing(at date: Date) -> Bool { start <= date && date < end }

    /// 0...1 through the event.
    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }

    /// A place you'd travel to, as opposed to a call ("Microsoft Teams Meeting", a pasted link).
    public var physicalLocation: String? {
        guard meetingLink == nil, let location = location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty, !location.contains("://") else { return nil }
        let lowered = location.lowercased()
        guard !MeetingService.allCases.contains(where: { lowered.contains($0.name.lowercased()) }) else { return nil }
        return location
    }

    /// Free text worth geocoding: shaped like an address ("1 Main St, Springfield"), not a room name, which
    /// would geocode to some unrelated place and raise a bogus "time to leave".
    var geocodableAddress: String? {
        physicalLocation.flatMap { $0.contains(",") ? $0 : nil }
    }

    /// Somewhere travel time can be computed to.
    var hasTravelDestination: Bool {
        coordinate != nil || geocodableAddress != nil
    }
}

public struct EventColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let fallback = EventColor(red: 0.04, green: 0.52, blue: 1)

    /// Relative luminance (sRGB weights, uncorrected; plenty for choosing black or white on top).
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

public struct Coordinate: Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A calendar the user can show or hide.
public struct CalendarInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Account it belongs to ("iCloud", "Google", ...), or "Subscribed" for read-only feeds.
    public var group: String
    public var color: EventColor

    public init(id: String, title: String, group: String, color: EventColor) {
        self.id = id
        self.title = title
        self.group = group
        self.color = color
    }
}
