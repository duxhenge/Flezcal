import Foundation
@preconcurrency import MapKit
import CoreLocation

@MainActor
class LocationSearchService: ObservableObject {
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false

    private var activeSearch: MKLocalSearch?

    /// Monotonically increasing generation counter. Each call to `search` or
    /// `multiSearch` increments this; if a newer search starts while an older
    /// one is mid-flight, the older one discards its results.
    private var searchGeneration = 0

    /// Shared search configuration — all three critical settings (MEMORY.md).
    /// `.hotel` included because some restaurant-inns (e.g. Winsor House Inn)
    /// are classified as hotels in Apple Maps despite being full restaurants.
    private static let poiFilter = MKPointOfInterestFilter(including: [
        .restaurant, .cafe, .bakery, .brewery, .winery,
        .nightlife, .foodMarket, .store, .hotel,
    ])

    /// Queries that should skip the POI filter entirely. These are retail/shop
    /// queries where Apple Maps categorizes the results outside our food/drink
    /// POI set (e.g. "Duxbury Wine and Spirits" may not be tagged as `.store`).
    /// Without this, the POI filter silently drops liquor stores, wine shops, etc.
    private static let unfiltered: Set<String> = [
        "liquor store", "wine shop", "bottle shop", "wine spirits",
    ]

    private static func makeRegion(center: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        let c = center ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
        return MKCoordinateRegion(
            center: c,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    }

    // MARK: - Single-query search (user-typed text)

    func search(query: String, userLocation: CLLocationCoordinate2D? = nil) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        activeSearch?.cancel()
        activeSearch = nil
        searchGeneration &+= 1
        let myGeneration = searchGeneration
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = Self.poiFilter
        request.region = Self.makeRegion(center: userLocation)

        let search = MKLocalSearch(request: request)
        activeSearch = search

        do {
            let response = try await search.start()
            guard searchGeneration == myGeneration else { return }
            searchResults = response.mapItems
            activeSearch = nil
            isSearching = false
        } catch {
            guard searchGeneration == myGeneration else { return }
            activeSearch = nil
            isSearching = false

            // Leave previous results visible for ALL errors — including
            // placemarkNotFound — so the list doesn't flash "No results"
            // on every keystroke while the user is still typing.
            // Results are only cleared explicitly via clearResults().
        }
    }

    // MARK: - Multi-query search (filter-based Explore)

    /// Runs multiple search queries sequentially, merges and deduplicates
    /// results, then sorts by distance to the user. Used when a category
    /// filter is active — e.g. mezcal's mapSearchTerms ["mezcal", "bar",
    /// "restaurante", "restaurant"] are all searched so that a niche term
    /// like "mezcal" (few Apple Maps hits) is supplemented by broader
    /// terms like "bar" that return many nearby venues for the website
    /// pre-screen to re-rank.
    ///
    /// Results from the first (most specific) query appear first, so
    /// Apple Maps' relevance ranking for "mezcal" is preserved at the top.
    func multiSearch(queries: [String], userLocation: CLLocationCoordinate2D? = nil) async {
        guard !queries.isEmpty else {
            searchResults = []
            return
        }

        activeSearch?.cancel()
        activeSearch = nil
        searchGeneration &+= 1
        let myGeneration = searchGeneration
        isSearching = true

        let center = userLocation ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
        let region = Self.makeRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude))

        var allItems: [MKMapItem] = []
        var seenNames: Set<String> = []

        for query in queries {
            guard searchGeneration == myGeneration, !Task.isCancelled else { return }

            let skipFilter = Self.unfiltered.contains(query.lowercased())
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            // Skip POI filter for retail queries like "liquor store" — Apple Maps
            // may categorize these outside our food/drink POI set, silently dropping them.
            if !skipFilter {
                request.pointOfInterestFilter = Self.poiFilter
                request.region = region
            } else {
                // Retail queries use a tighter region (~10 mi) so Apple Maps prioritizes
                // truly nearby stores. With the full 0.5° span (~35 mi), MKLocalSearch
                // fills its 25-result cap with stores across the whole region, pushing
                // out small local shops like "Duxbury Wine & Spirits" even when the user
                // is standing next to them.
                request.region = MKCoordinateRegion(
                    center: region.center,
                    span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                )
            }

            #if DEBUG
            print("[Explore] query \"\(query)\" — POI filter: \(skipFilter ? "OFF" : "ON")")
            #endif

            do {
                let response = try await MKLocalSearch(request: request).start()
                let newCount = response.mapItems.count
                var addedNames: [String] = []
                for item in response.mapItems {
                    let key = (item.name ?? "").lowercased()
                    guard !key.isEmpty, seenNames.insert(key).inserted else { continue }
                    allItems.append(item)
                    addedNames.append(item.name ?? "?")
                }
                #if DEBUG
                print("[Explore] query \"\(query)\": \(newCount) raw, \(addedNames.count) new → \(allItems.count) total")
                if !addedNames.isEmpty {
                    print("[Explore]   added: \(addedNames.prefix(10).joined(separator: ", "))\(addedNames.count > 10 ? "..." : "")")
                }
                #endif
            } catch {
                #if DEBUG
                let nsErr = error as NSError
                if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                    print("[Explore] query \"\(query)\": ⚠️ THROTTLED")
                } else {
                    print("[Explore] query \"\(query)\": ❌ error \(error.localizedDescription)")
                }
                #endif
                // Continue with remaining queries — don't abort the whole search
            }
        }

        guard searchGeneration == myGeneration, !Task.isCancelled else { return }

        // Sort by distance: closest venues first.
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        allItems.sort {
            let aLoc = CLLocation(latitude: $0.placemark.coordinate.latitude,
                                   longitude: $0.placemark.coordinate.longitude)
            let bLoc = CLLocation(latitude: $1.placemark.coordinate.latitude,
                                   longitude: $1.placemark.coordinate.longitude)
            return aLoc.distance(from: centerLoc) < bLoc.distance(from: centerLoc)
        }

        // Drop results beyond ~35 miles (matches the 0.5° search region span).
        // Apple Maps treats the region as a hint, not a hard boundary, so niche
        // queries like "mezcal" or "liquor store" can return venues hundreds of
        // miles away when nearby results are sparse.
        let maxDistance: CLLocationDistance = 56_327  // ~35 miles
        allItems = allItems.filter { item in
            let loc = CLLocation(latitude: item.placemark.coordinate.latitude,
                                  longitude: item.placemark.coordinate.longitude)
            return loc.distance(from: centerLoc) <= maxDistance
        }

        searchResults = allItems
        isSearching = false

        #if DEBUG
        print("[Explore] multiSearch done: \(allItems.count) results within 35 mi from \(queries.count) queries")
        #endif
    }

    func clearResults() {
        activeSearch?.cancel()
        activeSearch = nil
        searchGeneration &+= 1
        searchResults = []
        isSearching = false
    }
}
