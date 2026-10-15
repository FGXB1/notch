import Testing
@testable import NotchCore

struct SwipeTrackerTests {
    @Test func verticalPullTriggersOnceAtThreshold() {
        var tracker = SwipeTracker(verticalThreshold: 30, horizontalThreshold: 60, axisLockDistance: 6)
        var actions: [SwipeTracker.Action] = []

        actions += [tracker.update(dx: 0, dy: 4, phase: .began).triggered].compactMap(\.self)
        for _ in 0..<20 {
            actions += [tracker.update(dx: 1, dy: 4, phase: .changed).triggered].compactMap(\.self)
        }
        #expect(actions == [.pullDown])
        #expect(tracker.axis == .vertical)

        let ended = tracker.update(dx: 0, dy: 0, phase: .ended)
        #expect(ended == SwipeTracker.Output())
        #expect(!tracker.hasTriggered)
    }

    @Test func axisLocksToTheDominantDirection() {
        var tracker = SwipeTracker()
        _ = tracker.update(dx: -5, dy: 1, phase: .began)
        let output = tracker.update(dx: -5, dy: 2, phase: .changed)
        #expect(output.axis == .horizontal)
        // Later vertical travel doesn't steal a locked horizontal gesture.
        let later = tracker.update(dx: 0, dy: 40, phase: .changed)
        #expect(later.axis == .horizontal)
        #expect(later.triggered == nil)
    }

    @Test func horizontalSwipesMapToLeftAndRight() {
        var tracker = SwipeTracker(horizontalThreshold: 20)
        _ = tracker.update(dx: -10, dy: 0, phase: .began)
        #expect(tracker.update(dx: -12, dy: 0, phase: .changed).triggered == .swipeLeft)
        _ = tracker.update(dx: 0, dy: 0, phase: .ended)

        _ = tracker.update(dx: 10, dy: 0, phase: .began)
        #expect(tracker.update(dx: 12, dy: 0, phase: .changed).triggered == .swipeRight)
    }

    @Test func pushUpIsNegativeVerticalTravel() {
        var tracker = SwipeTracker(verticalThreshold: 10)
        _ = tracker.update(dx: 0, dy: -7, phase: .began)
        #expect(tracker.update(dx: 0, dy: -5, phase: .changed).triggered == .pushUp)
    }

    @Test func rubberBandIsMonotonicAndBounded() {
        let samples = stride(from: 0.0, through: 10, by: 0.5).map(SwipeTracker.rubberBand)
        #expect(samples == samples.sorted())
        #expect(samples.allSatisfy { $0 < 1 })
        #expect(SwipeTracker.rubberBand(-2) == -SwipeTracker.rubberBand(2))
    }
}
