import Activities
import Defaults
import Foundation
import Observation
import SwiftUI

/// App-wide registry of everything competing for the notch. Integrations (media, calendar, HUDs) report
/// here; every display's `NotchController` renders `display`. Changes are animated at the source so all
/// notches morph in the same transaction.
@MainActor
@Observable
public final class ActivityCenter {
    public static let shared = ActivityCenter()

    public private(set) var display: ActivityDisplay = .idle
    /// Live activities in display order (best first), for UI like the cycle indicator.
    public private(set) var visibleLive: [LiveActivity] = []

    @ObservationIgnored private var state = ArbiterState()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    // MARK: Live activities

    public func upsert(_ kind: ActivityKind, priority: Int = 0) {
        let date = now()
        let existing = state.live.first { $0.id == kind }
        let activity = LiveActivity(id: kind, priority: priority, startedAt: existing?.startedAt ?? date, updatedAt: date)
        commit(ActivityArbiter.upserting(activity, into: state))
    }

    public func end(_ kind: ActivityKind) {
        commit(ActivityArbiter.ending(kind, in: state))
    }

    public func isLive(_ kind: ActivityKind) -> Bool {
        state.live.contains { $0.id == kind }
    }

    /// Swiped away by the user and not yet restored.
    public func isDismissed(_ kind: ActivityKind) -> Bool {
        state.dismissed.contains(kind)
    }

    public func dismissCurrent() {
        commit(ActivityArbiter.dismissingCurrent(state))
    }

    public func restoreDismissed() {
        commit(ActivityArbiter.restoringDismissed(state))
    }

    public func cycle() {
        commit(ActivityArbiter.cycling(state))
    }

    public func setLocked(_ locked: Bool) {
        guard locked != state.isLocked else { return }
        var next = state
        next.isLocked = locked
        commit(next)
    }

    // MARK: Transient

    public func post(_ kind: Notice.Kind, duration: TimeInterval? = nil, hasActions: Bool = false) {
        var next = state
        next.notices.append(Notice(kind: kind, postedAt: now(), duration: duration ?? Defaults[.peekDuration],
                                   hasActions: hasActions))
        commit(next)
    }

    public func showHUD(_ kind: HUDKind, level: Double, isMuted: Bool = false, symbol: String? = nil,
                        showsPercentage: Bool = false) {
        var next = state
        next.hud = HUDEvent(kind: kind, level: level, isMuted: isMuted, symbol: symbol, showsPercentage: showsPercentage,
                            postedAt: now(), duration: Defaults[.hudDuration])
        commit(next)
    }

    // MARK: Resolution

    private func commit(_ newState: ArbiterState) {
        let date = now()
        state = ActivityArbiter.pruned(newState, at: date)
        visibleLive = ActivityArbiter.visibleLive(state)

        let resolved = ActivityArbiter.resolve(state, at: date)
        if resolved != display {
            Log.shell.debug("Display: \(String(describing: resolved), privacy: .public)")
            withAnimation(animation(from: display, to: resolved)) { display = resolved }
        }
        scheduleExpiry(after: date)
    }

    private func animation(from old: ActivityDisplay, to new: ActivityDisplay) -> Animation {
        switch (old, new) {
        case let (.hud(a), .hud(b)) where a.kind == b.kind:
            Motion.hudLevel
        case let (.compact(a), .compact(b)) where a.id == b.id:
            Motion.hudLevel
        default:
            Motion.activity
        }
    }

    private func scheduleExpiry(after date: Date) {
        expiryTask?.cancel()
        guard let deadline = ActivityArbiter.nextExpiry(state, after: date) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline.timeIntervalSince(date)))
            guard !Task.isCancelled, let self else { return }
            self.commit(self.state)
        }
    }
}
