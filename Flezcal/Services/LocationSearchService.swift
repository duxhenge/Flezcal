import Foundation
@preconcurrency import MapKit
import CoreLocation

/// A search result tagged with an arbitrary string (typically a FoodCategory ID)
/// so callers know which query produced each venue.
struct TaggedSearchResult {
    let item: MKMapItem
    let tag: String
}

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

    private static func makeRegion(center: CLLocationCoordinate2D?, radius: Double = 0.5) -> MKCoordinateRegion {
        let c = center ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
        return MKCoordinateRegion(
            center: c,
            span: MKCoordinateSpan(latitudeDelta: radius, longitudeDelta: radius)
        )
    }

    // MARK: - Single-query search (user-typed venue name)

    /// Venue-name search for the add-spot workflow. No POI filter — the user
    /// is looking for a specific place by name, so we don't restrict categories.
    /// Apple Maps may classify a tea house or juice bar outside our food/drink
    /// POI set; removing the filter lets those results come through.
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
        // No POI filter — venue-name search should find any place by name.
        // Category browsing (taggedMultiSearch) still uses the food/drink filter.
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

    // MARK: - Tagged multi-query search (unified search engine)

    /// Core search engine: runs multiple tagged queries sequentially, merges
    /// and deduplicates results by venue name, sorts by distance, and applies
    /// a hard distance cutoff. Returns a pure data array — does NOT touch
    /// `@Published` properties.
    ///
    /// Both `multiSearch` (Spots tab) and `SuggestionService` (Map tab)
    /// delegate to this method so search configuration (POI filter, retail
    /// bypass, region handling) exists in exactly one place.
    ///
    /// - Parameters:
    ///   - queries: Each entry is a `(query, tag)` tuple. The tag (typically
    ///     a FoodCategory ID) is preserved in the result so callers know
    ///     which query produced each venue. First tag wins on dedup.
    ///   - center: Geographic center for the search region and distance sort.
    ///   - radius: Search span in degrees (default 0.5°). Also used for the
    ///     hard distance cutoff (radius × 111 km).
    func taggedMultiSearch(
        queries: [(query: String, tag: String)],
        center: CLLocationCoordinate2D,
        radius: Double = 0.5
    ) async -> [TaggedSearchResult] {
        let region = Self.makeRegion(center: center, radius: radius)
        var results: [TaggedSearchResult] = []
        var seenNames: Set<String> = []

        for entry in queries {
            guard !Task.isCancelled else { break }

            let skipFilter = Self.unfiltered.contains(entry.query.lowercased())
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = entry.query
            request.resultTypes = .pointOfInterest
            if !skipFilter {
                request.pointOfInterestFilter = Self.poiFilter
                request.region = region
            } else {
                let retailSpan = radius * 0.3
                request.region = MKCoordinateRegion(
                    center: region.center,
                    span: MKCoordinateSpan(latitudeDelta: retailSpan, longitudeDelta: retailSpan)
                )
            }

            #if DEBUG
            print("[Search] query \"\(entry.query)\" tag=\(entry.tag) — POI filter: \(skipFilter ? "OFF" : "ON")")
            #endif

            do {
                let response = try await MKLocalSearch(request: request).start()
                var addedCount = 0
                for item in response.mapItems {
                    let key = (item.name ?? "").lowercased()
                    guard !key.isEmpty, seenNames.insert(key).inserted else { continue }
                    results.append(TaggedSearchResult(item: item, tag: entry.tag))
                    addedCount += 1
                }
                #if DEBUG
                print("[Search] query \"\(entry.query)\": \(response.mapItems.count) raw, \(addedCount) new → \(results.count) total")
                #endif
            } catch {
                #if DEBUG
                let nsErr = error as NSError
                if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                    print("[Search] query \"\(entry.query)\": ⚠️ THROTTLED")
                } else {
                    print("[Search] query \"\(entry.query)\": ❌ error \(error.localizedDescription)")
                }
                #endif
            }
        }

        // Sort by distance: closest venues first.
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        results.sort {
            let aLoc = CLLocation(latitude: $0.item.placemark.coordinate.latitude,
                                   longitude: $0.item.placemark.coordinate.longitude)
            let bLoc = CLLocation(latitude: $1.item.placemark.coordinate.latitude,
                                   longitude: $1.item.placemark.coordinate.longitude)
            return aLoc.distance(from: centerLoc) < bLoc.distance(from: centerLoc)
        }

        // Hard distance cutoff — 1° ≈ 111 km.
        let maxDistance: CLLocationDistance = radius * 111_000
        results.removeAll { result in
            let loc = CLLocation(latitude: result.item.placemark.coordinate.latitude,
                                  longitude: result.item.placemark.coordinate.longitude)
            return loc.distance(from: centerLoc) > maxDistance
        }

        #if DEBUG
        print("[Search] taggedMultiSearch done: \(results.count) results within \(String(format: "%.0f", radius * 111))km from \(queries.count) queries")
        #endif

        return results
    }

    // MARK: - Multi-query search (filter-based Explore)

    /// Thin wrapper around `taggedMultiSearch` for the Spots tab. Manages
    /// generation counter and `@Published` state; delegates the actual
    /// MKLocalSearch work to the unified engine.
    func multiSearch(queries: [String], userLocation: CLLocationCoordinate2D? = nil, radius: Double = 0.5) async {
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
        let tagged = queries.map { (query: $0, tag: "") }
        let results = await taggedMultiSearch(queries: tagged, center: center, radius: radius)

        guard searchGeneration == myGeneration, !Task.isCancelled else { return }
        searchResults = results.map(\.item)
        isSearching = false
    }

    func clearResults() {
        activeSearch?.cancel()
        activeSearch = nil
        searchGeneration &+= 1
        searchResults = []
        isSearching = false
    }
}
