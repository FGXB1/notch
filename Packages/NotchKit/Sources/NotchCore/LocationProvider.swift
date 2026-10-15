import CoreLocation
import Observation

/// The Mac's location, for travel times and weather. One manager for the whole app, so permission is asked
/// once and concurrent callers share a single fix. Location is requested lazily, never at launch.
@MainActor
@Observable
public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    public enum Authorization: Equatable, Sendable {
        case notDetermined
        case granted
        case denied
    }

    public static let shared = LocationProvider()

    public private(set) var authorization: Authorization = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    @ObservationIgnored private var lastLocation: CLLocation?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = Self.authorization(manager.authorizationStatus)
    }

    /// A fix no older than `maxAge`. Asks for permission the first time; nil when denied or unavailable.
    public func currentLocation(maxAge: TimeInterval) async -> CLLocation? {
        if let lastLocation, -lastLocation.timestamp.timeIntervalSinceNow < maxAge {
            return lastLocation
        }
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { authorizationWaiters.append($0) }
        }
        guard authorization == .granted else { return nil }
        return await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            if locationWaiters.count == 1 {
                manager.requestLocation()
            }
        }
    }

    /// Shows the Location Services prompt if it hasn't been answered.
    public func requestAuthorization() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    private static func authorization(_ status: CLAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways: .granted
        default: .denied
        }
    }

    // MARK: CLLocationManagerDelegate (delivered on the main run loop, where the manager was created)

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = Self.authorization(status)
            guard authorization != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated {
            if let location { lastLocation = location }
            finishLocationRequest(with: location)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.shell.error("Location failed: \(error.localizedDescription, privacy: .public)")
        MainActor.assumeIsolated { finishLocationRequest(with: nil) }
    }

    private func finishLocationRequest(with location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: location) }
    }
}
