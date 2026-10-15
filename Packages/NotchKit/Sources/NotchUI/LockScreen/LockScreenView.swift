import CalendarKit
import Defaults
import MediaKit
import NotchCore
import SwiftUI
import SystemKit
import WeatherLite

/// Widgets on the lock screen: the Now Playing card, then a row of small widgets (Battery, Headphones,
/// Focus, and the next event if allowed). Hosted in its own panel in the private space above loginwindow.
public struct LockScreenView: View {
    public static let width: CGFloat = 380
    static let canvas = "lockCanvas"

    let model: LockScreenModel
    let media: MediaController
    let calendar: CalendarController
    let battery: BatteryMonitor
    let focus: FocusMonitor
    let devices: DeviceMonitor
    let hud: HUDController
    let weather: WeatherController

    @Default(.lockScreenWidgetStyle) private var style
    @Default(.showVolumeControl) private var showVolumeControl
    @Default(.allowNowPlayingWidgetWhenLocked) private var showNowPlaying
    @Default(.allowBatteryWidgetWhenLocked) private var showBattery
    @Default(.allowFocusWidgetWhenLocked) private var showFocus
    @Default(.allowConnectivityWidgetWhenLocked) private var showHeadphones
    @Default(.allowCalendarWidgetWhenLocked) private var showCalendar
    @Default(.allowWeatherWidgetWhenLocked) private var showWeather

    public init(model: LockScreenModel, media: MediaController = .shared, calendar: CalendarController = .shared,
                battery: BatteryMonitor = .shared, focus: FocusMonitor = .shared, devices: DeviceMonitor = .shared,
                hud: HUDController = .shared, weather: WeatherController = .shared) {
        self.model = model
        self.media = media
        self.calendar = calendar
        self.battery = battery
        self.focus = focus
        self.devices = devices
        self.hud = hud
        self.weather = weather
    }

    public var body: some View {
        let backdrop = Backdrop(style: style, wallpaper: model.wallpaper, screenSize: model.screenSize,
                                panelOrigin: model.panelOrigin)
        VStack(spacing: 14) {
            if showNowPlaying, let item = media.nowPlaying {
                NowPlayingWidget(item: item, media: media, hud: hud, showsVolume: showVolumeControl)
                    .widgetBackground(.rect(cornerRadius: 28, style: .continuous), backdrop: backdrop)
                    .transition(.blurReplace)
            }
            let small = smallWidgets
            if !small.isEmpty {
                HStack(spacing: 12) {
                    ForEach(small) { widget in
                        view(for: widget)
                            .widgetBackground(.rect(cornerRadius: 24, style: .continuous), backdrop: backdrop)
                    }
                }
                .transition(.blurReplace)
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .coordinateSpace(.named(Self.canvas))
        .opacity(model.isVisible ? 1 : 0)
        .scaleEffect(model.isVisible ? 1 : 0.94, anchor: .top)
        .blur(radius: model.isVisible ? 0 : 10)
        .animation(.smooth(duration: 0.35), value: media.nowPlaying == nil)
    }

    // MARK: Small widgets

    private enum SmallWidget: Identifiable {
        case calendar(CalendarEvent)
        case battery(BatteryStatus)
        case headphones(ConnectedDevice)
        case focus(FocusMode)
        case weather(Forecast)

        var id: String {
            switch self {
            case .calendar: "calendar"
            case .battery: "battery"
            case .headphones: "headphones"
            case .focus: "focus"
            case .weather: "weather"
            }
        }

        /// Width in slots: 1 for a square, 2 for the calendar.
        var slots: Int {
            if case .calendar = self { 2 } else { 1 }
        }
    }

    @ViewBuilder private func view(for widget: SmallWidget) -> some View {
        switch widget {
        case let .calendar(event): NextEventWidget(event: event)
        case let .battery(status): BatteryWidget(status: status)
        case let .headphones(device): HeadphonesWidget(device: device)
        case let .focus(mode): FocusWidget(mode: mode)
        case let .weather(forecast): WeatherWidget(forecast: forecast)
        }
    }

    /// In order of preference, as many as fit in four slots.
    private var smallWidgets: [SmallWidget] {
        var candidates: [SmallWidget] = []
        if showCalendar, calendar.access == .granted, let next = nextEvent {
            candidates.append(.calendar(next))
        }
        if showBattery, let status = battery.status {
            candidates.append(.battery(status))
        }
        if showWeather, let forecast = weather.usable {
            candidates.append(.weather(forecast))
        }
        if showHeadphones, let device = devices.current {
            candidates.append(.headphones(device))
        }
        if showFocus, let mode = focus.active {
            candidates.append(.focus(mode))
        }
        var used = 0
        return candidates.filter { widget in
            guard used + widget.slots <= 4 else { return false }
            used += widget.slots
            return true
        }
    }

    private var nextEvent: CalendarEvent? {
        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)
        return calendar.events.first { !$0.isAllDay && !$0.isDeclined && $0.end > now && $0.start < horizon }
    }
}

// MARK: - Backdrop

struct Backdrop {
    var style: LockWidgetStyle
    var wallpaper: LockWallpaper
    var screenSize: CGSize
    var panelOrigin: CGPoint
}

private extension View {
    func widgetBackground<S: InsettableShape>(_ shape: S, backdrop: Backdrop) -> some View {
        modifier(WidgetBackground(shape: shape, backdrop: backdrop))
    }
}

private struct WidgetBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let backdrop: Backdrop

