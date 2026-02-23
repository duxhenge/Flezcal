import CoreLocation
import MapKit

// MARK: - Shared Distance & Address Helpers
//
// Single source of truth for distance formatting and address parsing.
// Import this file's symbols anywhere in the app — do NOT duplicate
// these functions in individual View files.

/// Returns a formatted distance string in miles from `userLocation` to a
/// coordinate, or `nil` if `userLocation` is unknown.
func formattedDistanceMiles(
    from userLocation: CLLocationCoordinate2D?,
    to coordinate: CLLocationCoordinate2D
) -> String? {
    guard let user = userLocation else { return nil }
    let userCL   = CLLocation(latitude: user.latitude,       longitude: user.longitude)
    let targetCL = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let miles = userCL.distance(from: targetCL) / 1609.344
    return miles < 0.1 ? "< 0.1 mi" : String(format: "%.1f mi", miles)
}

/// Returns a formatted distance string in miles from `userLocation` to an
/// `MKMapItem`, falling back to `"—"` when location is unavailable.
func formattedDistanceMiles(
    from userLocation: CLLocationCoordinate2D?,
    to mapItem: MKMapItem
) -> String {
    formattedDistanceMiles(from: userLocation,
                           to: mapItem.placemark.coordinate) ?? "—"
}

/// Extracts the city component from a comma-separated Apple Maps address string.
/// Apple Maps addresses follow the pattern: "Street, City, State, Country".
/// Returns the second-to-last component, or the full string if unparseable.
func cityName(from address: String) -> String {
    let parts = address.components(separatedBy: ", ")
    guard parts.count >= 2 else { return address }
    return parts[parts.count - 2]
}

/// Returns street + city from a comma-separated address for list row display.
/// e.g. "23A Bow St, Somerville, MA, US" → "23A Bow St, Somerville"
/// Falls back to the full address if fewer than 3 parts.
func shortAddress(from address: String) -> String {
    let parts = address.components(separatedBy: ", ")
    guard parts.count >= 3 else { return address }
    return parts.prefix(2).joined(separator: ", ")
}
