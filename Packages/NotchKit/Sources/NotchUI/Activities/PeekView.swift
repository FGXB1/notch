import Activities
import CalendarKit
import Defaults
import MediaKit
import NotchCore
import SwiftUI

/// Quick peek: a notice that briefly drops the notch down to a single line, then retracts.
struct PeekView: View {
    let notice: Notice
    let metrics: NotchMetrics
    let media: MediaController
    let calendar: CalendarController

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.closed.height)
            content
                .frame(maxHeight: .infinity)
                .padding(.horizontal, NowPlayingLayout.peekPadding)
        }
        .frame(width: metrics.peek.width, height: metrics.peek.height)
    }

    @ViewBuilder private var content: some View {
        switch notice.kind {
        case let .nowPlaying(title, artist):
            HStack(spacing: 12) {
                // ArtworkLayer draws the artwork in this slot.
                Color.clear.frame(width: NowPlayingLayout.peekArtwork, height: NowPlayingLayout.peekArtwork)
                lines(title: title, subtitle: artist ?? "", tint: media.palette.accent)
                Spacer(minLength: 0)
                EqualizerView(isPlaying: media.nowPlaying?.isPlaying ?? false, tint: media.palette.accent)
            }
        case let .calendarEvent(id, title, start, moment):
            let event = calendar.event(id: id)
            let style = EventStyle(event?.color)
            HStack(spacing: 12) {
                EventBadge(symbol: moment.isLeave ? Defaults[.defaultTransportType].symbol : event?.symbol ?? "calendar",
                           style: style, size: NowPlayingLayout.peekArtwork)
                    .symbolEffect(.bounce, value: notice.id)
                lines(title: title, subtitle: Self.subtitle(for: moment, start: start, event: event), tint: style.tint)
                Spacer(minLength: 0)
                if let event, event.meetingLink != nil, !moment.isLeave {
                    JoinButton { calendar.join(event) }
                }
            }
        case .battery, .device, .focus:
            EmptyView() // shown in the wings by StatusWingsView
        case let .demo(symbol, title, subtitle):
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(DemoPalette.tint(for: symbol), in: .circle)
                    .symbolEffect(.bounce, value: notice.id)
                lines(title: title, subtitle: subtitle, tint: .white.opacity(0.6))
                Spacer(minLength: 0)
            }
        }
    }

    private static func subtitle(for moment: EventMoment, start: Date, event: CalendarEvent?) -> String {
        let place = event?.whereLabel.map { " · " + $0 } ?? ""
        switch moment {
        case .startingSoon:
            return "In \(EventFormat.minutes(start.timeIntervalSinceNow)) min" + place
        case .starting:
            return "Starting now" + place
        case let .timeToLeave(travelTime):
            return "Time to leave · " + EventFormat.travel(travelTime, mode: Defaults[.defaultTransportType])
        }
    }

    private func lines(title: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
    }
}

private extension EventMoment {
    var isLeave: Bool {
        if case .timeToLeave = self { true } else { false }
    }
}
