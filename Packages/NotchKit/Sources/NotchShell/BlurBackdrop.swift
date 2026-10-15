import AppKit
import Defaults
import NotchCore
import Observation

/// A soft blur around the open notch that fades out with distance, so the black shape melts into whatever
/// is behind it instead of ending in a hard edge. Lives in its own mouse-transparent window just under the
/// notch, shown only while the notch is open (an invisible blur still costs the window server work).
///
/// The window stays out of the menu bar entirely, starting at its bottom edge. Masking the blur out of the
/// menu bar wasn't enough: a blurring window over it left a dark smudge beside the notch regardless.
@MainActor
final class BlurBackdrop {
    /// How far the blur reaches past the open notch before it has faded out completely.
    static let reach: CGFloat = 60
    /// The blur eases in over this much below the menu bar, so it doesn't start on a line.
    static let topFade: CGFloat = 20

    private let controller: NotchController
    private var canvas: CGRect
    private let panel: NotchPanel
    private let blurView = FadingBlurView()
    private var hideTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var isShown = false

    init(controller: NotchController, frame: CGRect) {
        self.controller = controller
        canvas = frame
        panel = NotchPanel(frame: Self.panelFrame(canvas: frame, metrics: controller.metrics))
        // Under the notch in every state: below the drag image too, where the notch steps down to during
        // file drags (see `DragMonitor`), but above ordinary windows, the menu bar and pop-up menus.
        panel.level = NSWindow.Level(rawValue: NotchPanel.dragLevel.rawValue - 1)
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        let container = NSView(frame: CGRect(origin: .zero, size: panel.frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(blurView)
        panel.contentView = container
        layoutBlur()
        observe()
        settingsTask = Task { [weak self] in
            for await _ in Defaults.updates(.progressiveBlur, initial: false) {
                self?.apply()
            }
        }
    }

    func update(frame: CGRect) {
        canvas = frame
        layoutBlur()
    }

    var sharingType: NSWindow.SharingType {
        get { panel.sharingType }
        set { panel.sharingType = newValue }
    }

    func close() {
        hideTask?.cancel()
        settingsTask?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    /// The notch's canvas, minus the menu bar strip at its top.
    private static func panelFrame(canvas: CGRect, metrics: NotchMetrics) -> CGRect {
        CGRect(x: canvas.minX, y: canvas.minY, width: canvas.width, height: canvas.height - metrics.closed.height)
    }

    /// Centred under the open notch, from the menu bar's bottom edge to `reach` below the notch.
    private func layoutBlur() {
        let metrics = controller.metrics
        let panelFrame = Self.panelFrame(canvas: canvas, metrics: metrics)
        if panel.frame != panelFrame {
            panel.setFrame(panelFrame, display: false)
        }
        let menuBar = metrics.closed.height
        let expanded = metrics.expanded
        let reach = Self.reach
        let size = CGSize(width: expanded.width + 2 * reach, height: expanded.height - menuBar + reach)
        let frame = CGRect(x: ((panelFrame.width - size.width) / 2).rounded(), y: panelFrame.height - size.height,
                           width: size.width, height: size.height)
        guard blurView.frame != frame else { return }
        blurView.frame = frame
        // The notch in the view's own top-left coordinates: it starts above the view, in the menu bar.
        let notch = CGRect(x: reach, y: -menuBar, width: expanded.width, height: expanded.height)
        blurView.setMask(size: size, notch: notch, cornerRadius: NotchRadii.expanded.bottom, reach: reach,
                         topFade: Self.topFade)
    }

    private func observe() {
        withObservationTracking {
            _ = controller.isExpanded
            _ = controller.isHidden
            _ = controller.metrics
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.layoutBlur()
                self?.apply()
                self?.observe()
            }
        }
    }

    private func apply() {
        let visible = controller.isExpanded && !controller.isHidden && Defaults[.progressiveBlur]
        guard visible != isShown else { return }
        isShown = visible
        hideTask?.cancel()
        if visible {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled, let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

/// A behind-window blur faded out by a mask: full at the notch's edge, nothing `reach` points away, with a
/// smooth (zero-slope) start and finish so there's no visible boundary. Uses only public API, so the system
/// honours the mask however it updates the view. Always the dark material: around a black notch it reads
/// as a soft shadow, where the light one would be a white haze.
final class FadingBlurView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        blendingMode = .behindWindow
        material = .hudWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setMask(size: CGSize, notch: CGRect, cornerRadius: CGFloat, reach: CGFloat, topFade: CGFloat) {
        guard let mask = BlurMask.make(size: size, notch: notch, cornerRadius: cornerRadius, reach: reach,
                                       topFade: topFade) else { return }
        maskImage = NSImage(cgImage: mask, size: size)
    }
}
