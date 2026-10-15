import CoreLocation
import MapKit
import NotchCore

public struct TravelEstimate: Equatable, Sendable {
    public var travelTime: TimeInterval
    public var mode: TravelMode
    public var computedAt: Date
}

/// Travel times from here to upcoming events that have a place, for "Remind me when it's time to leave".
/// Location is requested only once such an event is coming up, never at launch.
@MainActor
final class TravelEstimator {
    /// Only events starting within this window get an estimate.
    static let horizon: TimeInterval = 3 * 3600
    /// Traffic changes; estimates older than this are refreshed.
    static let refreshInterval: TimeInterval = 10 * 60

    private let location = LocationProvider.shared
    private var geocoded: [String: Coordinate?] = [:]

    var authorization: LocationProvider.Authorization { location.authorization }

    /// The estimates that should exist for `events`, reusing fresh ones from `existing`.
    func estimates(for events: [CalendarEvent], existing: [String: TravelEstimate], mode: TravelMode,
                   now: Date) async -> [String: TravelEstimate] {
        let targets = events.filter { event in
            !event.isAllDay && !event.isDeclined && event.start > now
                && event.start.timeIntervalSince(now) <= Self.horizon
                && event.hasTravelDestination
        }
        var result = existing.filter { id, _ in targets.contains { $0.id == id } }
        let stale = targets.filter { event in
            guard let estimate = result[event.id] else { return true }
            return estimate.mode != mode || now.timeIntervalSince(estimate.computedAt) > Self.refreshInterval
        }
        guard !stale.isEmpty, let here = await currentLocation() else { return result }

        for event in stale {
            guard let destination = await coordinate(for: event),
                  let travelTime = await travelTime(from: here, to: destination, mode: mode) else { continue }
            result[event.id] = TravelEstimate(travelTime: travelTime, mode: mode, computedAt: now)
            Log.calendar.info("Travel to \(event.title, privacy: .private): \(Int(travelTime / 60)) min by \(mode.rawValue)")
        }
        return result
    }

    /// Asks for permission the first time; nil when denied or unavailable.
    func currentLocation() async -> CLLocation? {
        await location.currentLocation(maxAge: Self.refreshInterval)
    }

    // MARK: Lookups

    private func coordinate(for event: CalendarEvent) async -> Coordinate? {
        if let coordinate = event.coordinate { return coordinate }
        guard let address = event.geocodableAddress else { return nil }
        if let cached = geocoded[address] { return cached }

        var result: Coordinate?
        if let request = MKGeocodingRequest(addressString: address),
           let location = try? await request.mapItems.first?.location {
            result = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
        geocoded[address] = result
        return result
    }

    private func travelTime(from here: CLLocation, to destination: Coordinate, mode: TravelMode) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: here, address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude,
                                                             longitude: destination.longitude), address: nil)
        request.transportType = mode.transportType
        do {
            return try await MKDirections(request: request).calculateETA().expectedTravelTime
        } catch {
            Log.calendar.error("ETA failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
