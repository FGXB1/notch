import Activities
import Foundation
import Testing
@testable import CalendarKit

struct EventScheduleTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let rules = ScheduleRules(lead: 15 * 60, showDuringEvents: true, reminder: 5 * 60, peekAtStart: true,
                                      leaveBuffer: 5 * 60)

    private func event(_ id: String, startsIn minutes: Double, lasting duration: Double = 30,
                       allDay: Bool = false, declined: Bool = false) -> CalendarEvent {
        let start = t0.addingTimeInterval(minutes * 60)
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(duration * 60),
                             isAllDay: allDay, isDeclined: declined)
    }

    // MARK: Featured

    @Test func upcomingWithinLeadIsFeatured() {
        let featured = EventSchedule.featured(in: [event("a", startsIn: 12)], at: t0, rules: rules)
        #expect(featured?.event.id == "a")
        #expect(featured?.isUrgent == false)
    }

    @Test func beyondLeadIsNotFeatured() {
        #expect(EventSchedule.featured(in: [event("a", startsIn: 16)], at: t0, rules: rules) == nil)
    }

    @Test func imminentEventBeatsTheOneInProgress() {
        let events = [event("current", startsIn: -20, lasting: 60), event("next", startsIn: 4)]
        let featured = EventSchedule.featured(in: events, at: t0, rules: rules)
        #expect(featured?.event.id == "next")
        #expect(featured?.isUrgent == true)
    }

    @Test func inProgressBeatsALaterUpcomingEvent() {
        let events = [event("current", startsIn: -20, lasting: 60), event("next", startsIn: 10)]
        #expect(EventSchedule.featured(in: events, at: t0, rules: rules)?.event.id == "current")
    }

    @Test func inProgressRespectsSettingAndLength() {
        var quiet = rules
        quiet.showDuringEvents = false
        #expect(EventSchedule.featured(in: [event("a", startsIn: -5)], at: t0, rules: quiet) == nil)
        #expect(EventSchedule.featured(in: [event("day", startsIn: -60, lasting: 9 * 60)], at: t0, rules: rules) == nil)
    }

    @Test func allDayAndDeclinedNeverDriveTheNotch() {
        let events = [event("allday", startsIn: -60, lasting: 24 * 60, allDay: true),
                      event("declined", startsIn: 2, declined: true)]
        #expect(EventSchedule.featured(in: events, at: t0, rules: rules) == nil)
    }

    // MARK: Notices

    @Test func noticesFireOnlyInsideTheWindow() {
        let a = event("a", startsIn: 5)
        // The "5 minutes before" moment is exactly t0.
        let due = EventSchedule.notices(for: [a], travelTimes: [:], rules: rules,
                                        after: t0.addingTimeInterval(-1), through: t0)
        #expect(due.map(\.moment) == [.startingSoon])

        let already = EventSchedule.notices(for: [a], travelTimes: [:], rules: rules, after: t0, through: t0 + 1)
        #expect(already.isEmpty)
    }

    @Test func timeToLeaveAccountsForTravelAndBuffer() {
        let a = event("a", startsIn: 30)
        // 20 min travel + 5 min buffer → leave at start - 25 min = t0 + 5 min.
        let due = EventSchedule.notices(for: [a], travelTimes: ["a": 20 * 60], rules: rules,
                                        after: t0.addingTimeInterval(4 * 60), through: t0.addingTimeInterval(5 * 60))
        #expect(due.map(\.moment) == [.timeToLeave(travelTime: 20 * 60)])
    }

    @Test func disabledMomentsDontFire() {
        let quiet = ScheduleRules(lead: 0, showDuringEvents: true, reminder: nil, peekAtStart: false, leaveBuffer: nil)
        let due = EventSchedule.notices(for: [event("a", startsIn: 5)], travelTimes: ["a": 60], rules: quiet,
                                        after: .distantPast, through: .distantFuture)
        #expect(due.isEmpty)
    }

    // MARK: Boundaries

    @Test func nextBoundaryIsTheEarliestChange() {
        let a = event("a", startsIn: 40)
        // Candidates: start-15 (25), start-5 (35, also the reminder), start (40), start+5 (45), end (70).
        #expect(EventSchedule.nextBoundary(for: [a], travelTimes: [:], rules: rules, after: t0)
            == t0.addingTimeInterval(25 * 60))
        #expect(EventSchedule.nextBoundary(for: [a], travelTimes: [:], rules: rules, after: t0.addingTimeInterval(25 * 60))
            == t0.addingTimeInterval(35 * 60))
        #expect(EventSchedule.nextBoundary(for: [a], travelTimes: [:], rules: rules, after: t0.addingTimeInterval(70 * 60))
            == nil)
    }

    @Test func leaveTimeIsABoundary() {
        let a = event("a", startsIn: 60)
        #expect(EventSchedule.nextBoundary(for: [a], travelTimes: ["a": 50 * 60], rules: rules, after: t0)
            == t0.addingTimeInterval(5 * 60))
    }
}
