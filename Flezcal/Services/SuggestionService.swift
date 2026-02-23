import Foundation
import MapKit

/// A suggested (unconfirmed) spot found via Apple Maps search.
/// Shown on the map as a ghost pin until a user confirms or dismisses it.
struct SuggestedSpot: Identifiable, Equatable {
    static func == (lhs: SuggestedSpot, rhs: SuggestedSpot) -> Bool {
        lhs.id == rhs.id
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
//
// Two-tier strategy per FoodCategory pick:
//
// ── Tier 1 (broad POI category passes) ───────────────────────────────────────
//   MKPointOfInterestCategory passes that cast the widest net.
//   Hardcoded for well-known POI types; other categories skip to Tier 2.
//
// ── Tier 2 (natural-language text queries) ───────────────────────────────────
//   Uses the FoodCategory's mapSearchTerms directly.
//   Works for every category without any hardcoding here.
// ─────────────────────────────────────────────────────────────────────────────

/// Returns broad MKPointOfInterestCategory passes for a FoodCategory, if applicable.
/// Categories without a clear POI mapping return an empty array (Tier 2 only).
private func tier1Passes(for pick: FoodCategory) -> [([MKPointOfInterestCategory], FoodCategory)] {
    switch pick.id {
    case "mezcal":
        return [
            ([.nightlife, .brewery, .winery], pick),
            ([.restaurant], pick),
        ]
    case "flan":
        return [([.bakery, .foodMarket], pick)]
    case "craft_beer":
        return [([.brewery], pick)]
    case "specialty_coffee":
        return [([.cafe], pick)]
    case "sushi", "ramen", "tacos", "dim_sum", "pizza", "birria", "pho":
        return [([.restaurant], pick)]
    case "oysters":
        return [([.restaurant], pick)]
    default:
        return []  // Tier 2 text queries only
    }
}

/// Builds up to 3 Tier 2 text queries for a FoodCategory.
/// With 3 active picks this produces at most 9 Tier 2 queries per fetch — well under
/// Apple Maps' 50-requests-per-60-seconds rate limit when combined with Tier 1 passes.
/// The third term matters for categories like mezcal where a Spanish-language query
/// ("restaurante") catches venues in Mexico that English-only terms miss.
private func tier2Queries(for pick: FoodCategory) -> [(query: String, category: FoodCategory)] {
    pick.mapSearchTerms.prefix(3).map { (query: $0, category: pick) }
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

    /// Maximum ghost pins shown at once.
    /// Raised from 20 to 40 to accommodate the broad Tier 0 pass — the batch
    /// homepage pre-screen filters down to green/yellow pins so showing more
    /// doesn't overwhelm the user.
    private static let maxTotalSuggestions = 40
    /// Maximum results accepted from a single query/pass.
    /// Prevents one broad category pass from monopolising the total cap.
    private static let maxPerQuery = 15

    /// Fetch suggestions near the given map region for the user's chosen picks.
    ///
    /// - Parameters:
    ///   - picks: The user's active FoodCategory selections from UserPicksService.
    ///            Pass a single-element array to restrict to one category,
    ///            or the full picks array for "All".
    ///   - existingSpots: Confirmed spots to exclude from suggestions.
    func fetchSuggestions(in region: MKCoordinateRegion,
                          existingSpots: [Spot],
                          picks: [FoodCategory]) async {
        fetchGeneration &+= 1
        let myGeneration = fetchGeneration

        isLoading = true
        var found: [SuggestedSpot] = []
        var anyThrottled = false

        print("[Suggestions] Fetching for region center (\(String(format: "%.4f", region.center.latitude)), \(String(format: "%.4f", region.center.longitude))) span (\(String(format: "%.4f", region.span.latitudeDelta)), \(String(format: "%.4f", region.span.longitudeDelta))), picks: \(picks.map(\.id))")

        // Build query lists from the active picks
        let activeCategoryPasses = picks.flatMap { tier1Passes(for: $0) }
        let activeTextQueries    = picks.flatMap { tier2Queries(for: $0) }

        // Existing confirmed spot names — never re-suggest these
        let existingNames = Set(existingSpots.map { $0.name.lowercased() })

        // Global dedup set across ALL passes — prevents cross-pass duplicates
        var seenNames: Set<String> = []

        // Reference point for distance sorting — region center (user's map view center)
        let regionCenter = CLLocation(latitude: region.center.latitude,
                                      longitude: region.center.longitude)

        // Helper: absorb MapKit results into `found`, honouring both caps.
        // Sorts items by distance to region center before processing so the
        // nearest venues fill the cap first.
        func absorb(_ items: [MKMapItem], as pick: FoodCategory) {
            let sorted = items.sorted {
                let aLoc = CLLocation(latitude: $0.placemark.coordinate.latitude,
                                      longitude: $0.placemark.coordinate.longitude)
                let bLoc = CLLocation(latitude: $1.placemark.coordinate.latitude,
                                      longitude: $1.placemark.coordinate.longitude)
                return aLoc.distance(from: regionCenter) < bLoc.distance(from: regionCenter)
            }
            var countThisPass = 0
            for item in sorted {
                guard found.count < Self.maxTotalSuggestions else { return }
                guard countThisPass < Self.maxPerQuery else { return }
                guard let name = item.name else { continue }
                let key = name.lowercased()
                if existingNames.contains(key) { continue }
                if !seenNames.insert(key).inserted { continue }
                found.append(SuggestedSpot(mapItem: item, suggestedCategory: pick))
                countThisPass += 1
            }
        }

        // ── Tier 0: broad "all nearby food/drink" passes ────────────────────────
        // Multiple text queries that cast the widest net. Apple Maps returns more
        // results when a naturalLanguageQuery is provided alongside the POI filter.
        // A POI-filter-only request (no text query) returns very few results in
        // sparse areas.  Using broad terms like "restaurant", "cafe", "bar" finds
        // venues that pick-specific Tier 1/2 queries miss.
        if let defaultPick = picks.first {
            let broadQueries = ["restaurant", "cafe", "bar", "food"]
            let broadFilter = MKPointOfInterestFilter(including: [
                .restaurant, .cafe, .bakery, .brewery, .winery,
                .nightlife, .foodMarket, .store
            ])
            for query in broadQueries {
                guard fetchGeneration == myGeneration else { break }
                guard found.count < Self.maxTotalSuggestions else { break }
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = region
                request.resultTypes = .pointOfInterest
                request.pointOfInterestFilter = broadFilter
                do {
                    let response = try await MKLocalSearch(request: request).start()
                    let before = found.count
                    absorb(response.mapItems, as: defaultPick)
                    print("[Suggestions] Tier 0 \"\(query)\": \(response.mapItems.count) raw → \(found.count - before) new (total \(found.count))")
                } catch {
                    let nsErr = error as NSError
                    if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                        anyThrottled = true
                        print("[Suggestions] Tier 0 \"\(query)\": THROTTLED")
                    } else {
                        print("[Suggestions] Tier 0 \"\(query)\": error \(error.localizedDescription)")
                    }
                }
            }
        }

        // ── Tier 1: MKPointOfInterestCategory passes ──────────────────────────
        for (categories, pick) in activeCategoryPasses {
            guard fetchGeneration == myGeneration else { break }
            guard found.count < Self.maxTotalSuggestions else { break }
            let request = MKLocalSearch.Request()
            request.region = region
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            do {
                let response = try await MKLocalSearch(request: request).start()
                let before = found.count
                absorb(response.mapItems, as: pick)
                print("[Suggestions] Tier 1 \(pick.id) \(categories.map(\.rawValue)): \(response.mapItems.count) raw → \(found.count - before) new (total \(found.count))")
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                    anyThrottled = true
                    print("[Suggestions] Tier 1 \(pick.id): THROTTLED")
                } else {
                    print("[Suggestions] Tier 1 \(pick.id): error \(error.localizedDescription)")
                }
            }
        }

        // ── Tier 2: natural-language text queries ─────────────────────────────
        for entry in activeTextQueries {
            guard fetchGeneration == myGeneration else { break }
            guard found.count < Self.maxTotalSuggestions else { break }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = entry.query
            request.region = region
            request.resultTypes = .pointOfInterest
            do {
                let response = try await MKLocalSearch(request: request).start()
                let before = found.count
                absorb(response.mapItems, as: entry.category)
                print("[Suggestions] Tier 2 \"\(entry.query)\": \(response.mapItems.count) raw → \(found.count - before) new (total \(found.count))")
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                    anyThrottled = true
                    print("[Suggestions] Tier 2 \"\(entry.query)\": THROTTLED")
                } else {
                    print("[Suggestions] Tier 2 \"\(entry.query)\": error \(error.localizedDescription)")
                }
            }
        }

        print("[Suggestions] Total found: \(found.count) venues: \(found.map(\.name).joined(separator: ", "))")

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
    /// Each suggestion gets its `preScreenMatches` set: non-empty if the
    /// homepage HTML contained keywords for the user's active picks,
    /// empty `Set()` if scanned but nothing found, or stays `nil` if
    /// the venue had no fetchable URL.
    func applyPreScreenResults(_ results: [String: Set<String>]) {
        for i in suggestions.indices {
            let id = suggestions[i].id
            if let matched = results[id] {
                suggestions[i].preScreenMatches = matched
            } else if suggestions[i].preScreenMatches == nil {
                // Mark as scanned-but-not-found (distinct from not-yet-scanned)
                suggestions[i].preScreenMatches = Set()
            }
        }
        preScreenComplete = true
    }
}
