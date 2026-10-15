import Foundation

/// Everything competing for the notch.
public struct ArbiterState: Equatable, Sendable {
    public var live: [LiveActivity] = []
    /// Shown one at a time, oldest first.
    public var notices: [Notice] = []
    public var hud: HUDEvent?
    /// Swiped away by the user; hidden until restored or ended. Last element was dismissed most recently.
    public var dismissed: [ActivityKind] = []
    /// Chosen by cycling; wins over recency while it's live and not dismissed.
    public var pinned: ActivityKind?
    /// Locked: private activities stay live but out of sight until unlock.
    public var isLocked = false

    public init() {}
}

/// Decides what the notch shows. Priority: HUD > notice (quick peek) > live activity > idle.
/// Pure and deterministic so the rules can be unit-tested; `ActivityCenter` applies them over time.
public enum ActivityArbiter {
    public static func resolve(_ state: ArbiterState, at now: Date) -> ActivityDisplay {
        if let hud = state.hud, hud.expiresAt > now {
            return .hud(hud)
        }
        if let notice = state.notices.first(where: { $0.expiresAt > now }) {
            return .peek(notice)
        }
        if let current = currentLive(state) {
            return .compact(current)
        }
        return .idle
    }

    /// Live activities that may be shown, best first: priority, then most recently updated.
    public static func visibleLive(_ state: ArbiterState) -> [LiveActivity] {
        state.live
            .filter { !state.dismissed.contains($0.id) && !(state.isLocked && $0.id.isPrivate) }
            .sorted { lhs, rhs in
                lhs.priority != rhs.priority ? lhs.priority > rhs.priority : lhs.updatedAt > rhs.updatedAt
            }
    }

    public static func currentLive(_ state: ArbiterState) -> LiveActivity? {
        let visible = visibleLive(state)
        if let pinned = state.pinned, let match = visible.first(where: { $0.id == pinned }) {
            return match
        }
        return visible.first
    }

    /// Drops expired HUDs and notices.
    public static func pruned(_ state: ArbiterState, at now: Date) -> ArbiterState {
        var state = state
        if let hud = state.hud, hud.expiresAt <= now {
            state.hud = nil
        }
        state.notices.removeAll { $0.expiresAt <= now }
        return state
    }

    /// When the displayed result can next change on its own.
    public static func nextExpiry(_ state: ArbiterState, after now: Date) -> Date? {
        let candidates = [state.hud?.expiresAt, state.notices.first?.expiresAt].compactMap(\.self)
        return candidates.filter { $0 > now }.min()
    }

    // MARK: Mutations

    public static func upserting(_ activity: LiveActivity, into state: ArbiterState) -> ArbiterState {
        var state = state
        if let index = state.live.firstIndex(where: { $0.id == activity.id }) {
            state.live[index].priority = activity.priority
            state.live[index].updatedAt = activity.updatedAt
        } else {
            state.live.append(activity)
        }
        return state
    }

    public static func ending(_ kind: ActivityKind, in state: ArbiterState) -> ArbiterState {
        var state = state
        state.live.removeAll { $0.id == kind }
        state.dismissed.removeAll { $0 == kind }
        if state.pinned == kind {
            state.pinned = nil
        }
        return state
    }

    /// Hides the live activity currently on screen.
    public static func dismissingCurrent(_ state: ArbiterState) -> ArbiterState {
        guard let current = currentLive(state) else { return state }
        var state = state
        state.dismissed.append(current.id)
        if state.pinned == current.id {
            state.pinned = nil
        }
        return state
    }

    /// Brings back the most recently dismissed activity that's still live, and shows it.
    public static func restoringDismissed(_ state: ArbiterState) -> ArbiterState {
        var state = state
        while let last = state.dismissed.popLast() {
            if state.live.contains(where: { $0.id == last }) {
                state.pinned = last
                break
            }
        }
        return state
    }

    /// Pins the next visible live activity after the current one.
    public static func cycling(_ state: ArbiterState) -> ArbiterState {
        let visible = visibleLive(state)
        guard visible.count > 1, let current = currentLive(state),
              let index = visible.firstIndex(where: { $0.id == current.id }) else { return state }
        var state = state
        state.pinned = visible[(index + 1) % visible.count].id
        return state
    }
}
