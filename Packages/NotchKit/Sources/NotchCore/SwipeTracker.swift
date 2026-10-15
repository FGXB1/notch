import Foundation

/// Turns a stream of two-finger scroll deltas into one directional action per gesture, plus continuous
/// progress for rubber-banding. Deltas are in finger space: +x = fingers moved right, +y = fingers moved down.
public struct SwipeTracker: Sendable {
    public enum Phase: Sendable {
        case began, changed, ended
    }

    public enum Axis: Sendable {
        case undecided, horizontal, vertical
    }

    public enum Action: Equatable, Sendable {
        case pullDown, pushUp, swipeLeft, swipeRight
    }

    public struct Output: Equatable, Sendable {
        /// Signed fraction of the threshold travelled on the locked axis (0 when undecided or ended).
        public var progress: Double = 0
        public var axis: Axis = .undecided
        /// Set exactly once per gesture, on the event that crosses the threshold.
        public var triggered: Action?
        public var isActive = false
    }

    public var verticalThreshold: Double
    public var horizontalThreshold: Double
    /// Travel needed before the dominant axis is locked for the rest of the gesture.
    public var axisLockDistance: Double

    public private(set) var axis: Axis = .undecided
    public private(set) var hasTriggered = false
    private var travel = (x: 0.0, y: 0.0)

    public init(verticalThreshold: Double = 30, horizontalThreshold: Double = 60, axisLockDistance: Double = 6) {
        self.verticalThreshold = verticalThreshold
        self.horizontalThreshold = horizontalThreshold
        self.axisLockDistance = axisLockDistance
    }

    public mutating func update(dx: Double, dy: Double, phase: Phase) -> Output {
        switch phase {
        case .began:
            reset()
            fallthrough
        case .changed:
            travel.x += dx
            travel.y += dy
            if axis == .undecided, max(abs(travel.x), abs(travel.y)) >= axisLockDistance {
                axis = abs(travel.y) >= abs(travel.x) ? .vertical : .horizontal
            }
            var output = Output(axis: axis, isActive: true)
            switch axis {
            case .undecided:
                break
            case .vertical:
                output.progress = travel.y / verticalThreshold
            case .horizontal:
                output.progress = travel.x / horizontalThreshold
            }
            if !hasTriggered, abs(output.progress) >= 1 {
                hasTriggered = true
                output.triggered = switch axis {
                case .vertical: output.progress > 0 ? .pullDown : .pushUp
                case .horizontal: output.progress > 0 ? .swipeRight : .swipeLeft
                case .undecided: nil
                }
            }
            return output
        case .ended:
            reset()
            return Output()
        }
    }

    private mutating func reset() {
        axis = .undecided
        hasTriggered = false
        travel = (0, 0)
    }

    /// Diminishing stretch for a gesture that hasn't committed yet: linear near zero, asymptotic to ±1.
    public static func rubberBand(_ progress: Double) -> Double {
        let magnitude = 1 - 1 / (abs(progress) * 0.8 + 1)
        return progress < 0 ? -magnitude : magnitude
    }
}
