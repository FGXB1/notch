import Foundation
import Testing
@testable import Activities

struct ActivityArbiterTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func live(_ symbol: String, priority: Int = 0, at offset: TimeInterval) -> LiveActivity {
        LiveActivity(id: .demo(symbol: symbol), priority: priority, startedAt: t0.addingTimeInterval(offset))
    }

    private func notice(at offset: TimeInterval, duration: TimeInterval = 2) -> Notice {
        Notice(kind: .demo(symbol: "bell", title: "Hi", subtitle: ""), postedAt: t0.addingTimeInterval(offset),
               duration: duration)
    }

    @Test func emptyStateIsIdle() {
        #expect(ActivityArbiter.resolve(ArbiterState(), at: t0) == .idle)
    }

    @Test func mostRecentLiveActivityWinsAmongEqualPriority() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(live("a", at: 0), into: state)
        state = ActivityArbiter.upserting(live("b", at: 5), into: state)
        #expect(ActivityArbiter.currentLive(state)?.id == .demo(symbol: "b"))

        // Updating "a" makes it the most recent.
        state = ActivityArbiter.upserting(live("a", at: 10), into: state)
        #expect(ActivityArbiter.currentLive(state)?.id == .demo(symbol: "a"))
    }

    @Test func priorityBeatsRecency() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(live("meeting", priority: 1, at: 0), into: state)
        state = ActivityArbiter.upserting(live("music", at: 5), into: state)
        #expect(ActivityArbiter.currentLive(state)?.id == .demo(symbol: "meeting"))
    }

    @Test func hudBeatsNoticeBeatsLiveUntilTheyExpire() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(live("music", at: 0), into: state)
        state.notices = [notice(at: 0, duration: 2)]
        state.hud = HUDEvent(kind: .volume, level: 0.5, postedAt: t0, duration: 1)

        guard case .hud = ActivityArbiter.resolve(state, at: t0.addingTimeInterval(0.5)) else {
            Issue.record("expected HUD first")
            return
        }
        guard case .peek = ActivityArbiter.resolve(state, at: t0.addingTimeInterval(1.5)) else {
            Issue.record("expected the notice once the HUD expires")
            return
        }
        #expect(ActivityArbiter.resolve(state, at: t0.addingTimeInterval(3)) == .compact(live("music", at: 0)))
    }

    @Test func nextExpiryIsTheEarliestPendingTimeout() {
        var state = ArbiterState()
        state.notices = [notice(at: 0, duration: 3)]
        state.hud = HUDEvent(kind: .brightness, level: 1, postedAt: t0, duration: 1)
        #expect(ActivityArbiter.nextExpiry(state, after: t0) == t0.addingTimeInterval(1))
        #expect(ActivityArbiter.nextExpiry(state, after: t0.addingTimeInterval(1)) == t0.addingTimeInterval(3))
        #expect(ActivityArbiter.nextExpiry(state, after: t0.addingTimeInterval(4)) == nil)
    }

    @Test func dismissHidesUntilRestored() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(live("a", at: 0), into: state)
        state = ActivityArbiter.upserting(live("b", at: 5), into: state)

        state = ActivityArbiter.dismissingCurrent(state)
        #expect(ActivityArbiter.currentLive(state)?.id == .demo(symbol: "a"))
        state = ActivityArbiter.dismissingCurrent(state)
        #expect(ActivityArbiter.resolve(state, at: t0) == .idle)

        state = ActivityArbiter.restoringDismissed(state)
        #expect(ActivityArbiter.currentLive(state)?.id == .demo(symbol: "a"))
    }

    @Test func restoreSkipsActivitiesThatEnded() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(live("a", at: 0), into: state)
        state = ActivityArbiter.upserting(live("b", at: 5), into: state)
        state = ActivityArbiter.dismissingCurrent(state) // b
        state = ActivityArbiter.dismissingCurrent(state) // a
        state.live.removeAll { $0.id == .demo(symbol: "a") }
        state = ActivityArbiter.restoringDismissed(state)
        #expect(ActivityArbiter.currentLive(state)?.id == .demo(symbol: "b"))
    }

    @Test func cyclingWrapsAround() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(live("a", at: 0), into: state)
        state = ActivityArbiter.upserting(live("b", at: 5), into: state)
        state = ActivityArbiter.upserting(live("c", at: 10), into: state)

        var seen: [ActivityKind?] = []
        for _ in 0..<4 {
            seen.append(ActivityArbiter.currentLive(state)?.id)
            state = ActivityArbiter.cycling(state)
        }
        #expect(seen == [.demo(symbol: "c"), .demo(symbol: "b"), .demo(symbol: "a"), .demo(symbol: "c")])
    }

    @Test func endingClearsPinAndDismissal() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(live("a", at: 0), into: state)
        state = ActivityArbiter.upserting(live("b", at: 5), into: state)
        state = ActivityArbiter.cycling(state)
        #expect(state.pinned == .demo(symbol: "a"))
        state = ActivityArbiter.ending(.demo(symbol: "a"), in: state)
        #expect(state.pinned == nil)
        #expect(ActivityArbiter.currentLive(state)?.id == .demo(symbol: "b"))
    }

    @Test func lockingHidesPrivateActivitiesUntilUnlock() {
        var state = ArbiterState()
        state = ActivityArbiter.upserting(LiveActivity(id: .calendarEvent(id: "standup"), priority: 2, startedAt: t0), into: state)
        state = ActivityArbiter.upserting(LiveActivity(id: .nowPlaying, startedAt: t0), into: state)
        #expect(ActivityArbiter.currentLive(state)?.id == .calendarEvent(id: "standup"))

        state.isLocked = true
        #expect(ActivityArbiter.currentLive(state)?.id == .nowPlaying)

        state.isLocked = false
        #expect(ActivityArbiter.currentLive(state)?.id == .calendarEvent(id: "standup"))
    }

    @Test func padlockOnlyFillsAnIdleNotch() {
        var state = ArbiterState()
        state.isLocked = true
        state = ActivityArbiter.upserting(LiveActivity(id: .nowPlaying, startedAt: t0), into: state)
        state = ActivityArbiter.upserting(LiveActivity(id: .lock, priority: -1, startedAt: t0 + 1), into: state)
        #expect(ActivityArbiter.currentLive(state)?.id == .nowPlaying)

        state = ActivityArbiter.ending(.nowPlaying, in: state)
        #expect(ActivityArbiter.currentLive(state)?.id == .lock)
    }
}
