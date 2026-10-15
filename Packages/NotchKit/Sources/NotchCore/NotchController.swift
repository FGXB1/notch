import Activities
import Defaults
import Observation
import SwiftUI

/// Single source of truth for one display's notch. Views read it; only this type decides transitions,
/// so every animation goes through the springs in `Motion` and can be interrupted mid-flight.
@MainActor
@Observable
public final class NotchController {
    public enum Presentation: Equatable, Sendable {
        case closed
        case compact(LiveActivity)
        case peek(Notice)
        case hud(HUDEvent)
        case expanded
    }

    public private(set) var isExpanded = false
    public private(set) var isHovering = false
    /// The closed notch's hover swell.
    public private(set) var isElevated = false
    public private(set) var isPressed = false
    /// Expanded content is revealed separately from the shell so it can trail the morph.
    public private(set) var isContentVisible = false
    public private(set) var tab: NotchTab = .home
    /// An app is full screen on this display (only matters with "Hide in full-screen apps" on).
    public private(set) var isFullScreenActive = false
    /// What's behind the notch is dark (see `BackdropMonitor`).
    public private(set) var isBackdropDark = false
    /// Live rubber-band stretch while a swipe is in progress.
    public private(set) var stretch: CGSize = .zero
    public private(set) var metrics: NotchMetrics
    public let activities: ActivityCenter

    /// Horizontal swipes go here first (media skipping, Phase 3). Return `true` if handled.
    @ObservationIgnored public var onHorizontalSwipe: ((SwipeTracker.Action) -> Bool)?

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var swipe = SwipeTracker()
    /// A file drag is over (or near) the notch; hover tracking is unreliable until it ends.
    @ObservationIgnored private var isFileDragActive = false

    public init(metrics: NotchMetrics, activities: ActivityCenter = .shared) {
        self.metrics = metrics
        self.activities = activities
    }

    // MARK: Shape

    public var presentation: Presentation {
        if isExpanded { return .expanded }
        return switch activities.display {
        case .idle: .closed
        case let .compact(activity): .compact(activity)
        case let .peek(notice): .peek(notice)
        case let .hud(event): .hud(event)
        }
    }

    /// Target size, without the transient gesture stretch.
    private var restingSize: CGSize {
        let base = switch presentation {
        case .closed: metrics.closed
        case let .compact(activity) where activity.id == .lock: metrics.lock
        case .compact: metrics.compact
        case let .peek(notice):
            switch notice.kind.wingWidth {
            case .regular: metrics.hud
            case .wide: metrics.wide
            case nil: metrics.peek
            }
        case let .hud(event): event.showsPercentage ? metrics.wide : metrics.hud
        case .expanded: metrics.expanded
        }
        guard !isExpanded else { return base }
        var size = base
        if isElevated { size = size + NotchMetrics.hoverBump }
        if isPressed { size = size - NotchMetrics.pressInset }
        return size
    }

    public var shellSize: CGSize {
        let size = restingSize + stretch
        return CGSize(width: max(0, size.width), height: max(0, size.height))
    }

    public var radii: NotchRadii {
        switch presentation {
        case .closed: .closed
        case let .compact(activity) where activity.id == .lock: .peek
        case .compact, .hud: .compact
        case let .peek(notice): notice.kind.wingWidth == nil ? .peek : .compact
        case .expanded: .expanded
        }
    }

    /// Region that counts as "on the notch": the target shape (not the in-flight one) plus flares and slop,
    /// so the hover state can't flap while the shape is still animating toward it.
    public var hitSize: CGSize {
        let slop = NotchMetrics.hitSlop
        let size = restingSize
        return CGSize(width: size.width + 2 * radii.top + 2 * slop, height: size.height + slop)
    }

    /// Out of the way for a full-screen app, except (by default) for volume and brightness.
    public var isHidden: Bool {
        guard isFullScreenActive, Defaults[.hideInFullScreen] else { return false }
        if case .hud = presentation, Defaults[.showHUDsInFullScreen] { return false }
        return true
    }

    /// Whether to draw the contrast outline, as far as settings and the backdrop go; views also leave it
    /// off while the notch is closed, where it should look like the hardware.
    public var wantsOutline: Bool {
        switch Defaults[.contrastOutline] {
        case .automatic: isBackdropDark
        case .always: true
        case .never: false
        }
    }

    public func setBackdropDark(_ dark: Bool) {
        guard dark != isBackdropDark else { return }
        isBackdropDark = dark
    }

    public func setFullScreen(_ active: Bool) {
        guard active != isFullScreenActive else { return }
        if active, Defaults[.hideInFullScreen] { collapse() }
        withAnimation(.smooth(duration: 0.3)) { isFullScreenActive = active }
    }

    public func update(metrics: NotchMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
    }

    // MARK: Pointer

