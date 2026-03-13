import Foundation
@preconcurrency import MapKit

/// Provides real-time typeahead venue/POI suggestions using `MKLocalSearchCompleter`.
///
/// Used by the search bar in `ListTabView` for Apple Maps-style venue search.
/// When the user types a venue name (e.g. "B&H Dairy"), this service returns
/// matching POI suggestions. The user selects one from the dropdown and it gets
/// pinned at the top of the spots list.
///
/// Modeled after `LocationCompleterService` (city search) but configured for
/// points of interest instead of addresses.
@MainActor
final class VenueCompleterService: NSObject, ObservableObject {

    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
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

    /// Resolve a selected completion into a `SuggestedSpot`.
    /// Uses `MKLocalSearch` with the completion to get the precise map item.
    func resolve(_ completion: MKLocalSearchCompletion, suggestedCategory: FoodCategory) async -> SuggestedSpot? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            return SuggestedSpot(mapItem: item, suggestedCategory: suggestedCategory)
        } catch {
            return nil
        }
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension VenueCompleterService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
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
