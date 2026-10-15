import Defaults
import Foundation

public enum TemperatureUnit: String, CaseIterable, Sendable, Defaults.Serializable {
    /// Whatever System Settings › Language & Region › Temperature says.
    case system
    case celsius
    case fahrenheit

    /// `system` resolved against the Mac's preference (or the locale, if it has none).
    public func resolved(defaults: UserDefaults = .standard, locale: Locale = .current) -> TemperatureUnit {
        guard self == .system else { return self }
        switch defaults.string(forKey: "AppleTemperatureUnit") {
        case "Fahrenheit": return .fahrenheit
        case "Celsius": return .celsius
        default: return locale.measurementSystem == .us ? .fahrenheit : .celsius
        }
    }
}

public enum WeatherLocationMode: String, CaseIterable, Sendable, Defaults.Serializable {
    /// Location Services.
    case automatic
    /// A city typed in Settings.
    case custom
}

public enum TemperatureFormat {
    /// "21°" or "70°": rounded, unit implied (as in the menu bar and on iPhone).
    public static func degrees(_ celsius: Double, unit: TemperatureUnit) -> String {
        let value = unit.resolved() == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        // `rounded()` keeps -0.4 from printing as "-0°".
        let rounded = Int(value.rounded())
        return "\(rounded == 0 ? 0 : rounded)°"
    }
}

public extension Defaults.Keys {
    static let enableWeather = Key<Bool>("enableWeather", default: true)
    static let weatherLocationMode = Key<WeatherLocationMode>("weatherLocationMode", default: .automatic)
    static let weatherCity = Key<String>("weatherCity", default: "")
    static let temperatureUnit = Key<TemperatureUnit>("temperatureUnit", default: .system)
    /// Symbol and temperature beside the clock in the expanded notch.
    static let showWeatherInHeader = Key<Bool>("showWeatherInHeader", default: true)
    /// A forecast card in place of "Nothing on today" in the agenda.
    static let showWeatherOnClearDays = Key<Bool>("showWeatherOnClearDays", default: true)
    static let allowWeatherWidgetWhenLocked = Key<Bool>("allowWeatherWidgetWhenLocked", default: true)

    /// Last good forecast, so weather shows instantly at launch and survives being offline.
    static let cachedForecast = Key<Forecast?>("cachedForecast", default: nil)
}
