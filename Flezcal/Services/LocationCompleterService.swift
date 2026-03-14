import Foundation
@preconcurrency import MapKit
import Combine

/// Provides real-time typeahead suggestions for cities, POIs, restaurants,
/// universities, and other places using `MKLocalSearchCompleter`.
///
/// Returns both address-level results (cities/regions) and points of interest
/// (theaters, universities, restaurants) so the user can search for Flezcals
/// near any kind of place.
///
/// Used by the unified search bar in `ListTabView`. Not an `@EnvironmentObject` —
/// instantiated locally to avoid re-render cascades (same pattern as LocationSearchService).
@MainActor
final class LocationCompleterService: NSObject, ObservableObject {

    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Suggest both cities/regions AND points of interest (restaurants,
        // universities, theaters, etc.) so one search bar handles everything.
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Update the search query. Called on every keystroke from the search text field.
    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            completer.cancel()
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = trimmed
    }

    /// Cancel any in-flight completion.
    func cancel() {
        completer.cancel()
        suggestions = []
        isSearching = false
    }

    /// Geocode a selected completion into a `CustomSearchLocation`.
    /// Uses `MKLocalSearch` with the completion to get the precise coordinate.
    func resolve(_ completion: MKLocalSearchCompletion) async -> CustomSearchLocation? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            let coord = item.placemark.coordinate
            let name = buildDisplayName(from: item.placemark, fallback: completion.title)
            return CustomSearchLocation(
                name: name,
                coordinate: coord
            )
        } catch {
            return nil
        }
    }

    /// Build a human-readable display name from a placemark.
    /// For POIs: "POI Name, City, State" (e.g. "The Public Theater, New York, NY").
    /// For cities: "City, State, Country" (e.g. "Boston, MA, United States").
    private func buildDisplayName(from placemark: MKPlacemark, fallback: String) -> String {
        var components: [String] = []
        // POI name (only if it's a named place, not just a city)
        if let name = placemark.name,
           name != placemark.locality,
           name != placemark.administrativeArea {
            components.append(name)
        }
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let admin = placemark.administrativeArea, admin != placemark.locality {
            components.append(admin)
        }
        if components.isEmpty, let country = placemark.country {
            components.append(country)
        }
        return components.isEmpty ? fallback : components.joined(separator: ", ")
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationCompleterService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            // Filter out street-level addresses (subtitles starting with a digit
            // like "123 Main St"). Keep cities, regions, and POIs.
            self.suggestions = completer.results.filter { result in
                let sub = result.subtitle
                let firstChar = sub.first
                let looksLikeStreetAddress = firstChar?.isNumber ?? false
                return !looksLikeStreetAddress
            }
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
            self.isSearching = false
        }
    }
}
