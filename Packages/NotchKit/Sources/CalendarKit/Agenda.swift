import Foundation

/// What the expanded notch's agenda lists for one day, fitted to a fixed number of rows (the notch
/// can't scroll: vertical swipes open and close it).
public enum Agenda {
    public enum Item: Identifiable, Equatable, Sendable {
        /// All of the day's all-day events, folded into one row ("2 all-day").
        case allDay([CalendarEvent])
        /// `isLaterDay`: a following day's event filling spare rows under today, labelled with its day.
        case event(CalendarEvent, isLaterDay: Bool)
        /// Rows that didn't fit ("2 more events").
        case more(Int)
        /// Empty-day message ("Nothing on today", ...).
        case caption(String)

        public var id: String {
            switch self {
            case let .allDay(events): "allday-" + events.map(\.id).joined(separator: ",")
            case let .event(event, _): event.id
            case let .more(count): "more-\(count)"
            case let .caption(text): "caption-" + text
            }
        }
    }

    public static func items(for day: Date, in events: [CalendarEvent], now: Date, rows: Int, showAllDay: Bool,
                             calendar: Calendar = .current) -> [Item] {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let dayEvents = events.occurring(on: day, calendar: calendar)
        let timed = dayEvents.filter { !$0.isAllDay }
        let remaining = isToday ? timed.filter { $0.end > now } : timed
        let allDay = showAllDay ? dayEvents.filter(\.isAllDay) : []

        var items: [Item] = allDay.isEmpty ? [] : [.allDay(allDay)]
        items += remaining.map { .event($0, isLaterDay: false) }

        if items.count > rows {
            return Array(items.prefix(rows - 1)) + [.more(items.count - (rows - 1))]
        }

        // Today with room to spare: carry on with what's coming up rather than leave the space empty.
        var later: [Item] = []
        if isToday, let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) {
            later = events
                .filter { !$0.isAllDay && !$0.isDeclined && $0.start >= tomorrow }
                .sorted { $0.start < $1.start }
                .map { .event($0, isLaterDay: true) }
        }

        if items.isEmpty {
            let caption = if !isToday { "Nothing on this day" }
                else if timed.isEmpty { "Nothing on today" }
                else { "Nothing else today" }
            return [.caption(caption)] + later.prefix(rows - 1)
        }
        return items + later.prefix(rows - items.count)
    }
}
