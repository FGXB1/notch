import AppKit
import CalendarKit
import Defaults
import SwiftUI

struct CalendarPane: View {
    @Default(.enableCalendar) private var enabled
    @Default(.excludedCalendars) private var excluded
    @Default(.showAllDayEvents) private var showAllDay
    @Default(.upcomingEventLead) private var lead
    @Default(.disableActivityDuringEvents) private var disableDuringEvents
    @Default(.enableCalendarQuickPeek) private var quickPeek
    @Default(.beforeEventStarts) private var beforeEventStarts
    @Default(.timeBeforeEvent) private var timeBeforeEvent
    @Default(.whenEventIsStarting) private var whenEventIsStarting
    @Default(.calendarPeekDuration) private var peekDuration
    @Default(.notifyWhenTimeToLeave) private var timeToLeave
    @Default(.defaultTransportType) private var transport
    @Default(.timeToLeaveBuffer) private var leaveBuffer
    @Default(.timeToLeaveDuration) private var leaveDuration
    @Default(.useCalendarColor) private var useCalendarColor
    @Default(.useEventIndicators) private var useEventIndicators
    @Default(.calendarApp) private var calendarApp
    @Default(.playSoundOnCalendarEvent) private var playSound
    @Default(.playHourlyChime) private var hourlyChime
    private let calendar = CalendarController.shared

    var body: some View {
        Form {
            Section {
                Toggle("Calendar", isOn: $enabled)
                LabeledContent("Access") {
                    HStack {
                        Text(accessDescription)
                        if calendar.access == .notDetermined || calendar.access == .denied {
                            Button(calendar.access == .denied ? "Open System Settings…" : "Allow…",
                                   action: calendar.requestAccess)
                        }
                    }
                }
            }

            if calendar.access == .granted {
                Section("Calendars") {
                    ForEach(groups, id: \.self) { group in
                        LabeledContent(group) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(calendar.calendars.filter { $0.group == group }) { info in
                                    Toggle(isOn: visibility(of: info.id)) {
                                        Label {
                                            Text(info.title)
                                        } icon: {
                                            Circle()
                                                .fill(Color(.sRGB, red: info.color.red, green: info.color.green,
                                                            blue: info.color.blue))
                                                .frame(width: 9, height: 9)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                }
            }

            Section("Live activity") {
                Picker("Show upcoming event", selection: $lead) {
                    Text("When it starts").tag(0.0)
                    ForEach([5.0, 10, 15, 30, 60], id: \.self) { Text("\(Int($0)) min before").tag($0) }
                }
                Toggle("Hide once it starts", isOn: $disableDuringEvents)
            }

            Section("Quick peek") {
                Toggle("Quick peek", isOn: $quickPeek)
                Group {
                    Toggle("Before it starts", isOn: $beforeEventStarts)
                    Picker("How long before", selection: $timeBeforeEvent) {
                        ForEach([1.0, 2, 5, 10, 15], id: \.self) { Text("\(Int($0)) min").tag($0) }
                    }
                    .disabled(!beforeEventStarts)
                    Toggle("As it starts", isOn: $whenEventIsStarting)
                    LabeledSlider(title: "Duration", value: $peekDuration, range: 2...15, format: "%.0f s")
                }
                .disabled(!quickPeek)
            }

            Section("Time to leave") {
                Toggle("Remind me when it's time to leave", isOn: $timeToLeave)
                Group {
                    Picker("Travel by", selection: $transport) {
                        ForEach(TravelMode.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Extra time", selection: $leaveBuffer) {
                        ForEach([0.0, 5, 10, 15], id: \.self) { Text("\(Int($0)) min").tag($0) }
                    }
                    LabeledSlider(title: "Show reminder for", value: $leaveDuration, range: 3...30, format: "%.0f s")
                    LabeledContent("Location", value: calendar.locationAuthorization)
                }
                .disabled(!timeToLeave)
                Text("For events with an address or a place picked in Calendar. Travel times come from Apple Maps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Calendar colours", isOn: $useCalendarColor)
                Toggle("Dots on days with events", isOn: $useEventIndicators)
                Toggle("Show all-day events", isOn: $showAllDay)
                Picker("Open events in", selection: $calendarApp) {
                    ForEach(CalendarApp.allCases.filter(isInstalled), id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section("Sounds") {
                Toggle("Sound with event alerts", isOn: $playSound)
                Toggle("Chime on the hour", isOn: $hourlyChime)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
        .onAppear { calendar.scheduleRefresh() }
    }

    private var accessDescription: String {
        switch calendar.access {
        case .checking: "Checking…"
        case .notDetermined: "Not requested"
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .disabled: "Off"
        }
    }

    private var groups: [String] {
        var seen: [String] = []
        for info in calendar.calendars where !seen.contains(info.group) {
            seen.append(info.group)
        }
        return seen
    }

    private func visibility(of id: String) -> Binding<Bool> {
        Binding {
            !excluded.contains(id)
        } set: { visible in
            if visible { excluded.remove(id) } else { excluded.insert(id) }
        }
    }

    private func isInstalled(_ app: CalendarApp) -> Bool {
        app == .calendar || NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) != nil
    }
}
