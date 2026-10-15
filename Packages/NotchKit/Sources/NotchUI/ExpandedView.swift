import CalendarKit
import Defaults
import FileTray
import MediaKit
import NotchCore
import SwiftUI
import WeatherLite

/// Content of the expanded notch. Laid out once at the expanded size; `NotchRootView` reveals it.
/// Two pages: Home (player and calendar) and the file tray, switched from the header or by dropping a file.
struct ExpandedView: View {
    let metrics: NotchMetrics
    let controller: NotchController
    let media: MediaController
    let calendar: CalendarController
    let weather: WeatherController
    let tray: TrayStore
    /// False while the notch is closed: pauses timelines so hidden content costs nothing.
    let isActive: Bool
    /// A drag is over the notch (the drop target is the whole notch, in `NotchRootView`).
    let isDropTargeted: Bool
    let onOpenSettings: () -> Void

    @Default(.enableFileTray) private var trayEnabled

    var body: some View {
        VStack(spacing: 0) {
            ExpandedHeader(tab: controller.tab, showsTabs: trayEnabled, trayIsEmpty: tray.items.isEmpty,
                           weather: weather, onSelect: controller.select, onOpenSettings: onOpenSettings)
                .frame(height: metrics.closed.height)

            ZStack(alignment: .top) {
                switch controller.tab {
                case .home:
                    home
                        .transition(.page(shift: -NowPlayingLayout.pageShift))
                case .tray:
                    TrayView(store: tray, isTargeted: isDropTargeted, isActive: isActive)
                        .transition(.page(shift: NowPlayingLayout.pageShift))
                }
            }
            .padding(.top, NowPlayingLayout.expandedTopGap)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, NowPlayingLayout.expandedPadding)
        .padding(.bottom, 14)
        .onChange(of: trayEnabled) {
            if !trayEnabled { controller.select(.home) }
        }
        .onChange(of: isActive) {
            if isActive { tray.prune() }
        }
    }

    private var home: some View {
        HStack(alignment: .top, spacing: NowPlayingLayout.columnSpacing) {
            Group {
                if let item = media.nowPlaying {
                    NowPlayingExpandedView(item: item, media: media, isActive: isActive)
                } else {
                    PlaceholderTile(symbol: "music.note", title: "Nothing playing", caption: "Play something anywhere")
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .transition(.blurReplace)

            if calendar.access != .disabled {
                CalendarColumn(calendar: calendar, isActive: isActive, weather: weather)
                    .frame(width: NowPlayingLayout.calendarColumnWidth)
                    .transition(.blurReplace)
            }
        }
    }
}

private extension AnyTransition {
    /// Pages slide a little toward their side of the header's switcher and soften as they go.
    static func page(shift: CGFloat) -> AnyTransition {
        .modifier(active: PageEffect(offset: shift, blur: 6, opacity: 0),
                  identity: PageEffect(offset: 0, blur: 0, opacity: 1))
    }
}

private struct PageEffect: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// Flanks the camera housing, which occupies the middle of the top row.
private struct ExpandedHeader: View {
    let tab: NotchTab
    let showsTabs: Bool
    let trayIsEmpty: Bool
    let weather: WeatherController
    let onSelect: (NotchTab) -> Void
    let onOpenSettings: () -> Void

    @Default(.showWeatherInHeader) private var showsWeather

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                if showsTabs {
                    TabSwitcher(selection: tab, trayIsEmpty: trayIsEmpty, onSelect: onSelect)
                    Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                } else {
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                }
                Spacer()
                if showsWeather, let forecast = weather.usable {
                    HeaderWeather(forecast: forecast)
                        .transition(.blurReplace)
                }
                Text(context.date, format: .dateTime.hour().minute())
                    .monospacedDigit()
                Button("Settings", systemImage: "gearshape.fill", action: onOpenSettings)
                    .buttonStyle(NotchButtonStyle(size: 24, fontSize: 12))
                    .opacity(0.7)
            }
        }
        .lineLimit(1)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
    }
}

/// Home | Tray, as a small capsule whose highlight slides between the two.
private struct TabSwitcher: View {
    let selection: NotchTab
    let trayIsEmpty: Bool
    let onSelect: (NotchTab) -> Void

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            button(.home, title: "Home", symbol: "house.fill")
            button(.tray, title: "Tray", symbol: trayIsEmpty ? "tray.fill" : "tray.full.fill")
        }
        .padding(2)
        .background(.white.opacity(0.08), in: .capsule)
    }

    private func button(_ tab: NotchTab, title: String, symbol: String) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.5))
                .frame(width: 26, height: 20)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct PlaceholderTile: View {
    let symbol: String
    let title: String
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 18, style: .continuous))
    }
}
