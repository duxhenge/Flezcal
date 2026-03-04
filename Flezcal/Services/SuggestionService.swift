import Foundation
import MapKit

/// A suggested (unconfirmed) spot found via Apple Maps search.
/// Shown on the map as a ghost pin until a user confirms or dismisses it.
struct SuggestedSpot: Identifiable, Equatable {
    static func == (lhs: SuggestedSpot, rhs: SuggestedSpot) -> Bool {
        lhs.id == rhs.id &&
        lhs.preScreenMatches == rhs.preScreenMatches
    }

    /// Stable ID derived from the venue name so the same venue keeps the
    /// same ID across successive fetches. This lets SwiftUI diff map
    /// annotations correctly and lets website-check results survive re-fetches.
    var id: String { name.lowercased() }
    let mapItem: MKMapItem
    /// The FoodCategory pick that produced this suggestion.
    let suggestedCategory: FoodCategory

    /// Categories found during batch homepage pre-screen.
    /// `nil` = not yet scanned. Empty set = scanned, nothing found.
    /// Non-empty set = homepage HTML matched these category IDs.
    var preScreenMatches: Set<String>? = nil

    var name: String { mapItem.name ?? "Unknown" }
    var coordinate: CLLocationCoordinate2D { mapItem.placemark.coordinate }
    var address: String { mapItem.placemark.formattedAddress ?? "" }
}

// MARK: - Query building

/// Builds text queries for a FoodCategory from all its mapSearchTerms.
private func textQueries(for pick: FoodCategory) -> [(query: String, category: FoodCategory)] {
    pick.mapSearchTerms.map { (query: $0, category: pick) }
}

// MARK: - SuggestionService

@MainActor
class SuggestionService: ObservableObject {
    @Published var suggestions: [SuggestedSpot] = []
    @Published var isLoading = false
    /// True once the batch homepage pre-screen has finished for the current suggestions.
    @Published var preScreenComplete = false

    /// Dismissed suggestion IDs (stable String IDs, persisted for the session)
    private var dismissedIDs: Set<String> = []

    /// Incremented each time fetchSuggestions is called. Each fetch checks
    /// its own generation value before issuing each MKLocalSearch request —
    /// if a newer call has started, the older one aborts immediately.
    /// This prevents stale batches from burning through Apple's rate limit.
    private var fetchGeneration = 0

    /// Maximum ghost pins returned after sorting by distance.
    private static let maxSuggestions = 25

    /// Fetch suggestions near the given map region for the user's chosen picks.
    ///
    /// Strategy: run each pick's mapSearchTerms as text queries, collect every
    /// result into one pool, deduplicate by name, sort by distance to region
    /// center, then take the closest `maxSuggestions`.
    ///
    /// No broad or POI-category queries — each pick's mapSearchTerms already
    /// include the right mix of specific + broad terms (e.g. mezcal's terms
    /// are ["mezcal", "bar", "liquor store", "restaurante", "restaurant"]).
    /// This keeps the total MKLocalSearch call count low (~5 per pick) so
    /// every term actually runs without throttling.
    func fetchSuggestions(in region: MKCoordinateRegion,
                          existingSpots: [Spot],
                          picks: [FoodCategory]) async {
        fetchGeneration &+= 1
        let myGeneration = fetchGeneration

        isLoading = true
        var pool: [SuggestedSpot] = []
        var seenNames: Set<String> = []
        var anyThrottled = false

        // Build the query list from all picks' mapSearchTerms, deduplicating
        // across picks so e.g. "restaurant" isn't searched twice.
        var seenQueries = Set<String>()
        var allQueries: [(query: String, category: FoodCategory)] = []
        for pick in picks {
            for entry in textQueries(for: pick) {
                let key = entry.query.lowercased()
                if seenQueries.insert(key).inserted {
                    allQueries.append(entry)
                }
            }
        }

        #if DEBUG
        print("[Suggestions] Fetching for region center (\(String(format: "%.4f", region.center.latitude)), \(String(format: "%.4f", region.center.longitude))) span (\(String(format: "%.4f", region.span.latitudeDelta)), \(String(format: "%.4f", region.span.longitudeDelta))), picks: \(picks.map(\.id)), \(allQueries.count) unique queries: \(allQueries.map(\.query))")
        #endif

        // Existing confirmed spot names — never re-suggest these
        let existingNames = Set(existingSpots.map { $0.name.lowercased() })

        // Reference point for distance sorting
        let regionCenter = CLLocation(latitude: region.center.latitude,
                                      longitude: region.center.longitude)

        // Helper: deduplicate and add items to the pool.
        func absorb(_ items: [MKMapItem], as pick: FoodCategory) {
            for item in items {
                guard let name = item.name else { continue }
                let key = name.lowercased()
                if existingNames.contains(key) { continue }
                if !seenNames.insert(key).inserted { continue }
                pool.append(SuggestedSpot(mapItem: item, suggestedCategory: pick))
            }
        }

        // Helper: run a single MKLocalSearch and absorb results.
        func runQuery(_ request: MKLocalSearch.Request,
                      as pick: FoodCategory,
                      label: String) async {
            do {
                let response = try await MKLocalSearch(request: request).start()
                let before = pool.count
                absorb(response.mapItems, as: pick)
                #if DEBUG
                print("[Suggestions] \(label): \(response.mapItems.count) raw → \(pool.count - before) new (pool \(pool.count))")
                #endif
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                    anyThrottled = true
                    #if DEBUG
                    print("[Suggestions] \(label): THROTTLED")
                    #endif
                } else {
                    #if DEBUG
                    print("[Suggestions] \(label): error \(error.localizedDescription)")
                    #endif
                }
            }
        }

