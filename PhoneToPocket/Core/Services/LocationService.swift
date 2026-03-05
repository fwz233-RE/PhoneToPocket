import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationResult, Error>?

    struct LocationResult: Sendable {
        let latitude: Double
        let longitude: Double
        let address: String
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func getCurrentLocation() async throws -> LocationResult {
        requestPermission()

        return try await withCheckedThrowingContinuation { c in
            self.continuation = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate

        Task { @MainActor in
            let result = LocationResult(
                latitude: coord.latitude,
                longitude: coord.longitude,
                address: String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
            )
            self.continuation?.resume(returning: result)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
