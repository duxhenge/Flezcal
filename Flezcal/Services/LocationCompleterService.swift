import Foundation
@preconcurrency import MapKit
import Combine

/// Provides real-time typeahead city/region suggestions using `MKLocalSearchCompleter`.
///
/// Replaces the old `CLGeocoder`-based approach which required typing a near-complete
/// city name before results appeared. `MKLocalSearchCompleter` returns suggestions
/// after just a few characters (e.g. "Mam" → "Mammoth Lakes, CA").
///
/// Used by the location bar in `ListTabView`. Not an `@EnvironmentObject` — instantiated
/// locally to avoid re-render cascades (same pattern as LocationSearchService).
@MainActor
final class LocationCompleterService: NSObject, ObservableObject {

    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Only suggest cities/regions (not specific addresses or POIs)
        completer.resultTypes = .address
    }

    /// Update the search query. Called on every keystroke from the location text field.
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
            let name = buildDisplayName(from: item.placemark)
            return CustomSearchLocation(
                name: name.isEmpty ? completion.title : name,
                coordinate: coord
            )
        } catch {
            return nil
        }
    }

    /// Build a human-readable "City, State, Country" string from a placemark.
    private func buildDisplayName(from placemark: MKPlacemark) -> String {
        var components: [String] = []
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let admin = placemark.administrativeArea, admin != placemark.locality {
            components.append(admin)
        }
        if let country = placemark.country, country != placemark.administrativeArea {
            components.append(country)
        }
        return components.joined(separator: ", ")
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationCompleterService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            // Filter to region/city-level results — skip street addresses and POIs.
            // City results typically have a subtitle like "CA, United States" with no
            // street number, while address results have subtitles like "123 Main St".
            self.suggestions = completer.results.filter { result in
                // Keep results where the subtitle looks like a region (not a street address).
                // Street addresses typically contain digits at the start.
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
