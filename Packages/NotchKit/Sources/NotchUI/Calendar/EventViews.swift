import CalendarKit
import Defaults
import SwiftUI

/// Colors for one event on the black notch. With "Calendar colours" off everything is white.
struct EventStyle {
    /// Solid fills: badges, color bars, dots.
    var fill: Color
    /// Text and strokes; lifted toward white when the calendar color is too dark to read.
    var tint: Color
    /// Glyphs drawn on top of `fill`.
    var onFill: Color

    init(_ color: EventColor?, useCalendarColor: Bool = Defaults[.useCalendarColor]) {
        guard useCalendarColor, let color else {
            self.init(fill: .white, tint: .white, onFill: .black)
            return
        }
        let base = Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
        self.init(fill: base, tint: color.luminance < 0.35 ? base.mix(with: .white, by: 0.45) : base,
                  onFill: color.luminance > 0.6 ? .black : .white)
    }

    private init(fill: Color, tint: Color, onFill: Color) {
        self.fill = fill
        self.tint = tint
        self.onFill = onFill
    }
}

extension CalendarEvent {
    /// What kind of event this is at a glance: a call, a place, or neither.
    var symbol: String {
        if meetingLink != nil { return "video.fill" }
        if physicalLocation != nil { return "mappin" }
        return "calendar"
    }

    /// "Zoom", or the place, for subtitles.
    var whereLabel: String? {
        meetingLink?.service.name ?? physicalLocation
    }
}

/// The event's counterpart to album artwork: a rounded square in the calendar's color.
struct EventBadge: View {
    let symbol: String
    let style: EventStyle
    let size: CGFloat
    /// Breathes gently to draw the eye in the last minute before the start.
    var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(style.fill)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(style.onFill)
            }
            .frame(width: size, height: size)
            .phaseAnimator(isPulsing ? [false, true] : [false]) { content, isUp in
                content
                    .scaleEffect(isUp ? 1.1 : 1)
                    .brightness(isUp ? 0.15 : 0)
            } animation: { _ in
                .easeInOut(duration: 0.75)
            }
    }
}

/// Green capsule that joins the call, as on an incoming FaceTime.
struct JoinButton: View {
    let action: () -> Void
    var compact = false

    var body: some View {
        Button(action: action) {
            if compact {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 20)
            } else {
                Label("Join", systemImage: "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 26)
            }
        }
        .buttonStyle(JoinButtonStyle())
        .help("Join")
    }
}

private struct JoinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .background(Color.green.mix(with: .white, by: isHovering ? 0.12 : 0), in: .capsule)
                .contentShape(.capsule)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.snappy(duration: 0.2), value: configuration.isPressed)
                .animation(.smooth(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

/// Plain row/cell button for the dark notch: a soft rounded highlight on hover.
struct RowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct Styled: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(.white.opacity(configuration.isPressed ? 0.12 : isHovering ? 0.07 : 0),
                            in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                .animation(.smooth(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

enum EventFormat {
    /// "12m", "2h"; "now" once it has started.
    static func countdown(to start: Date, at now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    static func minutes(_ interval: TimeInterval) -> Int {
        max(1, Int((interval / 60).rounded(.up)))
    }

    static func travel(_ interval: TimeInterval, mode: TravelMode) -> String {
        let minutes = minutes(interval)
        let duration = minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
        return switch mode {
        case .drive: "\(duration) drive"
        case .transit: "\(duration) by transit"
        case .walk: "\(duration) walk"
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Tomorrow", else the short weekday ("Thu"); the agenda only reaches a week ahead.
    static func day(_ date: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              !calendar.isDate(date, inSameDayAs: tomorrow) else { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}
