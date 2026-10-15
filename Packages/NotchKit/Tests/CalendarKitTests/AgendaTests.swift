import Foundation
import Testing
@testable import CalendarKit

struct AgendaTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-13 00:00 UTC.
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))! }

    private func at(_ hour: Double, day: Int = 0) -> Date {
        today.addingTimeInterval(Double(day) * 86400 + hour * 3600)
    }

    private func event(_ id: String, from start: Double, to end: Double, day: Int = 0, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: at(start, day: day), end: at(end, day: day), isAllDay: allDay)
    }

    private func items(_ events: [CalendarEvent], day: Int = 0, now: Double, rows: Int = 3) -> [Agenda.Item] {
        Agenda.items(for: at(0, day: day), in: events, now: at(now), rows: rows, showAllDay: true, calendar: calendar)
    }

    @Test func todayHidesFinishedEvents() {
        let events = [event("past", from: 9, to: 10), event("now", from: 11, to: 12), event("later", from: 15, to: 16)]
        let result = items(events, now: 11.5)
        #expect(result.map(\.id) == ["now", "later"])
    }

    @Test func overflowBecomesMoreRow() {
        let events = (0..<5).map { event("e\($0)", from: 12 + Double($0), to: 12.5 + Double($0)) }
        #expect(items(events, now: 8) == [.event(events[0], isLaterDay: false), .event(events[1], isLaterDay: false),
                                         .more(3)])
    }

    @Test func allDayEventsFoldIntoOneRowFirst() {
        let holiday = event("holiday", from: 0, to: 24, allDay: true)
        let trip = event("trip", from: 0, to: 24, allDay: true)
        let meeting = event("meeting", from: 14, to: 15)
        #expect(items([meeting, holiday, trip], now: 8) == [.allDay([holiday, trip]), .event(meeting, isLaterDay: false)])
    }

    @Test func spareRowsContinueWithTheNextEventsThisWeek() {
        let late = event("late", from: 20, to: 21)
        let thursday = event("thu", from: 9, to: 10, day: 2)
        let friday = event("fri", from: 9, to: 10, day: 3)
        let saturday = event("sat", from: 9, to: 10, day: 4)
        #expect(items([saturday, late, friday, thursday], now: 8)
            == [.event(late, isLaterDay: false), .event(thursday, isLaterDay: true), .event(friday, isLaterDay: true)])
    }

    @Test func emptyStates() {
        #expect(items([], now: 8) == [.caption("Nothing on today")])
        #expect(items([event("done", from: 9, to: 10)], now: 11) == [.caption("Nothing else today")])
        #expect(items([], day: 2, now: 8) == [.caption("Nothing on this day")])

        let tomorrow = event("tmrw", from: 9, to: 10, day: 1)
        #expect(items([tomorrow], now: 8) == [.caption("Nothing on today"), .event(tomorrow, isLaterDay: true)])
    }

    @Test func otherDaysShowEverything() {
        let morning = event("morning", from: 9, to: 10, day: 2)
        #expect(items([morning], day: 2, now: 23) == [.event(morning, isLaterDay: false)])
    }
}