    public func setHovering(_ inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        hoverTask?.cancel()

        switch (inside, isExpanded) {
        case (true, false):
            withAnimation(Motion.hoverBump) { isElevated = true }
            // Locked: no agenda or player for whoever is at the screen; the lock-screen widgets cover playback.
            if LockMonitor.shared.isLocked { return }
            // A peek with a button stays put so the button can be clicked; a click elsewhere still expands.
            if case let .peek(notice) = presentation, notice.hasActions { return }
            guard Defaults[.expandNotchOnHover] else { return }
            let dwell = Defaults[.hoverDuration]
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(dwell))
                guard !Task.isCancelled else { return }
                self?.expand()
            }
        case (false, false):
            withAnimation(Motion.hoverRelease) {
                isElevated = false
                isPressed = false
            }
        case (false, true):
            guard !isFileDragActive else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.exitGrace)
                guard !Task.isCancelled else { return }
                self?.collapse()
            }
        case (true, true):
            break
        }
    }

    public func setPressed(_ pressed: Bool) {
        guard pressed != isPressed, !isExpanded || !pressed else { return }
        withAnimation(Motion.hoverBump) { isPressed = pressed }
    }

    public func toggle() {
        isExpanded ? collapse() : expand()
    }

    // MARK: Swipes

    /// Two-finger scroll over the notch, in finger space (+x right, +y down).
    public func handleScroll(dx: Double, dy: Double, phase: SwipeTracker.Phase) {
        let output = swipe.update(dx: dx, dy: dy, phase: phase)
        // The tray scrolls sideways; leave horizontal swipes to it.
        if case .horizontal = output.axis, isExpanded, tab == .tray { return }

        if let action = output.triggered {
            withAnimation(Motion.gestureRelease) { stretch = .zero }
            perform(action)
        } else if phase == .ended || swipe.hasTriggered {
            if stretch != .zero {
                withAnimation(Motion.gestureRelease) { stretch = .zero }
            }
        } else {
            stretch = rubberBandStretch(for: output)
        }
    }

    private func rubberBandStretch(for output: SwipeTracker.Output) -> CGSize {
        let band = SwipeTracker.rubberBand(output.progress)
        switch output.axis {
        case .undecided:
            return .zero
        case .vertical where band > 0:
            // Pulling down: the notch follows the fingers, wanting to open.
            return isExpanded ? CGSize(width: 0, height: 10 * band) : CGSize(width: 10 * band, height: 18 * band)
        case .vertical:
            // Pushing up: the notch resists, wanting to shrink.
            return CGSize(width: 8 * band, height: 12 * band)
        case .horizontal:
            return CGSize(width: 12 * abs(band), height: 0)
        }
    }

    private func perform(_ action: SwipeTracker.Action) {
        Haptics.tick()
        switch action {
        case .pullDown:
            if !isExpanded, Defaults[.swipeToToggle] { expand() }
        case .pushUp:
            if isExpanded {
                if Defaults[.swipeToToggle] { collapse() }
            } else if case .compact = presentation, Defaults[.swipeToDismiss] {
                activities.dismissCurrent()
            } else if presentation == .closed, Defaults[.swipeToDismiss] {
                activities.restoreDismissed()
            }
        case .swipeLeft, .swipeRight:
            if Defaults[.swipeToSkip], onHorizontalSwipe?(action) == true { return }
            if case .compact = presentation, Defaults[.swipeToCycleActivity] {
                activities.cycle()
            }
        }
    }

    // MARK: Tabs and file drags

    public func select(_ tab: NotchTab) {
        guard tab != self.tab else { return }
        if isExpanded {
            withAnimation(Motion.tabSwitch) { self.tab = tab }
        } else {
            self.tab = tab
        }
    }

    /// A file drag reached the notch: open on the tray so it can be dropped there.
    public func fileDragEntered() {
        guard Defaults[.enableFileTray], Defaults[.openTrayOnDrag], !LockMonitor.shared.isLocked, !isHidden else { return }
        isFileDragActive = true
        hoverTask?.cancel()
        select(.tray)
        expand()
    }

    /// The drag wandered off without dropping: close again, as if the pointer had left.
    public func fileDragExited() {
        guard isFileDragActive else { return }
        isFileDragActive = false
        isHovering = false
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.exitGrace)
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    /// The mouse button came up. Hover events don't arrive during a drag, so resync from where it ended.
    public func fileDragEnded(pointerInside: Bool) {
        guard isFileDragActive else { return }
        isFileDragActive = false
        isHovering = pointerInside
        guard !pointerInside else { return }
        hoverTask?.cancel()
        // Linger long enough to see the drop land.
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    // MARK: Transitions

    public func expand() {
        guard !isExpanded, !LockMonitor.shared.isLocked, !isHidden else { return }
        hoverTask?.cancel()
        let interval = Log.signposter.beginInterval("expand")
        withAnimation(Motion.open, completionCriteria: .logicallyComplete) {
            isExpanded = true
            isElevated = false
            isPressed = false
        } completion: {
            Log.signposter.endInterval("expand", interval)
        }
        withAnimation(Motion.contentIn) { isContentVisible = true }
        Haptics.tick()
    }

    public func collapse() {
        guard isExpanded else { return }
        hoverTask?.cancel()
        let interval = Log.signposter.beginInterval("collapse")
        withAnimation(Motion.contentOut) { isContentVisible = false }
        withAnimation(Motion.close, completionCriteria: .logicallyComplete) {
            isExpanded = false
            isElevated = isHovering
        } completion: { [weak self] in
            Log.signposter.endInterval("collapse", interval)
            guard let self, !self.isExpanded, !Defaults[.rememberLastTab] else { return }
            self.tab = .home
        }
    }
}

extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }

    static func - (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
}
