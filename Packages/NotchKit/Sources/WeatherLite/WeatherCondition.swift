/// A WMO weather interpretation code (what Open-Meteo reports) as a name and an SF Symbol.
public struct WeatherCondition: Equatable, Sendable {
    public let code: Int
    public let title: String
    private let daySymbol: String
    private let nightSymbol: String

    public init(code: Int) {
        self.code = code
        (title, daySymbol, nightSymbol) = switch code {
        case 0: ("Clear", "sun.max.fill", "moon.stars.fill")
        case 1: ("Mostly Clear", "sun.max.fill", "moon.stars.fill")
        case 2: ("Partly Cloudy", "cloud.sun.fill", "cloud.moon.fill")
        case 3: ("Cloudy", "cloud.fill", "cloud.fill")
        case 45, 48: ("Foggy", "cloud.fog.fill", "cloud.fog.fill")
        case 51, 53, 55: ("Drizzle", "cloud.drizzle.fill", "cloud.drizzle.fill")
        case 56, 57: ("Freezing Drizzle", "cloud.sleet.fill", "cloud.sleet.fill")
        case 61: ("Light Rain", "cloud.rain.fill", "cloud.rain.fill")
        case 63: ("Rain", "cloud.rain.fill", "cloud.rain.fill")
        case 65: ("Heavy Rain", "cloud.heavyrain.fill", "cloud.heavyrain.fill")
        case 66, 67: ("Freezing Rain", "cloud.sleet.fill", "cloud.sleet.fill")
        case 71: ("Light Snow", "cloud.snow.fill", "cloud.snow.fill")
        case 73, 77: ("Snow", "cloud.snow.fill", "cloud.snow.fill")
        case 75: ("Heavy Snow", "snowflake", "snowflake")
        case 80, 81: ("Showers", "cloud.sun.rain.fill", "cloud.moon.rain.fill")
        case 82: ("Heavy Showers", "cloud.heavyrain.fill", "cloud.heavyrain.fill")
        case 85, 86: ("Snow Showers", "cloud.snow.fill", "cloud.snow.fill")
        case 95: ("Thunderstorms", "cloud.bolt.rain.fill", "cloud.bolt.rain.fill")
        case 96, 99: ("Hail", "cloud.hail.fill", "cloud.hail.fill")
        default: ("Unknown", "cloud.fill", "cloud.fill")
        }
    }

    public func symbol(isDay: Bool) -> String {
        isDay ? daySymbol : nightSymbol
    }

    /// Rough family, for tinting cards.
    public var mood: Mood {
        switch code {
        case 0, 1: .clear
        case 2, 3, 45, 48: .cloudy
        case 71...77, 85, 86: .snow
        case 95...99: .storm
        default: .rain
        }
    }

    public enum Mood: Sendable {
        case clear, cloudy, rain, snow, storm
    }
}
