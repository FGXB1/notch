import Activities
import AppKit
import Defaults
import EventKit
import NotchCore
import Observation
import SwiftUI

/// Calendar for the whole app: keeps a week of events fresh, puts the relevant one in the wings, peeks
/// before and at its start, and tells you when to leave. Nothing polls: it sleeps until the next moment
/// that can change what's shown (`EventSchedule.nextBoundary`) and wakes early for store, clock, time
/// zone, day and wake notifications.
@MainActor
@Observable
public final class CalendarController {
    public enum Access: Equatable, Sendable {
        case checking
        case notDetermined
        case granted
        case denied
        case disabled
    }

    /// Playground fixtures, so every calendar state can be seen without touching the real calendar.
    public enum DemoEvent: CaseIterable, Sendable {
        case startingSoon
        case inProgress
        case timeToLeave
    }

    public static let shared = CalendarController()
    /// Days in the agenda's week strip, starting today.
    public static let daysShown = 7

    public private(set) var access: Access = .checking
    /// Today and the following days, sorted by start; includes Playground demo events.
    public private(set) var events: [CalendarEvent] = []
    public private(set) var calendars: [CalendarInfo] = []
    public private(set) var travel: [String: TravelEstimate] = [:]
    public private(set) var featured: FeaturedEvent?

    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private let reader = EventStoreReader()
    @ObservationIgnored private let travelEstimator = TravelEstimator()
    @ObservationIgnored private var storeEvents: [CalendarEvent] = []
    @ObservationIgnored private var demoEvents: [CalendarEvent] = []
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var liveKind: ActivityKind?
    @ObservationIgnored private var livePriority = 0
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var postedNotices: Set<String> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var travelTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Moments missed by more than this (asleep, lid closed) are dropped rather than announced late.
    private static let staleNotice: TimeInterval = 120

    public init(activities: ActivityCenter = .shared) {
        self.activities = activities
    }

    // MARK: Lifecycle

