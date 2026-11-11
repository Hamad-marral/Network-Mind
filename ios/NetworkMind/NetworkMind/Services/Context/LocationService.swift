import Foundation
import CoreLocation

/// One-shot, when-in-use location for tagging where someone was met. Never prompts on its
/// own during a background sync; authorization is requested from an explanation screen.
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    private let geocoder = CLGeocoder()
    private var pending: [CheckedContinuation<CLLocation?, Never>] = []
    /// Incremented per location request so a stale timeout can't cancel a newer request.
    private var requestGeneration = 0

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Neighbourhood-level accuracy is enough to name a venue and is faster/cheaper.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var canRequestAuthorization: Bool { authorizationStatus == .notDetermined }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// A single location fix, or nil if unauthorized/unavailable within `timeout`.
    func currentLocation(timeout: TimeInterval = 10) async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -120 {
            return recent
        }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            guard pending.count == 1 else { return }  // a request is already in flight
            requestGeneration += 1
            let generation = requestGeneration
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, self.requestGeneration == generation else { return }
                self.finish(with: nil)
            }
        }
    }

    /// Human-readable place: point of interest if known, else "Street, City".
    func placeName(for location: CLLocation) async -> String? {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return Self.describe(placemark)
    }

    static func describe(_ placemark: CLPlacemark) -> String? {
        if let poi = placemark.areasOfInterest?.first {
            return [poi, placemark.locality].compactMap { $0 }.joined(separator: ", ")
        }
        let parts = [placemark.name, placemark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        let unique = parts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    private func finish(with location: CLLocation?) {
        requestGeneration += 1
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume(returning: location) }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(with: nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }
}
