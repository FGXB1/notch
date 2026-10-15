import Defaults
import SwiftUI
import WeatherLite

/// Weather symbols in the system's own palette (yellow sun, white cloud, blue rain), as in Weather.app.
struct WeatherSymbol: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size, weight: .medium))
            .contentTransition(.symbolEffect(.replace))
    }
}

/// "☁︎ 21°" beside the clock in the expanded notch.
struct HeaderWeather: View {
    let forecast: Forecast
    @Default(.temperatureUnit) private var unit

    var body: some View {
        HStack(spacing: 4) {
            WeatherSymbol(name: forecast.current.symbol, size: 12)
            Text(TemperatureFormat.degrees(forecast.current.temperature, unit: unit))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .help([forecast.current.condition.title, forecast.place].compactMap(\.self).joined(separator: " · "))
    }
}

/// Takes the place of "Nothing on today" in the agenda: the day's forecast, so an empty day still says
/// something useful. Today shows the current temperature; later days their high and low.
struct WeatherDayCard: View {
    let caption: String
    let day: Forecast.Day
    /// Set for today.
    let current: Forecast.Current?

    @Default(.temperatureUnit) private var unit

    static let height: CGFloat = 56

    var body: some View {
        let condition = current?.condition ?? day.condition
        HStack(spacing: 10) {
            WeatherSymbol(name: current?.symbol ?? day.condition.symbol(isDay: true), size: 24)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Group {
                    if let current {
                        Text("\(condition.title), \(TemperatureFormat.degrees(current.temperature, unit: unit))")
                    } else {
                        Text(condition.title)
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 6) {
                    Text("H:\(TemperatureFormat.degrees(day.high, unit: unit)) L:\(TemperatureFormat.degrees(day.low, unit: unit))")
                    if let chance = day.precipitationChance, chance >= 30 {
                        Label("\(chance)%", systemImage: "drop.fill")
                            .labelStyle(TightLabelStyle())
                            .foregroundStyle(.cyan.opacity(0.9))
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background(WeatherBackdrop(mood: condition.mood, isNight: current.map { !$0.isDay } ?? false),
                    in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// A faint wash of the sky's colour behind weather cards.
struct WeatherBackdrop: ShapeStyle {
    let mood: WeatherCondition.Mood
    let isNight: Bool

    func resolve(in environment: EnvironmentValues) -> LinearGradient {
        let colors: [Color] = if isNight, mood == .clear || mood == .cloudy {
            [Color(red: 0.16, green: 0.18, blue: 0.42).opacity(0.55), .indigo.opacity(0.12)]
        } else {
            switch mood {
            case .clear: [.orange.opacity(0.32), .yellow.opacity(0.08)]
            case .cloudy: [Color(white: 0.55).opacity(0.28), Color(white: 0.4).opacity(0.1)]
            case .rain: [.blue.opacity(0.36), .teal.opacity(0.1)]
            case .snow: [.cyan.opacity(0.26), .white.opacity(0.08)]
            case .storm: [.indigo.opacity(0.45), .purple.opacity(0.14)]
            }
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title
        }
    }
}
