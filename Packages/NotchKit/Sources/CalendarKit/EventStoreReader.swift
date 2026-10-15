import CoreGraphics
import EventKit

/// Owns the EventKit store off the main thread and hands out plain values. EventKit objects never leave it.
actor EventStoreReader {
    private var store = EKEventStore()

    nonisolated static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    nonisolated static var canRequestAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    func requestAccess() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in continuation.resume(returning: granted) }
        }
        if granted {
            // A store created before access was granted can keep serving empty results.
            store = EKEventStore()
        }
        return granted
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { calendar in
                let group = calendar.type == .subscription || calendar.type == .birthday
                    ? "Subscribed" : calendar.source?.title ?? "Other"
                return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title, group: group,
                                    color: EventColor(calendar.cgColor))
            }
            .sorted { ($0.group, $0.title) < ($1.group, $1.title) }
    }

    func events(from start: Date, to end: Date, excluding excluded: Set<String>) -> [CalendarEvent] {
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        // An empty list would mean "all calendars" to EventKit.
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .map(CalendarEvent.init)
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }
    }
}

private extension CalendarEvent {
    init(_ event: EKEvent) {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let attendeeStatus = event.attendees?.first(where: \.isCurrentUser)?.participantStatus
        self.init(
            id: "\(identifier)@\(Int(event.startDate.timeIntervalSince1970))",
            eventIdentifier: identifier,
            title: event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            color: EventColor(event.calendar?.cgColor),
            location: event.location,
            coordinate: event.structuredLocation?.geoLocation.map {
                Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            },
            meetingLink: MeetingLink.detect(in: [event.url?.absoluteString, event.location, event.notes]),
            isDeclined: attendeeStatus == .declined || event.status == .canceled)
    }
}

extension EventColor {
    init(_ color: CGColor?) {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color?.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else {
            self = .fallback
            return
        }
        self.init(red: components[0], green: components[1], blue: components[2])
    }
}
