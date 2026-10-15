import AppKit
import Defaults
import NotchCore
import SwiftUI
import WeatherLite

struct WeatherPane: View {
    @Default(.enableWeather) private var enabled
    @Default(.weatherLocationMode) private var locationMode
    @Default(.weatherCity) private var city
    @Default(.temperatureUnit) private var unit
    @Default(.showWeatherInHeader) private var showInHeader
    @Default(.showWeatherOnClearDays) private var showOnClearDays
    @Default(.allowWeatherWidgetWhenLocked) private var showOnLockScreen
    private let weather = WeatherController.shared
    private let location = LocationProvider.shared

    var body: some View {
        Form {
            Section {
                Toggle("Weather", isOn: $enabled)
                LabeledContent("Now") {
                    HStack {
                        TimelineView(.everyMinute) { context in
                            Text(status(at: context.date))
                                .foregroundStyle(.secondary)
                        }
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            weather.scheduleRefresh(force: true)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!enabled)
                    }
                }
            }

            Section("Location") {
                Picker("Location", selection: $locationMode) {
                    Text("Current location").tag(WeatherLocationMode.automatic)
                    Text("A city").tag(WeatherLocationMode.custom)
                }
                .pickerStyle(.radioGroup)
                if locationMode == .custom {
                    TextField("City", text: $city, prompt: Text("Lisbon, Portugal"))
                } else {
                    LabeledContent("Location Services") {
                        HStack {
                            Text(locationDescription)
                            if location.authorization == .denied {
                                Button("Open System Settings…", action: openLocationSettings)
                            }
                        }
                    }
                }
            }
            .disabled(!enabled)

            Section("Show") {
                Toggle("Beside the clock in the expanded notch", isOn: $showInHeader)
                Toggle("On clear days in the calendar", isOn: $showOnClearDays)
                Toggle("On the lock screen", isOn: $showOnLockScreen)
            }
            .disabled(!enabled)

            Section {
                Picker("Temperature", selection: $unit) {
                    Text("System (\(TemperatureUnit.system.resolved() == .fahrenheit ? "°F" : "°C"))")
                        .tag(TemperatureUnit.system)
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
            } footer: {
                Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
                    .font(.footnote)
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .navigationTitle("Weather")
    }

    private func status(at now: Date) -> String {
        guard enabled else { return "Off" }
        switch weather.status {
        case .needsLocation:
            return locationMode == .custom ? "Enter a city" : "Needs Location Services, or choose a city"
        case .cityNotFound:
            return "Couldn't find “\(city)”"
        case .failed where weather.forecast == nil:
            return "Couldn't reach Open-Meteo; retrying"
        case .loading where weather.forecast == nil:
            return "Loading…"
        default:
            guard let forecast = weather.forecast else { return "Waiting…" }
            let temperature = TemperatureFormat.degrees(forecast.current.temperature, unit: unit)
            let place = forecast.place.map { " in \($0)" } ?? ""
            let age = forecast.fetchedAt.formatted(.relative(presentation: .named))
            return "\(temperature), \(forecast.current.condition.title)\(place) · updated \(age)"
        }
    }

    private var locationDescription: String {
        switch location.authorization {
        case .notDetermined: "Asked the first time weather loads"
        case .granted: "Allowed"
        case .denied: "Not allowed"
        }
    }

    private func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
