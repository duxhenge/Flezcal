import Foundation
@preconcurrency import MapKit
import Combine

// MARK: - Unified suggestion type

/// A single dropdown suggestion from either the completer (fast) or a
/// supplemental `MKLocalSearch` business query (catches names the completer misses).
enum LocationSuggestion: Identifiable {
    case completer(MKLocalSearchCompletion)
    case business(MKMapItem)

    var id: String {
        switch self {
        case .completer(let c):
            return "c_\(c.title)_\(c.subtitle)"
        case .business(let item):
            return "b_\(item.name ?? "")_\(item.placemark.coordinate.latitude)"
        }
    }

    var title: String {
        switch self {
        case .completer(let c): return c.title
        case .business(let item): return item.name ?? "Unknown"
        }
    }

    var subtitle: String {
        switch self {
        case .completer(let c): return c.subtitle
        case .business(let item):
            var parts: [String] = []
            if let locality = item.placemark.locality { parts.append(locality) }
            if let admin = item.placemark.administrativeArea, admin != item.placemark.locality {
                parts.append(admin)
            }
            return parts.isEmpty ? "" : parts.joined(separator: ", ")
        }
    }

}

// MARK: - Location Completer Service

/// Provides real-time typeahead suggestions for cities, POIs, restaurants,
/// universities, and other places using `MKLocalSearchCompleter`.
///
/// Supplements the completer with a debounced `MKLocalSearch` natural-language
/// query to catch business names the completer misses (e.g. "Atla NYC").
///
/// Used by the unified search bar in `LocationSearchBarView`. Not an
/// `@EnvironmentObject` — instantiated locally to avoid re-render cascades.
@MainActor
final class LocationCompleterService: NSObject, ObservableObject {

    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var businessResults: [MKMapItem] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var businessSearchTask: Task<Void, Never>?
    /// Cached for distance-sorting business results in `mergedSuggestions`.
    private var lastUserLocation: CLLocationCoordinate2D?

    override init() {
        super.init()
        completer.delegate = self
        // Suggest both cities/regions AND points of interest (restaurants,
        // universities, theaters, etc.) so one search bar handles everything.
        completer.resultTypes = [.address, .pointOfInterest]
    }

    // MARK: - Merged suggestions

    /// Completer results first (instant), then business results (after debounce),
    /// deduplicated by lowercased name. Business results sorted by distance.
    /// Capped at 7 total.
    var mergedSuggestions: [LocationSuggestion] {
        var results: [LocationSuggestion] = []
        var seenNames: Set<String> = []

        for completion in suggestions {
            let key = completion.title.lowercased()
            if seenNames.insert(key).inserted {
                results.append(.completer(completion))
            }
        }

        // Sort business results by distance before merging
        let sorted: [MKMapItem]
        if let loc = lastUserLocation {
            let ref = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            sorted = businessResults.sorted {
                let d0 = ref.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                let d1 = ref.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
                return d0 < d1
            }
        } else {
            sorted = businessResults
        }

        for item in sorted {
            let key = (item.name ?? "").lowercased()
            guard !key.isEmpty, seenNames.insert(key).inserted else { continue }
            results.append(.business(item))
        }

        return Array(results.prefix(7))
    }

    // MARK: - Query

    /// Update the search query. Called on every keystroke from the search text field.
    /// Also fires a debounced business name search after 400ms.
    func updateQuery(_ query: String, userLocation: CLLocationCoordinate2D? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            completer.cancel()
            suggestions = []
            businessResults = []
            businessSearchTask?.cancel()
            isSearching = false
            return
        }
        isSearching = true
        lastUserLocation = userLocation

        // Bias completer toward the user's location so nearby results rank first.
        // This is a hint, not a hard filter — distant cities still appear.
        if let loc = userLocation {
            completer.region = MKCoordinateRegion(
                center: loc,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        completer.queryFragment = trimmed

        // Debounced business name search — 400ms after last keystroke
        businessSearchTask?.cancel()
        businessSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await searchBusinesses(query: trimmed, userLocation: userLocation)
        }
    }

    /// Cancel any in-flight completion and business search.
    func cancel() {
        completer.cancel()
        suggestions = []
        businessResults = []
        businessSearchTask?.cancel()
        isSearching = false
    }

    // MARK: - Resolution

    /// Geocode a completer suggestion into a `CustomSearchLocation`.
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

    /// Resolve a business `MKMapItem` — already has coordinates, no async needed.
    func resolveMapItem(_ mapItem: MKMapItem) -> CustomSearchLocation {
        let name = buildDisplayName(from: mapItem.placemark, fallback: mapItem.name ?? "Unknown")
        return CustomSearchLocation(
            name: name,
            coordinate: mapItem.placemark.coordinate
        )
    }

    // MARK: - Private

    /// Supplemental business name search via `MKLocalSearch`.
    /// Catches specific restaurant/business names the completer misses.
    private func searchBusinesses(query: String, userLocation: CLLocationCoordinate2D?) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        let center = userLocation ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
        request.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            businessResults = Array(response.mapItems.prefix(5))
        } catch {
            // Don't clear on error — keep previous results visible
            guard !Task.isCancelled else { return }
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
            // Pass through all results — cities, POIs, businesses, and
            // street addresses are all valid search centerpoints.
            self.suggestions = completer.results
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
