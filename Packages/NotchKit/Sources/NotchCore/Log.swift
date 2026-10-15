import OSLog

/// Unified logging. Stream with: `log stream --predicate 'subsystem == "dev.ishan.notch"'`
public enum Log {
    public static let subsystem = "dev.ishan.notch"

    public static let shell = Logger(subsystem: subsystem, category: "shell")
    public static let motion = Logger(subsystem: subsystem, category: "motion")
    public static let media = Logger(subsystem: subsystem, category: "media")
    public static let calendar = Logger(subsystem: subsystem, category: "calendar")
    public static let system = Logger(subsystem: subsystem, category: "system")
    public static let weather = Logger(subsystem: subsystem, category: "weather")
    public static let tray = Logger(subsystem: subsystem, category: "tray")

    /// Signposts appear in Instruments' "Points of Interest" track next to Animation Hitches.
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
