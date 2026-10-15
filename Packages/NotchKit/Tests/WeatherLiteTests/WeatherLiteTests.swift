import Foundation
import Testing
@testable import WeatherLite

struct OpenMeteoTests {
    /// A real response (Lafayette, IN), with one day's high nulled out as the API does past its horizon.
    static let sample = Data("""
    {"latitude":40.406116,"longitude":-86.89583,"generationtime_ms":2.45,"utc_offset_seconds":-14400,
     "timezone":"America/Indiana/Indianapolis","timezone_abbreviation":"GMT-4","elevation":185.0,
     "current":{"time":"2026-10-14T17:00","interval":900,"temperature_2m":20.8,"apparent_temperature":22.4,
                "weather_code":3,"is_day":1},
     "daily":{"time":["2026-10-14","2026-10-15","2026-10-16","2026-10-17"],
              "weather_code":[3,3,55,3],
              "temperature_2m_max":[24.4,24.6,21.8,null],
              "temperature_2m_min":[17.8,16.2,9.2,4.8],
              "precipitation_probability_max":[14,48,62,null],
              "sunrise":["2026-10-14T07:57","2026-10-15T07:58","2026-10-16T07:59","2026-10-17T08:00"],
              "sunset":["2026-10-14T19:09","2026-10-15T19:07","2026-10-16T19:06","2026-10-17T19:04"]}}
    """.utf8)

    @Test func decodesCurrentConditions() throws {
        let forecast = try OpenMeteo.decode(Self.sample, fetchedAt: .now)
        #expect(forecast.current.temperature == 20.8)
        #expect(forecast.current.feelsLike == 22.4)
        #expect(forecast.current.condition.title == "Cloudy")
        #expect(forecast.current.isDay)
        #expect(forecast.latitude == 40.406116)
    }

    @Test func decodesDaysAndSkipsIncompleteOnes() throws {
        let forecast = try OpenMeteo.decode(Self.sample, fetchedAt: .now)
        #expect(forecast.days.map(\.date) == ["2026-10-14", "2026-10-15", "2026-10-16"])
        let drizzle = try #require(forecast.days.last)
        #expect(drizzle.condition.title == "Drizzle")
        #expect(drizzle.high == 21.8)
        #expect(drizzle.precipitationChance == 62)
    }

    @Test func sunTimesUseThePlacesOffset() throws {
        let forecast = try OpenMeteo.decode(Self.sample, fetchedAt: .now)
        let sunset = try #require(forecast.days.first?.sunset)
        // 19:09 at UTC-4 is 23:09 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.hour, .minute], from: sunset)
        #expect(parts.hour == 23 && parts.minute == 9)
    }

    @Test func requestAsksForEnoughDaysForTheWeekStrip() throws {
        let url = OpenMeteo.url(latitude: 40.4167, longitude: -86.8753)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        // Rounded to about a kilometre: plenty for weather, and no more of the user's location than needed.
        #expect(items.first { $0.name == "latitude" }?.value == "40.42")
        #expect(items.first { $0.name == "longitude" }?.value == "-86.88")
        #expect(items.first { $0.name == "forecast_days" }?.value == "8")
        #expect(items.first { $0.name == "timezone" }?.value == "auto")
    }

    @Test func findsTheForecastForACalendarDay() throws {
        let forecast = try OpenMeteo.decode(Self.sample, fetchedAt: .now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9)))
        #expect(forecast.day(for: day, calendar: calendar)?.precipitationChance == 48)
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30)))
        #expect(forecast.day(for: later, calendar: calendar) == nil)
    }

    @Test func staleForecastsAreNotFresh() throws {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        let forecast = try OpenMeteo.decode(Self.sample, fetchedAt: fetched)
        #expect(forecast.isFresh(at: fetched.addingTimeInterval(3600)))
        #expect(!forecast.isFresh(at: fetched.addingTimeInterval(7 * 3600)))
    }
}

struct WeatherConditionTests {
    @Test func clearSkiesHaveNightSymbols() {
        let clear = WeatherCondition(code: 0)
        #expect(clear.symbol(isDay: true) == "sun.max.fill")
        #expect(clear.symbol(isDay: false) == "moon.stars.fill")
        #expect(clear.mood == .clear)
    }

    @Test func groupsCodesIntoMoods() {
        #expect(WeatherCondition(code: 63).mood == .rain)
        #expect(WeatherCondition(code: 75).mood == .snow)
        #expect(WeatherCondition(code: 95).mood == .storm)
        #expect(WeatherCondition(code: 45).mood == .cloudy)
        #expect(WeatherCondition(code: 1234).title == "Unknown")
    }
}

struct TemperatureTests {
    @Test func formatsRoundedDegrees() {
        #expect(TemperatureFormat.degrees(20.8, unit: .celsius) == "21°")
        #expect(TemperatureFormat.degrees(20.8, unit: .fahrenheit) == "69°")
        #expect(TemperatureFormat.degrees(-0.4, unit: .celsius) == "0°")
        #expect(TemperatureFormat.degrees(-40, unit: .fahrenheit) == "-40°")
    }

    @Test func systemUnitFollowsTheMacsPreference() throws {
        let defaults = try #require(UserDefaults(suiteName: "WeatherLiteTests.\(UUID().uuidString)"))
        defaults.set("Fahrenheit", forKey: "AppleTemperatureUnit")
        #expect(TemperatureUnit.system.resolved(defaults: defaults, locale: Locale(identifier: "en_GB")) == .fahrenheit)
        defaults.set("Celsius", forKey: "AppleTemperatureUnit")
        #expect(TemperatureUnit.system.resolved(defaults: defaults, locale: Locale(identifier: "en_US")) == .celsius)
        defaults.removeObject(forKey: "AppleTemperatureUnit")
        #expect(TemperatureUnit.celsius.resolved(defaults: defaults) == .celsius)
    }
}
