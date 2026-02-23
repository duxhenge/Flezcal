import Foundation
import MapKit

/// A suggested (unconfirmed) spot found via Apple Maps search.
/// Shown on the map as a ghost pin until a user confirms or dismisses it.
struct SuggestedSpot: Identifiable {
    /// Stable ID derived from the venue name so the same venue keeps the
    /// same ID across successive fetches. This lets SwiftUI diff map
    /// annotations correctly and lets website-check results survive re-fetches.
    var id: String { name.lowercased() }
    let mapItem: MKMapItem
    /// The FoodCategory pick that produced this suggestion.
    let suggestedCategory: FoodCategory

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
    case "ramen", "tacos", "dim_sum", "pizza", "birria", "pho":
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

    /// Dismissed suggestion IDs (stable String IDs, persisted for the session)
    private var dismissedIDs: Set<String> = []

    /// Incremented each time fetchSuggestions is called. Each fetch checks
    /// its own generation value before issuing each MKLocalSearch request —
    /// if a newer call has started, the older one aborts immediately.
    /// This prevents stale batches from burning through Apple's rate limit.
    private var fetchGeneration = 0

    /// Maximum ghost pins shown at once — keeps MapKit annotation rendering smooth.
    private static let maxTotalSuggestions = 20
    /// Maximum results accepted from a single query/pass.
    /// Prevents one broad category pass from monopolising the total cap.
    private static let maxPerQuery = 10

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
                absorb(response.mapItems, as: pick)
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                    anyThrottled = true
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
                absorb(response.mapItems, as: entry.category)
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == MKErrorDomain, nsErr.code == MKError.loadingThrottled.rawValue {
                    anyThrottled = true
                }
            }
        }

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
}
