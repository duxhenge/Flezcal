import Foundation
import CoreLocation
import MapKit

/// Wraps CLLocationManager and publishes the user's location to SwiftUI views.
///
/// @MainActor ensures all @Published mutations happen on the main thread,
/// satisfying Swift 6 strict concurrency requirements.
/// CLLocationManagerDelegate callbacks are `nonisolated` because CoreLocation
/// delivers them on an arbitrary thread; each hops to MainActor via Task.
@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default: San Francisco
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Stop updates before hopping to main actor to avoid a race where a
        // second callback could arrive before the first Task executes.
        manager.stopUpdatingLocation()
        Task { @MainActor in
            self.userLocation = location.coordinate
            self.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Silently handle — map will use default region
    }
}