    public func start() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.EKEventStoreChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange,
                                          NSLocale.currentLocaleDidChangeNotification, .NSCalendarDayChanged]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })

        Task { [weak self] in
            for await enabled in Defaults.updates(.enableCalendar) {
                await self?.setEnabled(enabled)
            }
        }
        Task { [weak self] in
            for await _ in Defaults.updates([.excludedCalendars], initial: false) {
                self?.scheduleRefresh()
            }
        }
        Task { [weak self] in
            let rules: [Defaults._AnyKey] = [
                .upcomingEventLead, .disableActivityDuringEvents, .enableCalendarQuickPeek, .beforeEventStarts,
                .timeBeforeEvent, .whenEventIsStarting, .notifyWhenTimeToLeave, .defaultTransportType,
                .timeToLeaveBuffer, .playHourlyChime,
            ]
            for await _ in Defaults.updates(rules, initial: false) {
                self?.evaluate()
            }
        }
    }

    private func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        guard enabled else {
            access = .disabled
            storeEvents = []
            publish()
            return
        }
        if EventStoreReader.canRequestAccess {
            access = .notDetermined
            await requestStoreAccess()
        } else {
            await refresh()
        }
    }

    // MARK: Access

    /// Shows the system prompt the first time; afterwards only System Settings can change the answer.
    public func requestAccess() {
        if EventStoreReader.canRequestAccess {
            Task { await requestStoreAccess() }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestStoreAccess() async {
        let granted = await reader.requestAccess()
        Log.calendar.info("Calendar access \(granted ? "granted" : "denied", privacy: .public)")
        await refresh()
    }

    public var locationAuthorization: String {
        switch travelEstimator.authorization {
        case .notDetermined: "Asked when an event with a location is coming up"
        case .granted: "Allowed"
        case .denied: "Not allowed — enable Notch in System Settings › Privacy & Security › Location Services"
        }
    }

    // MARK: Fetching

    /// Coalesces bursts (a sync touching many events posts many store-changed notifications).
    public func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard isEnabled else { return }
        guard EventStoreReader.hasAccess else {
            access = EventStoreReader.canRequestAccess ? .notDetermined : .denied
            storeEvents = []
            publish()
            return
        }
        access = .granted

        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: Self.daysShown, to: start) ?? start
        let excluded = Defaults[.excludedCalendars]
        let calendars = await reader.calendars()
        let fetched = await reader.events(from: start, to: end, excluding: excluded)
        if calendars != self.calendars {
            self.calendars = calendars
        }
        storeEvents = fetched
        publish()
    }

    private func publish() {
        let merged = (storeEvents + demoEvents).sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }
        if merged != events {
            withAnimation(.smooth(duration: 0.35)) { events = merged }
            postedNotices = postedNotices.filter { key in merged.contains { key.hasPrefix($0.id + "|") } }
        }
        evaluate()
    }

    // MARK: Evaluation

    private func evaluate() {
        let now = Date()
        let rules = ScheduleRules.current
        let candidates = isEnabled ? events : []
        let travelTimes = travel.mapValues(\.travelTime)

        let newFeatured = EventSchedule.featured(in: candidates, at: now, rules: rules)
        if newFeatured != featured {
            featured = newFeatured
        }
        syncActivity()

        let previousCheck = lastCheck ?? now
        let from = max(previousCheck, now.addingTimeInterval(-Self.staleNotice))
        lastCheck = now
        for notice in EventSchedule.notices(for: candidates, travelTimes: travelTimes, rules: rules, after: from, through: now) {
            post(notice)
        }
        chimeIfOnTheHour(since: previousCheck, now: now)

        updateTravel(for: candidates, now: now)
        scheduleBoundary(for: candidates, rules: rules, travelTimes: travelTimes, now: now)
    }

    private func syncActivity() {
        let kind = featured.map { ActivityKind.calendarEvent(id: $0.event.id) }
        let priority = featured?.isUrgent == true ? 2 : 0
        if let liveKind, liveKind != kind {
            activities.end(liveKind)
        }
        // Upsert only on change: each upsert counts as fresh activity and would steal the wings from music.
        if let kind, kind != liveKind || priority != livePriority {
            activities.upsert(kind, priority: priority)
        }
        liveKind = kind
        livePriority = priority
    }

    private func post(_ notice: DueNotice) {
        let key = "\(notice.event.id)|\(notice.moment.key)"
        // Locked: events are private (their wings are hidden too), so their peeks are skipped.
        guard !postedNotices.contains(key), !LockMonitor.shared.isLocked,
              !activities.isDismissed(.calendarEvent(id: notice.event.id)) else { return }
        postedNotices.insert(key)

        let isLeave = if case .timeToLeave = notice.moment { true } else { false }
        activities.post(.calendarEvent(id: notice.event.id, title: notice.event.title, start: notice.event.start,
                                       moment: notice.moment),
                        duration: isLeave ? Defaults[.timeToLeaveDuration] : Defaults[.calendarPeekDuration],
                        hasActions: !isLeave && notice.event.meetingLink != nil)
        if Defaults[.playSoundOnCalendarEvent] {
            NSSound(named: isLeave ? "Purr" : "Glass")?.play()
        }
    }

    private func chimeIfOnTheHour(since previous: Date, now: Date) {
        guard Defaults[.playHourlyChime],
              let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start,
              hour > previous, now.timeIntervalSince(hour) < 60 else { return }
        NSSound(named: "Tink")?.play()
    }

    private func scheduleBoundary(for events: [CalendarEvent], rules: ScheduleRules,
                                  travelTimes: [String: TimeInterval], now: Date) {
        var candidates = [EventSchedule.nextBoundary(for: events, travelTimes: travelTimes, rules: rules, after: now)]
        if Defaults[.playHourlyChime] {
            candidates.append(Calendar.current.dateInterval(of: .hour, for: now)?.end)
        }
        if Defaults[.notifyWhenTimeToLeave] {
            candidates.append(nextTravelCheck(for: events, now: now))
        }
        boundaryTask?.cancel()
        guard let next = candidates.compactMap(\.self).filter({ $0 > now }).min() else { return }
        boundaryTask = Task { [weak self] in
            // Slightly late rather than early, so the boundary is definitely in the past when we look.
            try? await Task.sleep(for: .seconds(next.timeIntervalSince(now) + 0.05))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    // MARK: Time to leave

    private func updateTravel(for events: [CalendarEvent], now: Date) {
        guard Defaults[.notifyWhenTimeToLeave] else {
            if !travel.isEmpty { travel = [:] }
            return
        }
        guard travelTask == nil else { return }
        let mode = Defaults[.defaultTransportType]
        travelTask = Task { [weak self] in
            guard let self else { return }
            let updated = await travelEstimator.estimates(for: events, existing: travel, mode: mode, now: now)
            travelTask = nil
            guard updated != travel else { return }
            travel = updated
            postOverdueLeaveNotices()
            evaluate()
        }
    }

    /// An estimate can arrive after its leave time has passed (event added late, longer traffic). You still
    /// want to know, as long as the event hasn't started.
    private func postOverdueLeaveNotices() {
        let now = Date()
        let notices = EventSchedule.notices(for: events, travelTimes: travel.mapValues(\.travelTime),
                                            rules: .current, after: .distantPast, through: now)
        for notice in notices where notice.event.start > now {
            if case .timeToLeave = notice.moment { post(notice) }
        }
    }

    /// When an event with a place enters the estimate window, and periodic refreshes while one is in it.
    private func nextTravelCheck(for events: [CalendarEvent], now: Date) -> Date? {
        let placed = events.filter {
            !$0.isAllDay && !$0.isDeclined && $0.start > now && $0.hasTravelDestination
        }
        if placed.contains(where: { $0.start.timeIntervalSince(now) <= TravelEstimator.horizon }) {
            return now.addingTimeInterval(TravelEstimator.refreshInterval)
        }
        return placed.map { $0.start.addingTimeInterval(-TravelEstimator.horizon) }.min()
    }

    // MARK: Actions

    public func event(id: String) -> CalendarEvent? {
        events.first { $0.id == id }
    }

    /// Opens the meeting in its app when installed (no browser detour), else in the browser.
    public func join(_ event: CalendarEvent) {
        guard let link = event.meetingLink else { return }
        let hasApp = link.service.appBundleIdentifiers.contains {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        NSWorkspace.shared.open(hasApp ? link.nativeURL ?? link.url : link.url)
    }

    /// "Open in …": the event itself in Calendar, its day in Fantastical, the app otherwise.
    public func open(_ event: CalendarEvent?, day: Date = .now) {
        let app = Defaults[.calendarApp]
        let url: URL? = switch app {
        case .calendar:
            event.flatMap { event in
                event.eventIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                    .flatMap { URL(string: "ical://ekevent/\($0)?method=show&options=more") }
            }
        case .fantastical:
            URL(string: "x-fantastical3://show?date=\((event?.start ?? day).formatted(.iso8601.year().month().day()))")
        case .notionCalendar:
            nil
        }
        if let url, !demoEvents.contains(where: { $0.id == event?.id }) {
            NSWorkspace.shared.open(url)
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Playground

    public func addDemoEvent(_ demo: DemoEvent) {
        let minute = Calendar.current.dateInterval(of: .minute, for: .now)?.end ?? .now
        switch demo {
        case .startingSoon:
            // Far enough out that the "before event starts" peek is still to come.
            let start = minute.addingTimeInterval((Defaults[.timeBeforeEvent] + 1) * 60)
            addDemo(title: "Design Review", start: start, duration: 30 * 60,
                    link: MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1234567890")!),
                    color: EventColor(red: 1, green: 0.62, blue: 0.04))
        case .inProgress:
            addDemo(title: "Weekly Sync", start: minute.addingTimeInterval(-11 * 60), duration: 30 * 60,
                    link: MeetingLink(service: .meet, url: URL(string: "https://meet.google.com/abc-defg-hij")!),
                    color: EventColor(red: 0.2, green: 0.78, blue: 0.35))
        case .timeToLeave:
            Task { await addTravelDemo(after: minute) }
        }
    }

    public func clearDemoEvents() {
        demoEvents.removeAll()
        publish()
    }

    /// An event ~3 km north of here, timed so "time to leave" fires about a minute from now.
    private func addTravelDemo(after minute: Date) async {
        guard let here = await travelEstimator.currentLocation() else {
            Log.calendar.error("Travel demo needs location access")
            return
        }
        let destination = Coordinate(latitude: here.coordinate.latitude + 0.027, longitude: here.coordinate.longitude)
        let id = "demo-\(UUID().uuidString)"
        let probe = CalendarEvent(id: id, title: "Coffee with Sam", start: .now.addingTimeInterval(3600),
                                  end: .now.addingTimeInterval(5400), coordinate: destination)
        let mode = Defaults[.defaultTransportType]
        let estimate = await travelEstimator.estimates(for: [probe], existing: [:], mode: mode, now: .now)[id]
        guard let travelTime = estimate?.travelTime else { return }
        let start = minute.addingTimeInterval(60 + travelTime + Defaults[.timeToLeaveBuffer] * 60)
        travel[id] = TravelEstimate(travelTime: travelTime, mode: mode, computedAt: .now)
        addDemo(id: id, title: "Coffee with Sam", start: start, duration: 45 * 60, location: "Blue Bottle Coffee",
                coordinate: destination, color: EventColor(red: 0.69, green: 0.32, blue: 0.87))
    }

    private func addDemo(id: String = "demo-\(UUID().uuidString)", title: String, start: Date, duration: TimeInterval,
                         link: MeetingLink? = nil, location: String? = nil, coordinate: Coordinate? = nil,
                         color: EventColor) {
        demoEvents.append(CalendarEvent(id: id, title: title, start: start, end: start.addingTimeInterval(duration),
                                        color: color, location: location ?? link?.service.name,
                                        coordinate: coordinate, meetingLink: link))
        publish()
    }
}

extension EventMoment {
    /// Identity for de-duplication; the travel time inside `.timeToLeave` may change between estimates.
    var key: String {
        switch self {
        case .startingSoon: "soon"
        case .starting: "start"
        case .timeToLeave: "leave"
        }
    }
}

public extension Array where Element == CalendarEvent {
    /// Events overlapping `day`, declined ones left out.
    func occurring(on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return filter { !$0.isDeclined && $0.start < interval.end && $0.end > interval.start }
    }
}
