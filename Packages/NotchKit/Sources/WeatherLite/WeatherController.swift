import AppKit
import CoreLocation
import Defaults
import MapKit
import NotchCore
import Observation

/// Keeps a forecast for here (or the city chosen in Settings) fresh: every half hour, after waking, and
/// whenever the location settings change. The last good forecast is cached so weather shows at launch.
@MainActor
@Observable
public final class WeatherController {
    public enum Status: Equatable, Sendable {
        case idle
        case loading
        /// Location Services is off for Notch (or found nothing) and no city is set.
        case needsLocation
        case cityNotFound
        case failed
        case ready
    }

    public static let shared = WeatherController()

    public private(set) var forecast: Forecast? = Defaults[.cachedForecast]
    public private(set) var status: Status = .idle
    public private(set) var isEnabled = Defaults[.enableWeather]

    static let refreshInterval: TimeInterval = 30 * 60
    static let retryInterval: TimeInterval = 2 * 60
    /// Moving further than this counts as a new place.
    static let moveThreshold: CLLocationDistance = 3_000

    private struct Place {
        var location: CLLocation
        var name: String?
    }

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var geocodedCity: (query: String, place: Place)?

    public init() {}

    /// A forecast fit to show right now: weather on, and recent enough that "now" still means now.
    public var usable: Forecast? {
        guard isEnabled, let forecast, forecast.isFresh(at: .now) else { return nil }
        return forecast
    }

    public func start() {
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let delay = self?.status == .ready ? Self.refreshInterval : Self.retryInterval
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        settingsTask = Task { [weak self] in
            let keys: [Defaults._AnyKey] = [.enableWeather, .weatherLocationMode, .weatherCity, .hasCompletedOnboarding]
            for await _ in Defaults.updates(keys, initial: false) {
                self?.isEnabled = Defaults[.enableWeather]
                // Debounced: the city field reports every keystroke.
                self?.scheduleRefresh(after: .seconds(1), force: true)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The network takes a moment to come back after sleep.
            MainActor.assumeIsolated { self?.scheduleRefresh(after: .seconds(5), force: false) }
        }
    }

    public func scheduleRefresh(after delay: Duration = .zero, force: Bool) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh(force: force)
        }
    }

    public func refresh(force: Bool = false) async {
        guard isEnabled else {
            status = .idle
            return
        }
        guard let place = await resolvePlace() else { return }

        if !force, status == .ready, let forecast,
           Date.now.timeIntervalSince(forecast.fetchedAt) < Self.refreshInterval - 60,
           Self.distance(from: forecast, to: place.location) < Self.moveThreshold {
            return
        }

        if forecast == nil { status = .loading }
        let coordinate = place.location.coordinate
        do {
            var fresh = try await OpenMeteo.fetch(latitude: coordinate.latitude, longitude: coordinate.longitude)
            fresh.place = await name(for: place)
            forecast = fresh
            Defaults[.cachedForecast] = fresh
            status = .ready
            Log.weather.info("""
                Weather: \(fresh.current.condition.title, privacy: .public), \(fresh.current.temperature, format: .fixed(precision: 1))°C \
                in \(fresh.place ?? "?", privacy: .private), \(fresh.days.count) days
                """)
        } catch {
            status = .failed
            Log.weather.error("Weather fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Place

    private func resolvePlace() async -> Place? {
        switch Defaults[.weatherLocationMode] {
        case .automatic:
            // Before the welcome window, it asks there instead.
            if LocationProvider.shared.authorization == .notDetermined, !Defaults[.hasCompletedOnboarding] {
                status = .needsLocation
                return nil
            }
            guard let location = await LocationProvider.shared.currentLocation(maxAge: Self.refreshInterval) else {
                status = .needsLocation
                return nil
            }
            return Place(location: location, name: nil)
        case .custom:
            let query = Defaults[.weatherCity].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                status = .needsLocation
                return nil
            }
            if let geocodedCity, geocodedCity.query == query { return geocodedCity.place }
            guard let request = MKGeocodingRequest(addressString: query),
                  let item = try? await request.mapItems.first else {
                status = .cityNotFound
                return nil
            }
            let place = Place(location: item.location,
                              name: item.addressRepresentations?.cityName ?? item.name ?? query)
            geocodedCity = (query, place)
            return place
        }
    }

    /// The city's name, reusing the last one while still in the same place.
    private func name(for place: Place) async -> String? {
        if let name = place.name { return name }
        if let forecast, let known = forecast.place,
           Self.distance(from: forecast, to: place.location) < Self.moveThreshold {
            return known
        }
        guard let request = MKReverseGeocodingRequest(location: place.location),
              let item = try? await request.mapItems.first else { return nil }
        return item.addressRepresentations?.cityName ?? item.name
    }

    private static func distance(from forecast: Forecast, to location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: forecast.latitude, longitude: forecast.longitude).distance(from: location)
    }
}
