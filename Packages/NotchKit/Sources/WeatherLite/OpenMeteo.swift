import Foundation

/// The Open-Meteo forecast API: free, keyless, global. https://open-meteo.com/en/docs
enum OpenMeteo {
    /// Today plus the rest of the calendar's week strip.
    static let forecastDays = 8

    static func url(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,"
                + "precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
        ]
        return components.url!
    }

    static func fetch(latitude: Double, longitude: Double, session: URLSession = .shared) async throws -> Forecast {
        var request = URLRequest(url: url(latitude: latitude, longitude: longitude))
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try decode(data, fetchedAt: .now)
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> Forecast {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let offset = response.utcOffsetSeconds
        let daily = response.daily

        var days: [Forecast.Day] = []
        for (index, date) in daily.time.enumerated() {
            guard let code = daily.weatherCode[safe: index] ?? nil,
                  let high = daily.temperatureMax[safe: index] ?? nil,
                  let low = daily.temperatureMin[safe: index] ?? nil else { continue }
            days.append(Forecast.Day(
                date: date, code: code, high: high, low: low,
                precipitationChance: daily.precipitationChance?[safe: index] ?? nil,
                sunrise: (daily.sunrise?[safe: index] ?? nil).flatMap { localTime($0, utcOffset: offset) },
                sunset: (daily.sunset?[safe: index] ?? nil).flatMap { localTime($0, utcOffset: offset) }))
        }

        let current = response.current
        return Forecast(
            current: Forecast.Current(temperature: current.temperature, feelsLike: current.apparentTemperature,
                                      code: current.weatherCode, isDay: current.isDay == 1),
            days: days, latitude: response.latitude, longitude: response.longitude, place: nil, fetchedAt: fetchedAt)
    }

    /// "2026-10-14T19:09" in the place's own time zone.
    static func localTime(_ string: String, utcOffset: Int) -> Date? {
        let numbers = string.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard numbers.count >= 5, let zone = TimeZone(secondsFromGMT: utcOffset) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2],
                                                  hour: numbers[3], minute: numbers[4]))
    }

    private struct Response: Decodable {
        var latitude: Double
        var longitude: Double
        var utcOffsetSeconds: Int
        var current: Current
        var daily: Daily

        enum CodingKeys: String, CodingKey {
            case latitude, longitude, current, daily
            case utcOffsetSeconds = "utc_offset_seconds"
        }

        struct Current: Decodable {
            var temperature: Double
            var apparentTemperature: Double
            var weatherCode: Int
            var isDay: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            var time: [String]
            var weatherCode: [Int?]
            var temperatureMax: [Double?]
            var temperatureMin: [Double?]
            var precipitationChance: [Int?]?
            var sunrise: [String?]?
            var sunset: [String?]?

            enum CodingKeys: String, CodingKey {
                case time, sunrise, sunset
                case weatherCode = "weather_code"
                case temperatureMax = "temperature_2m_max"
                case temperatureMin = "temperature_2m_min"
                case precipitationChance = "precipitation_probability_max"
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
