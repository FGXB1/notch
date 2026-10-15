import CalendarKit
import NotchCore
import SwiftUI

/// An event in the wings: its badge on the left; on the right a countdown until it starts, then a ring
/// that fills as it runs. Events start on the minute, so a once-a-minute timeline keeps both exact.
struct CalendarWings: View {
    let event: CalendarEvent?
    let metrics: NotchMetrics

    var body: some View {
        TimelineView(.everyMinute) { context in
            WingsLayout(metrics: metrics, wing: metrics.compactWing) {
                if let event {
                    EventBadge(symbol: event.symbol, style: EventStyle(event.color), size: metrics.wingGlyph,
                               isPulsing: isFinalMinute(event, at: context.date))
                }
            } trailing: {
                if let event {
                    trailing(for: event, at: context.date)
                }
            }
        }
    }

    @ViewBuilder private func trailing(for event: CalendarEvent, at now: Date) -> some View {
        let style = EventStyle(event.color)
        if event.start > now {
            let countdown = EventFormat.countdown(to: event.start, at: now)
            Text(countdown)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(style.tint)
                .contentTransition(.numericText(countsDown: true))
                .animation(.smooth(duration: 0.4), value: countdown)
        } else {
            ProgressRing(progress: event.progress(at: now), tint: style.tint, size: metrics.wingGlyph * 0.8)
        }
    }

    private func isFinalMinute(_ event: CalendarEvent, at now: Date) -> Bool {
        event.start > now && event.start.timeIntervalSince(now) <= 60
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    let size: CGFloat
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.6), value: progress)
    }
}
