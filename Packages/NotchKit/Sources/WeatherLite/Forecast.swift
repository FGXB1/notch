import Defaults
import Foundation

/// Current conditions plus a daily outlook for one place. Temperatures are always Celsius; views convert.
public struct Forecast: Codable, Equatable, Sendable, Defaults.Serializable {
    public struct Current: Codable, Equatable, Sendable {
        public var temperature: Double
        public var feelsLike: Double
        public var code: Int
        public var isDay: Bool

        public var condition: WeatherCondition { WeatherCondition(code: code) }
        public var symbol: String { condition.symbol(isDay: isDay) }
    }

    public struct Day: Codable, Equatable, Sendable {
        /// The place's local date, "yyyy-MM-dd".
        public var date: String
        public var code: Int
        public var high: Double
        public var low: Double
        /// Highest chance of precipitation that day, 0...100.
        public var precipitationChance: Int?
        public var sunrise: Date?
        public var sunset: Date?

        public var condition: WeatherCondition { WeatherCondition(code: code) }
    }

    public var current: Current
    public var days: [Day]
    public var latitude: Double
    public var longitude: Double
    /// "Lafayette", for display; nil until reverse geocoding answers.
    public var place: String?
    public var fetchedAt: Date

    /// Forecasts older than this aren't shown: a stale "now" is worse than none.
    public static let maxAge: TimeInterval = 6 * 3600

    public func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) < Self.maxAge
    }

    public func day(for date: Date, calendar: Calendar = .current) -> Day? {
        let key = Self.dayKey(for: date, calendar: calendar)
        return days.first { $0.date == key }
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
