import Activities
import AppKit
import Defaults
import IOKit.pwr_mgt
import MediaKit
import NotchCore
import NotchUI
import Observation
import SwiftUI

/// Everything that changes when the Mac locks: the widget panel above loginwindow, the padlock in the
/// notch, lock/unlock sounds, and keeping the display awake for music.
@MainActor
final class LockScreenController {
    /// Collapses expanded notches the moment the Mac locks.
    var onLock: () -> Void = {}

    private let space: PrivateSpace
    private let lock = LockMonitor.shared
    private let activities = ActivityCenter.shared
    private let model = LockScreenModel()
    private var panel: NotchPanel?
    private var hideTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?
    private var displayAssertion = IOPMAssertionID(0)
    private var settingsTask: Task<Void, Never>?

    private static let soundDirectory = "/System/Library/Frameworks/SecurityInterface.framework/Versions/A/Resources/"
    private let lockSound = NSSound(contentsOfFile: soundDirectory + "lock.aif", byReference: true)
    private let unlockSound = NSSound(contentsOfFile: soundDirectory + "unlock.aif", byReference: true)

    /// Top of the widgets, as a fraction of the screen height (below loginwindow's clock).
    private static let topFraction: CGFloat = 0.3
    private static let panelSize = CGSize(width: LockScreenView.width + 60, height: 420)

    init(space: PrivateSpace) {
        self.space = space
    }

    /// Whether screenshots and recordings can see the widgets.
    var sharingType: NSWindow.SharingType = .readOnly {
        didSet { panel?.sharingType = sharingType }
    }

    func start() {
        lock.start()
        lock.onEvent { [weak self] event in self?.handle(event) }
        if lock.isLocked {
            handle(.locked)
        }
        observePlayback()
        settingsTask = Task { [weak self] in
            for await _ in Defaults.updates([.nowPlayingWidgetOffset, .enableLockScreen], initial: false) {
                self?.reposition()
            }
        }
    }

    /// Shows the widgets on the desktop for a few seconds, to tune style and offset without locking.
    func preview() {
        guard !lock.isLocked else { return }
        show()
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.lock.isLocked else { return }
            self.hide()
        }
    }

    // MARK: Events

    private func handle(_ event: LockEvent) {
        switch event {
        case .locked:
            unlockTask?.cancel()
            previewTask?.cancel()
            onLock()
            activities.setLocked(true)
            lock.isIndicatorOpen = false
            if Defaults[.showLockIndicator] {
                // Lowest priority: music and the rest still win the wings; the padlock fills an idle notch.
                activities.upsert(.lock, priority: -1)
            }
            if Defaults[.playSoundOnLock] { play(lockSound) }
            show()
        case .unlocked:
            activities.setLocked(false)
            if Defaults[.playSoundOnUnlock] { play(unlockSound) }
            hide()
            animateUnlock()
        case .screenSaverStarted:
            if lock.isLocked, !Defaults[.showOnScreenSaver] { hide() }
        case .screenSaverStopped:
            if lock.isLocked { show() }
        }
        updateDisplayAssertion()
    }

    /// The padlock takes the notch, opens, then retracts, like Face ID unlocking the iPhone.
    private func animateUnlock() {
        guard Defaults[.showLockIndicator], activities.isLive(.lock) else {
            activities.end(.lock)
            return
        }
        activities.upsert(.lock, priority: 3)
        unlockTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.35)) { self.lock.isIndicatorOpen = true }
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self.activities.end(.lock)
        }
    }

    // MARK: Panel

    private func show() {
        guard Defaults[.enableLockScreen], let screen = NSScreen.screens.first else { return }
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        place(panel, on: screen)
        model.wallpaper.load(for: screen)
        panel.orderFrontRegardless()
        space.add(panel)
        withAnimation(.smooth(duration: 0.45)) { model.isVisible = true }
    }

    private func hide() {
        guard let panel, model.isVisible else { return }
        withAnimation(.smooth(duration: 0.3)) { model.isVisible = false }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, self?.model.isVisible == false else { return }
            panel.orderOut(nil)
        }
    }

    private func reposition() {
        guard let panel, model.isVisible, let screen = NSScreen.screens.first else { return }
        if !Defaults[.enableLockScreen] {
            hide()
            return
        }
        place(panel, on: screen)
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(frame: CGRect(origin: .zero, size: Self.panelSize))
        panel.sharingType = sharingType
        let hostingView = NoSafeAreaHostingView(rootView: LockScreenView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    private func place(_ panel: NotchPanel, on screen: NSScreen) {
        let size = Self.panelSize
        let top = screen.frame.maxY - screen.frame.height * Self.topFraction - Defaults[.nowPlayingWidgetOffset]
        let frame = CGRect(x: (screen.frame.midX - size.width / 2).rounded(), y: (top - size.height).rounded(),
                           width: size.width, height: size.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        model.screenSize = screen.frame.size
        model.panelOrigin = CGPoint(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY)
    }

    // MARK: Sound and power

    private func play(_ sound: NSSound?) {
        sound?.stop()
        sound?.play()
    }

    /// Re-arms itself on every change to playback, so keep-awake follows play/pause while locked.
    private func observePlayback() {
        withObservationTracking {
            _ = MediaController.shared.nowPlaying?.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateDisplayAssertion()
                self?.observePlayback()
            }
        }
    }

    /// While locked with music playing (and "Keep awake" on), stop the display from idling to sleep.
    private func updateDisplayAssertion() {
        let wanted = Defaults[.keepAwake] && lock.isLocked && MediaController.shared.nowPlaying?.isPlaying == true
        if wanted, displayAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Notch: music on the lock screen" as CFString, &displayAssertion)
        } else if !wanted, displayAssertion != 0 {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
        }
    }
}