        // Enforce a minimum search span so zoomed-in maps still discover
        // the same venues the Explore tab finds with its fixed 0.5° region.
        // MKLocalSearch treats region as a relevance hint — a tiny region
        // causes it to return different (often fewer) results for the same query.
        let minSpan = 0.5
        let searchRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta:  max(region.span.latitudeDelta,  minSpan),
                longitudeDelta: max(region.span.longitudeDelta, minSpan)
            )
        )

        // ── Run each pick's mapSearchTerms as text queries ────────────────
        for entry in allQueries {
            guard fetchGeneration == myGeneration else { break }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = entry.query
            request.region = searchRegion
            request.resultTypes = .pointOfInterest
            await runQuery(request, as: entry.category, label: "\(entry.category.id) \"\(entry.query)\"")
        }

        // ── Sort by distance, take closest maxSuggestions ───────────────────
        pool.sort {
            let aLoc = CLLocation(latitude: $0.coordinate.latitude,
                                   longitude: $0.coordinate.longitude)
            let bLoc = CLLocation(latitude: $1.coordinate.latitude,
                                   longitude: $1.coordinate.longitude)
            return aLoc.distance(from: regionCenter) < bLoc.distance(from: regionCenter)
        }
        let found = Array(pool.prefix(Self.maxSuggestions))

        #if DEBUG
        print("[Suggestions] Pool: \(pool.count) unique venues → closest \(found.count) kept")
        print("[Suggestions] Venues: \(found.map(\.name).joined(separator: ", "))")
        #endif

        // A newer fetch started while we were running — discard our results entirely.
        guard fetchGeneration == myGeneration else { isLoading = false; return }

        // Remove any the user has already dismissed this session
        let newSuggestions = found.filter { !dismissedIDs.contains($0.id) }

        // Only replace suggestions when:
        //   • The fetch found at least one result, AND
        //   • Either the fetch was not throttled, OR it found more than what we already have.
        // This prevents a throttled partial fetch from downgrading a good prior result set.
        let shouldReplace = !newSuggestions.isEmpty &&
            (!anyThrottled || newSuggestions.count >= suggestions.count)
        if shouldReplace {
            suggestions = newSuggestions
        }
        isLoading = false
    }

    /// User said "not accurate" — hide this suggestion for the session
    func dismiss(_ suggestion: SuggestedSpot) {
        dismissedIDs.insert(suggestion.id)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    /// User confirmed a suggestion was added — remove it from suggestions
    func confirm(_ suggestion: SuggestedSpot) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    /// Updates suggestions in-place with batch pre-screen results.
    ///
    /// The `results` dict contains entries for every venue that had a scannable URL:
    /// - Non-empty set → homepage matched keywords for user's picks (green pin)
    /// - Empty set → URL was scanned but no keywords matched (dimmed yellow pin)
    /// - Not in dict → venue had no URL / social media only (stays yellow "?" pin)
    func applyPreScreenResults(_ results: [String: Set<String>]) {
        for i in suggestions.indices {
            let id = suggestions[i].id
            if let matched = results[id] {
                // Venue was in the scan set — update with result (possibly empty)
                suggestions[i].preScreenMatches = matched
            }
            // Venues not in results had no scannable URL — keep preScreenMatches = nil
        }
        preScreenComplete = true
    }
}
