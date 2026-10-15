import CalendarKit
import Defaults
import FileTray
import MediaKit
import NotchCore
import SwiftUI
import WeatherLite

/// Root of every notch window. The notch animates by morphing `NotchShape`; the window and canvas never
/// resize, which keeps layout out of the per-frame work. Each presentation's content is laid out once at
/// its final size and revealed by the shape's clip as the shell grows around it.
public struct NotchRootView: View {
    let controller: NotchController
    let media: MediaController
    let calendar: CalendarController
    let weather: WeatherController
    let tray: TrayStore
    let onOpenSettings: () -> Void

    @Default(.enableFileTray) private var trayEnabled
    // Read so the view redraws when they change; `controller.isHidden` reads the values itself.
    @Default(.hideInFullScreen) private var hideInFullScreen
    @Default(.showHUDsInFullScreen) private var showHUDsInFullScreen
    @Default(.contrastOutline) private var contrastOutline
    @State private var isDropTargeted = false

    public init(controller: NotchController, media: MediaController = .shared, calendar: CalendarController = .shared,
                weather: WeatherController = .shared, tray: TrayStore = .shared,
                onOpenSettings: @escaping () -> Void) {
        self.controller = controller
        self.media = media
        self.calendar = calendar
        self.weather = weather
        self.tray = tray
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        let radii = controller.radii
        let shape = NotchShape(bodySize: controller.shellSize, topRadius: radii.top, bottomRadius: radii.bottom)
        let metrics = controller.metrics
        let hit = controller.hitSize

        ZStack(alignment: .top) {
            shape.fill(.black)

            switch controller.presentation {
            case let .compact(activity):
                CompactWingsView(activity: activity, metrics: metrics, media: media, calendar: calendar)
                    .transition(.blurReplace)
            case let .peek(notice) where notice.kind.wingWidth != nil:
                StatusWingsView(notice: notice, metrics: metrics)
                    .transition(.blurReplace)
            case let .peek(notice):
                PeekView(notice: notice, metrics: metrics, media: media, calendar: calendar)
                    .transition(.blurReplace)
            case let .hud(event):
                HUDView(event: event, metrics: metrics)
                    .transition(.blurReplace)
            case .closed, .expanded:
                EmptyView()
            }

            ExpandedView(metrics: metrics, controller: controller, media: media, calendar: calendar, weather: weather,
                         tray: tray, isActive: controller.isContentVisible, isDropTargeted: isDropTargeted,
                         onOpenSettings: onOpenSettings)
                .frame(width: metrics.expanded.width, height: metrics.expanded.height)
                .opacity(controller.isContentVisible ? 1 : 0)
                .blur(radius: controller.isContentVisible ? 0 : 6)
                .scaleEffect(controller.isContentVisible ? 1 : 0.94, anchor: .top)
                .allowsHitTesting(controller.isContentVisible)

            ArtworkLayer(controller: controller, media: media)
        }
        .clipShape(shape)
        .overlay {
            // Hairline edge on dark backdrops. Not while closed (it should look like the hardware there), and
            // masked off along the screen's top edge, where the shape's flat top runs.
            shape.stroke(.white.opacity(0.18), lineWidth: 1)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 1.5)
                        Color.black
                    }
                }
                .opacity(controller.wantsOutline && controller.presentation != .closed ? 1 : 0)
                .animation(.smooth(duration: 0.3), value: controller.presentation == .closed)
                .allowsHitTesting(false)
        }
        // `.onHover` tracks the view's frame (not its content shape), so the frame *is* the hover region.
        // It snaps to the target size; the shape inside still springs because only the frame opts out.
        .animation(nil) { $0.frame(width: hit.width, height: hit.height, alignment: .top) }
        .contentShape(Rectangle())
        .onHover { controller.setHovering($0) }
        // The whole notch takes drops, closed or open: dragging a file onto it opens the tray.
        .onDrop(of: trayEnabled ? TrayStore.acceptedTypes : [], isTargeted: $isDropTargeted) { providers in
            Log.tray.info("Drop: \(providers.count) item(s)")
            controller.select(.tray)
            Task { await tray.add(providers) }
            return true
        }
        .onChange(of: isDropTargeted) {
            Log.tray.info("Drop target \(isDropTargeted ? "entered" : "exited", privacy: .public)")
            // Normally the drag monitor has opened the tray already; this covers drags it didn't see.
            if isDropTargeted { controller.fileDragEntered() }
        }
        .onTapGesture { controller.toggle() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in controller.setPressed(true) }
                .onEnded { _ in controller.setPressed(false) }
        )
        .opacity(controller.isHidden ? 0 : 1)
        .allowsHitTesting(!controller.isHidden)
        .animation(.smooth(duration: 0.3), value: controller.isHidden)
        .frame(width: NotchMetrics.canvas.width, height: NotchMetrics.canvas.height, alignment: .top)
    }
}
