import CalendarKit
import Defaults
import SwiftUI
import WeatherLite

/// The expanded notch's calendar: a week strip over the selected day's agenda.
struct CalendarColumn: View {
    let calendar: CalendarController
    /// False while the notch is closed; the selection snaps back to today then.
    let isActive: Bool
    var weather: WeatherController = .shared

    static let rows = 3

    /// nil means today, so the selection follows midnight.
    @State private var selectedDay: Date?
    @Default(.useEventIndicators) private var useEventIndicators
    @Default(.showAllDayEvents) private var showAllDay
    @Default(.showWeatherOnClearDays) private var showWeather
    // Read here so the column redraws when it changes; `EventStyle` reads the value itself.
    @Default(.useCalendarColor) private var useCalendarColor

    var body: some View {
        switch calendar.access {
        case .granted:
            agenda
        case .notDetermined, .denied:
            CalendarPermissionView(isDenied: calendar.access == .denied, onRequest: calendar.requestAccess)
        case .checking, .disabled:
            Color.clear
        }
    }

    private var agenda: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let today = Calendar.current.startOfDay(for: now)
            let selected = selectedDay.map { max($0, today) } ?? today

            VStack(spacing: 6) {
                WeekStrip(today: today, selected: selected, events: calendar.events,
                          showsIndicators: useEventIndicators, usesCalendarColor: useCalendarColor) { day in
                    withAnimation(.smooth(duration: 0.3)) { selectedDay = day }
                }
                AgendaList(items: Agenda.items(for: selected, in: calendar.events, now: now, rows: Self.rows,
                                               showAllDay: showAllDay),
                           day: selected, now: now, calendar: calendar,
                           forecast: showWeather ? weather.usable : nil)
                    .id(selected)
                    .transition(.blurReplace)
            }
        }
        .onChange(of: isActive) {
            if !isActive { selectedDay = nil }
        }
    }
}

private struct WeekStrip: View {
    let today: Date
    let selected: Date
    let events: [CalendarEvent]
    let showsIndicators: Bool
    let usesCalendarColor: Bool
    let onSelect: (Date) -> Void

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 1) {
            ForEach(days, id: \.self) { day in
                Button { onSelect(day) } label: {
                    cell(for: day)
                }
                .buttonStyle(RowButtonStyle(cornerRadius: 9))
            }
        }
    }

    private var days: [Date] {
        (0..<CalendarController.daysShown).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private func cell(for day: Date) -> some View {
        let isToday = day == today
        let isSelected = day == selected
        return VStack(spacing: 2) {
            Text(day, format: .dateTime.weekday(.narrow))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(day, format: .dateTime.day())
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? (isToday ? .white : .black) : isToday ? .red : .white)
                .frame(width: 22, height: 22)
                .background {
                    if isSelected {
                        Circle()
                            .fill(isToday ? Color.red : .white)
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
            HStack(spacing: 2) {
                if showsIndicators {
                    ForEach(Array(indicatorColors(on: day).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }

    /// One dot per calendar with events that day, up to three.
    private func indicatorColors(on day: Date) -> [Color] {
        var seen: [EventColor] = []
        for event in events.occurring(on: day) where !seen.contains(event.color) {
            seen.append(event.color)
        }
        return seen.prefix(3).map { EventStyle($0, useCalendarColor: usesCalendarColor).fill.opacity(0.9) }
    }
}

private struct AgendaList: View {
    let items: [Agenda.Item]
    let day: Date
    let now: Date
    let calendar: CalendarController
    let forecast: Forecast?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if case let .caption(text) = items.first, let forecast, let dayForecast = forecast.day(for: day) {
                // The forecast card is two rows tall, so one fewer of what's coming up fits under it.
                WeatherDayCard(caption: text, day: dayForecast,
                               current: Calendar.current.isDate(day, inSameDayAs: now) ? forecast.current : nil)
                    .padding(.bottom, 2)
                ForEach(items.dropFirst().prefix(CalendarColumn.rows - 2)) { item in
                    row(for: item)
                }
            } else {
                ForEach(items) { item in
                    row(for: item)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func row(for item: Agenda.Item) -> some View {
        switch item {
        case let .event(event, isLaterDay):
            EventRow(event: event, isLaterDay: isLaterDay, now: now, travel: calendar.travel[event.id],
                     onOpen: { calendar.open(event) }, onJoin: { calendar.join(event) })
        case let .allDay(events):
            AllDayRow(events: events) {
                calendar.open(events.count == 1 ? events.first : nil, day: day)
            }
        case let .more(count):
            Button { calendar.open(nil, day: day) } label: {
                Text(count == 1 ? "1 more event" : "\(count) more events")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            }
            .buttonStyle(RowButtonStyle())
        case let .caption(text):
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .frame(height: 22, alignment: .leading)
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let isLaterDay: Bool
    let now: Date
    let travel: TravelEstimate?
    let onOpen: () -> Void
    let onJoin: () -> Void

    var body: some View {
        let style = EventStyle(event.color)
        let isOngoing = event.isOngoing(at: now)
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(style.fill)
                    .frame(width: 3, height: 21)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    detail
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isOngoing ? style.tint : .white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: showsJoin ? 34 : 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 27)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
        .overlay(alignment: .trailing) {
            if showsJoin {
                JoinButton(action: onJoin, compact: true)
                    .padding(.trailing, 4)
            }
        }
        .help("Open in \(Defaults[.calendarApp].title)")
    }

    private var showsJoin: Bool {
        event.meetingLink != nil && event.end > now && !isLaterDay
    }

    private var detail: Text {
        let times = if event.isOngoing(at: now) {
            "Now · until \(EventFormat.time(event.end))"
        } else if isLaterDay {
            "\(EventFormat.day(event.start, relativeTo: now)) \(EventFormat.time(event.start))"
        } else {
            "\(EventFormat.time(event.start)) – \(EventFormat.time(event.end))"
        }
        guard let travel, event.start > now else { return Text(times) }
        return Text("\(times)  \(Image(systemName: travel.mode.symbol)) \(EventFormat.minutes(travel.travelTime)) min")
    }
}

private struct AllDayRow: View {
    let events: [CalendarEvent]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                VStack(spacing: 2) {
                    ForEach(events.prefix(3)) { event in
                        Capsule().fill(EventStyle(event.color).fill)
                    }
                }
                .frame(width: 3, height: 21)
                VStack(alignment: .leading, spacing: 1) {
                    Text(events.count == 1 ? events[0].title : "\(events.count) all-day events")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(events.count == 1 ? "All day" : events.map(\.title).joined(separator: ", "))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 27)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
    }
}

private struct CalendarPermissionView: View {
    let isDenied: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calendar", systemImage: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(isDenied ? "Allow Notch in System Settings to see your upcoming events."
                : "Notch needs your permission to display your upcoming calendar events.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRequest) {
                Text(isDenied ? "Open System Settings" : "Allow Access")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(.white.opacity(0.14), in: .capsule)
            }
            .buttonStyle(RowButtonStyle(cornerRadius: 12))
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
