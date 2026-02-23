import Foundation
import MapKit

@MainActor
class LocationSearchService: ObservableObject {
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false

    private var activeSearch: MKLocalSearch?

    func search(query: String, userLocation: CLLocationCoordinate2D? = nil) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        activeSearch?.cancel()
        activeSearch = nil
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest

        // Restrict to food & drink venue categories only.
        // This filters at the MapKit layer — roads, parks, shops, etc. are
        // never returned, so a search for "Barra" finds the Somerville
        // restaurant rather than "Barra Road, ME".
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery,
            .nightlife, .foodMarket, .store,
        ])

        // Use a local region (~35-mile radius) so Apple Maps ranks nearby
        // venues first.  A 5-degree span (~350 miles) lets distant matches
        // score higher than intended for short or generic venue names.
        // Fall back to Greater-Boston center when GPS isn't available yet.
        let center = userLocation ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
        request.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        let search = MKLocalSearch(request: request)
        activeSearch = search

        do {
            let response = try await search.start()
            // If a newer search has taken over, discard these results silently.
            guard activeSearch === search else {
                // isSearching is managed by the newer search call.
                return
            }
            searchResults = response.mapItems
            activeSearch = nil
            isSearching = false
        } catch {
            // Always clear isSearching if WE are still the active search.
            // This prevents isSearching from getting stuck when a search is
            // cancelled externally (e.g. by clearResults() or Task cancellation).
            if activeSearch === search {
                activeSearch = nil
                isSearching = false
            } else {
                // A newer search took over — it will manage isSearching.
                return
            }

            // Leave previous results visible for ALL errors — including
            // placemarkNotFound — so the list doesn't flash "No results"
            // on every keystroke while the user is still typing.
            // Results are only cleared explicitly via clearResults().
        }
    }

    func clearResults() {
        activeSearch?.cancel()
        activeSearch = nil
        searchResults = []
        isSearching = false
    }
}
