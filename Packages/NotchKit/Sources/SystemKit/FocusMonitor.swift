import Activities
import AppKit
import Defaults
import NotchCore
import Observation

public struct FocusMode: Equatable, Sendable {
    public var id: String
    public var name: String
    public var symbol: String
    /// Color name: "indigo", "mint", ... (see `FocusLog.tint(fromLog:)`).
    public var tint: String

    public init(id: String, name: String, symbol: String, tint: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.tint = tint
    }
}

public enum FocusLogEvent: Equatable, Sendable {
    /// The active Focus changed; nil means none.
    case activeMode(String?)
    /// A mode's details, seen inside a state dump (how custom Focuses get their name and symbol).
    case modeInfo(FocusMode)
}

/// Parses `donotdisturbd`'s log lines. Undocumented and liable to change; every field is optional, and
/// unknown modes fall back to a generic Focus.
public enum FocusLog {
    public static let sleepModeID = "com.apple.sleep.sleep-mode"

    /// Apple's built-in modes, named as in System Settings.
    public static let builtIn: [String: FocusMode] = Dictionary(uniqueKeysWithValues: [
        FocusMode(id: "com.apple.donotdisturb.mode.default", name: "Do Not Disturb", symbol: "moon.fill", tint: "indigo"),
        FocusMode(id: sleepModeID, name: "Sleep", symbol: "bed.double.fill", tint: "mint"),
        FocusMode(id: "com.apple.donotdisturb.mode.driving", name: "Driving", symbol: "car.fill", tint: "blue"),
        FocusMode(id: "com.apple.focus.work", name: "Work", symbol: "lanyardcard.fill", tint: "teal"),
        FocusMode(id: "com.apple.focus.personal-time", name: "Personal", symbol: "person.fill", tint: "purple"),
        FocusMode(id: "com.apple.focus.fitness", name: "Fitness", symbol: "figure.run", tint: "green"),
        FocusMode(id: "com.apple.focus.gaming", name: "Gaming", symbol: "gamecontroller.fill", tint: "blue"),
        FocusMode(id: "com.apple.focus.mindfulness", name: "Mindfulness", symbol: "figure.mind.and.body", tint: "cyan"),
        FocusMode(id: "com.apple.focus.reading", name: "Reading", symbol: "book.fill", tint: "orange"),
        FocusMode(id: "com.apple.focus.reduce-interruptions", name: "Reduce Interruptions", symbol: "apple.intelligence",
                  tint: "indigo"),
    ].map { ($0.id, $0) })

    public static func parse(_ message: String) -> FocusLogEvent? {
        if message.contains("Delivering active mode update"),
           let match = message.firstMatch(of: #/activeModeIdentifier=([^,\s]+)/#) {
            let id = String(match.1)
            return .activeMode(id == "(null)" ? nil : id)
        }
        // "...mode: <DNDMode: 0x…; name: Work; modeIdentifier: com.apple.focus.work; symbolImageName: …"
        guard let modeStart = message.range(of: "mode: <DNDMode") else { return nil }
        let details = message[modeStart.upperBound...]
        guard let id = field("modeIdentifier", in: details) else { return nil }
        let known = builtIn[id]
        return .modeInfo(FocusMode(id: id,
                                   name: field("name", in: details) ?? known?.name ?? "Focus",
                                   symbol: field("symbolImageName", in: details) ?? known?.symbol ?? "moon.fill",
                                   tint: field("tintColorName", in: details).map(tint(fromLog:)) ?? known?.tint ?? "indigo"))
    }

    /// The best description of `id` so far.
    public static func mode(_ id: String, known: [String: FocusMode]) -> FocusMode {
        known[id] ?? builtIn[id] ?? FocusMode(id: id, name: "Focus", symbol: "moon.fill", tint: "indigo")
    }

    /// "systemPurpleColor" → "purple".
    static func tint(fromLog name: String) -> String {
        var name = name
        if name.hasPrefix("system") { name.removeFirst("system".count) }
        if name.hasSuffix("Color") { name.removeLast("Color".count) }
        return name.lowercased()
    }

    private static func field(_ name: String, in text: Substring) -> String? {
        guard let range = text.range(of: "; \(name): ") ?? text.range(of: " \(name): ") else { return nil }
        let value = text[range.upperBound...].prefix { $0 != ";" && $0 != ">" }
            .trimmingCharacters(in: .whitespaces)
        return value.isEmpty || value == "(null)" ? nil : value
    }
}

/// Focus changes, read from the Do Not Disturb daemon's log stream (there's no public API for the active
/// mode). The current mode is unknown until the first change after launch.
@MainActor
@Observable
public final class FocusMonitor {
    public static let shared = FocusMonitor()

    public private(set) var active: FocusMode?

    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var known: [String: FocusMode] = [:]
    @ObservationIgnored private var restartDelay: Duration = .seconds(2)
    @ObservationIgnored private var isRunning = false

    public init(activities: ActivityCenter = .shared) {
        self.activities = activities
    }

    public func start() {
        isRunning = true
        launch()
    }

    public func stop() {
        isRunning = false
        process?.terminate()
        process = nil
    }

    private func launch() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/log")
        process.arguments = [
            "stream", "--style", "ndjson", "--level", "info", "--predicate",
            #"subsystem == "com.apple.donotdisturb" AND (category == "ServiceProvider" OR category == "StateProvider") "#
                + #"AND (eventMessage CONTAINS "activeModeIdentifier=" OR eventMessage CONTAINS "DNDMode:")"#,
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let reader = LineReader { [weak self] line in
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = json["eventMessage"] as? String,
                  let event = FocusLog.parse(message) else { return }
            Task { @MainActor in self?.receive(event) }
        }
        let readHandle = output.fileHandleForReading
        readHandle.readabilityHandler = { handle in reader.consume(handle.availableData) }
        process.terminationHandler = { [weak self] _ in
            readHandle.readabilityHandler = nil
            Task { @MainActor in self?.streamDidExit() }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            Log.system.error("Focus log stream failed: \(error.localizedDescription, privacy: .public)")
            streamDidExit()
        }
    }

    private func streamDidExit() {
        process = nil
        guard isRunning else { return }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, .seconds(60))
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.isRunning, self.process == nil else { return }
            self.launch()
        }
    }

    private func receive(_ event: FocusLogEvent) {
        restartDelay = .seconds(2)
        switch event {
        case let .modeInfo(mode):
            known[mode.id] = mode
        case let .activeMode(id):
            // The daemon delivers each change to every client; only the first one is news.
            guard id != active?.id else { return }
            let previous = active
            let current = id.map { FocusLog.mode($0, known: known) }
            active = current
            Log.system.info("Focus: \(current?.name ?? "off", privacy: .public)")

            if Defaults[.notifyOnFocusChange], LockMonitor.allows(.allowFocusWhenLocked), let shown = current ?? previous {
                activities.post(.focus(name: shown.name, symbol: shown.symbol, tint: shown.tint, isOn: current != nil))
            }
            if current?.id == FocusLog.sleepModeID, Defaults[.playSoundOnSleepFocus] {
                NSSound(named: "Blow")?.play()
            }
        }
    }
}