    func body(content: Content) -> some View {
        switch backdrop.style {
        case .frosted:
            content
                .background {
                    ZStack {
                        WallpaperSlice(image: backdrop.wallpaper.blurred, backdrop: backdrop)
                        Color.black.opacity(backdrop.wallpaper.blurred == nil ? 0.55 : 0.3)
                    }
                    .clipShape(shape)
                }
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
        case .glass:
            content
                .glassEffect(.regular, in: shape)
                .background {
                    WallpaperSlice(image: backdrop.wallpaper.sharp, backdrop: backdrop)
                        .clipShape(shape)
                }
        case .clear:
            content
                .shadow(color: .black.opacity(0.5), radius: 10, y: 2)
        }
    }
}

/// The part of the wallpaper that's behind this view on screen: the whole picture laid out aspect-fill at
/// screen size (as the lock screen draws it), shifted by this view's position on the screen.
private struct WallpaperSlice: View {
    let image: NSImage?
    let backdrop: Backdrop

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(LockScreenView.canvas))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: backdrop.screenSize.width, height: backdrop.screenSize.height)
                    .offset(x: -(backdrop.panelOrigin.x + frame.minX), y: -(backdrop.panelOrigin.y + frame.minY))
            } else {
                Color.black.opacity(0.25)
            }
        }
    }
}

// MARK: - Now Playing

private struct NowPlayingWidget: View {
    let item: NowPlaying
    let media: MediaController
    let hud: HUDController
    let showsVolume: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ArtworkImage(media: media)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(text: item.title, font: .system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(item.artist ?? "")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            ScrubberView(item: item, tint: .white, onSeek: media.seek)
            HStack(spacing: 30) {
                Button("Previous", systemImage: "backward.fill", action: media.previous)
                    .buttonStyle(NotchButtonStyle(size: 40, fontSize: 20))
                Button(item.isPlaying ? "Pause" : "Play", systemImage: item.isPlaying ? "pause.fill" : "play.fill",
                       action: media.togglePlayPause)
                    .contentTransition(.symbolEffect(.replace))
                    .buttonStyle(NotchButtonStyle(size: 48, fontSize: 28))
                Button("Next", systemImage: "forward.fill", action: media.next)
                    .buttonStyle(NotchButtonStyle(size: 40, fontSize: 20))
            }
            if showsVolume {
                VolumeSlider(level: hud.volume, onChange: hud.setVolume)
            }
        }
        .padding(18)
    }
}

private struct VolumeSlider: View {
    let level: Double
    let onChange: (Double) -> Void
    @State private var dragLevel: Double?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11, weight: .semibold))
            GeometryReader { proxy in
                let value = dragLevel ?? level
                Capsule()
                    .fill(.white.opacity(0.22))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: max(6, proxy.size.width * value))
                    }
                    .frame(height: dragLevel == nil ? 6 : 9)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let value = min(1, max(0, gesture.location.x / proxy.size.width))
                                withAnimation(.snappy(duration: 0.12)) { dragLevel = value }
                                onChange(value)
                            }
                            .onEnded { _ in
                                withAnimation(.snappy(duration: 0.2)) { dragLevel = nil }
                            }
                    )
            }
            .frame(height: 18)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.75))
    }
}

// MARK: - Small widgets

/// A square lock-screen widget: a gauge or symbol over a one-line caption.
private struct SquareWidget<Center: View>: View {
    let caption: String
    @ViewBuilder let center: Center

    var body: some View {
        VStack(spacing: 6) {
            center
                .frame(width: 44, height: 44)
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 6)
        .frame(width: 84, height: 84)
    }
}

private struct BatteryWidget: View {
    let status: BatteryStatus

    var body: some View {
        let tint: Color = status.isCharging ? .green : status.level <= 0.2 ? .red : .white
        SquareWidget(caption: status.level.formatted(.percent.precision(.fractionLength(0)))) {
            ZStack {
                ProgressRing(progress: status.level, tint: tint, size: 42, lineWidth: 4)
                Image(systemName: status.isCharging ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: status.isCharging ? 15 : 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct HeadphonesWidget: View {
    let device: ConnectedDevice

    var body: some View {
        SquareWidget(caption: device.battery?.formatted(.percent.precision(.fractionLength(0))) ?? "Connected") {
            ZStack {
                if let level = device.battery {
                    ProgressRing(progress: level, tint: level <= 0.2 ? .red : .green, size: 42, lineWidth: 4)
                }
                Image(systemName: device.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct FocusWidget: View {
    let mode: FocusMode

    var body: some View {
        SquareWidget(caption: mode.name) {
            Image(systemName: mode.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(FocusTint.color(mode.tint))
        }
    }
}

private struct WeatherWidget: View {
    let forecast: Forecast
    @Default(.temperatureUnit) private var unit

    var body: some View {
        VStack(spacing: 2) {
            WeatherSymbol(name: forecast.current.symbol, size: 20)
                .frame(height: 24)
            Text(TemperatureFormat.degrees(forecast.current.temperature, unit: unit))
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(forecast.place ?? forecast.current.condition.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 6)
        .frame(width: 84, height: 84)
    }
}

private struct NextEventWidget: View {
    let event: CalendarEvent

    var body: some View {
        let style = EventStyle(event.color)
        HStack(spacing: 10) {
            Capsule()
                .fill(style.fill)
                .frame(width: 4)
                .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 3) {
                TimelineView(.everyMinute) { context in
                    Text(when(at: context.date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(style.tint)
                }
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(EventFormat.time(event.start)) – \(EventFormat.time(event.end))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 84 * 2 + 12, height: 84)
    }

    private func when(at now: Date) -> String {
        if event.isOngoing(at: now) { return "NOW" }
        let minutes = EventFormat.minutes(event.start.timeIntervalSince(now))
        if minutes < 60 { return "IN \(minutes) MIN" }
        return Calendar.current.isDate(event.start, inSameDayAs: now) ? "LATER TODAY" : "TOMORROW"
    }
}
