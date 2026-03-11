import Foundation
@preconcurrency import MapKit

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

// MARK: - SuggestionService

@MainActor
class SuggestionService: ObservableObject {
    @Published var suggestions: [SuggestedSpot] = []
    @Published var isLoading = false
    /// True once the batch homepage pre-screen has finished for the current suggestions.
    @Published var preScreenComplete = false

    /// Full pool of venues found by the last fetchSuggestions call, before
    /// trimming to `maxDisplayPins`. Stored so `batchPreScreen` can scan all
    /// of them — venues that match the user's picks are promoted into the
    /// displayed `suggestions` even if they weren't in the closest 25.
    var fullPool: [SuggestedSpot] = []

    /// Injects pre-built results from another tab (e.g. Spots → Map).
    /// Replaces any existing suggestions and marks pre-screen complete
    /// since the data already has `preScreenMatches` baked in.
    func injectResults(_ results: [SuggestedSpot]) {
        suggestions = Array(results.prefix(25))
        fullPool = results
        preScreenComplete = true
        isLoading = false
    }

    /// Reference center from the last fetch — used for distance sorting
    /// when applying pre-screen results.
    private var lastFetchCenter: CLLocation?

    /// Dismissed suggestion IDs (stable String IDs, persisted for the session)
    private var dismissedIDs: Set<String> = []

    /// Incremented each time fetchSuggestions is called. Each fetch checks
    /// its own generation value before issuing each MKLocalSearch request —
    /// if a newer call has started, the older one aborts immediately.
    /// This prevents stale batches from burning through Apple's rate limit.
    private var fetchGeneration = 0

    /// Unified search engine — delegates MKLocalSearch work so POI filter,
    /// retail bypass, and region handling exist in exactly one place.
    private let searchService = LocationSearchService()

    /// Maximum ghost pins shown on the map / in the annotation set.
    private static let maxDisplayPins = 25

    /// Fetch suggestions near the given map region for the user's chosen picks.
    ///
    /// Strategy: run each pick's mapSearchTerms as text queries, collect every
    /// result into one pool, deduplicate by name, sort by distance to region
    /// center, then show the closest `maxDisplayPins`. The full pool is kept
    /// in `fullPool` so the pre-screen can scan every venue — green matches
    /// are promoted into the displayed set even if they weren't in the initial 25.
    ///
    /// No broad or POI-category queries — each pick's mapSearchTerms already
    /// include the right mix of specific + broad terms (e.g. mezcal's terms
    /// are ["mezcal", "bar", "liquor store", "restaurante", "restaurant"]).
    /// This keeps the total MKLocalSearch call count low (~5 per pick) so
    /// every term actually runs without throttling.
    func fetchSuggestions(in region: MKCoordinateRegion,
                          existingSpots: [Spot],
                          picks: [FoodCategory],
                          radius: Double = 0.5) async {
        fetchGeneration &+= 1
        let myGeneration = fetchGeneration

        isLoading = true
        var pool: [SuggestedSpot] = []
        var seenNames: Set<String> = []

        // Build tagged queries from all picks' mapSearchTerms, deduplicating
        // across picks so e.g. "restaurant" isn't searched twice.
        var seenQueries = Set<String>()
        var taggedQueries: [(query: String, tag: String)] = []
        for pick in picks {
            for term in pick.mapSearchTerms {
                let key = term.lowercased()
                if seenQueries.insert(key).inserted {
                    taggedQueries.append((query: term, tag: pick.id))
                }
            }
        }

        #if DEBUG
        print("[Suggestions] Fetching for region center (\(String(format: "%.4f", region.center.latitude)), \(String(format: "%.4f", region.center.longitude))), picks: \(picks.map(\.id)), \(taggedQueries.count) unique queries: \(taggedQueries.map(\.query))")
        #endif

        // Existing confirmed spot names — never re-suggest these.
        // Exclude hidden spots so ghost pins reappear when user removes all categories.
        let existingNames = Set(existingSpots.filter { !$0.isHidden }.map { $0.name.lowercased() })

        // Reference point for distance sorting in applyPreScreenResults
        let regionCenter = CLLocation(latitude: region.center.latitude,
                                      longitude: region.center.longitude)

        // ── Delegate to the unified search engine ────────────────────────
        // taggedMultiSearch applies the correct POI filter, retail bypass,
        // region handling, distance sort, and hard distance cutoff.
        let taggedResults = await searchService.taggedMultiSearch(
            queries: taggedQueries,
            center: region.center,
            radius: radius
        )
        guard fetchGeneration == myGeneration else { isLoading = false; return }

        // Convert TaggedSearchResults → SuggestedSpots with category tracking.
        let picksByID = Dictionary(uniqueKeysWithValues: picks.map { ($0.id, $0) })
        for result in taggedResults {
            guard let name = result.item.name else { continue }
            let key = name.lowercased()
            if existingNames.contains(key) {
                #if DEBUG
                print("[Suggestions] Skipped \"\(name)\" — already a confirmed spot")
                #endif
                continue
            }
            if !seenNames.insert(key).inserted { continue }
            let category = picksByID[result.tag] ?? picks[0]
            pool.append(SuggestedSpot(mapItem: result.item, suggestedCategory: category))
        }

        // Remove dismissed venues from the pool
        let validPool = pool.filter { !dismissedIDs.contains($0.id) }
        let found = Array(validPool.prefix(Self.maxDisplayPins))

        #if DEBUG
        print("[Suggestions] Pool: \(pool.count) unique venues → closest \(found.count) kept (full pool: \(validPool.count))")
        print("[Suggestions] Venues: \(found.map(\.name).joined(separator: ", "))")
        #endif

        // A newer fetch started while we were running — discard our results entirely.
        guard fetchGeneration == myGeneration else { isLoading = false; return }

        // Replace suggestions when results are non-empty. taggedMultiSearch
        // handles throttling internally (continues with remaining queries),
        // so a partial result set is still the best available.
        if !found.isEmpty {
            suggestions = found
            // Store the full pool (distance-sorted, dismissed removed) for pre-screening.
            // batchPreScreen will scan all of these, and applyPreScreenResults will
            // promote green matches into the displayed suggestions.
            fullPool = validPool
            lastFetchCenter = regionCenter
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

    /// Updates suggestions with batch pre-screen results, promoting green
    /// matches from the full pool into the displayed set.
    ///
    /// The `results` dict contains entries for every venue that had a scannable URL:
    /// - Non-empty set → homepage matched keywords for user's picks (green pin)
    /// - Empty set → URL was scanned but no keywords matched (dimmed yellow pin)
    /// - Not in dict → venue had no URL / social media only (stays yellow "?" pin)
    func applyPreScreenResults(_ results: [String: Set<String>]) {
        // Apply pre-screen results to the full pool first.
        let updatedPool = fullPool.map { suggestion in
            var updated = suggestion
            if let matched = results[suggestion.id] {
                updated.preScreenMatches = matched
            }
            return updated
        }

        // Re-sort: green matches first (sorted by distance), then remaining
        // (sorted by distance). Take the best maxDisplayPins.
        //
        // Promotion cap: only promote green pins within a reasonable distance
        // of the search center (the 25th-closest venue's distance × 1.5).
        // Green pins beyond this cap are interleaved by distance with
        // non-green pins so a match 30 miles away doesn't displace a
        // nearby unchecked pin.
        let regionCenter = lastFetchCenter
        func distance(_ s: SuggestedSpot) -> Double {
            guard let center = regionCenter else { return 0 }
            let loc = CLLocation(latitude: s.coordinate.latitude,
                                  longitude: s.coordinate.longitude)
            return loc.distance(from: center)
        }

        // Determine the promotion distance cap: 1.5× the distance of the
        // 25th-closest venue (i.e. the initial display edge).
        let sortedByDistance = updatedPool.sorted { distance($0) < distance($1) }
        let capIndex = min(Self.maxDisplayPins - 1, sortedByDistance.count - 1)
        let promotionCap = capIndex >= 0
            ? distance(sortedByDistance[capIndex]) * 1.5
            : Double.greatestFiniteMagnitude

        // "Nearby green" = green matches within the promotion cap → sorted first
        // "Far green" + non-green → interleaved by distance
        let nearbyGreen = updatedPool
            .filter { $0.preScreenMatches?.isEmpty == false && distance($0) <= promotionCap }
            .sorted { distance($0) < distance($1) }
        let rest = updatedPool
            .filter { !($0.preScreenMatches?.isEmpty == false && distance($0) <= promotionCap) }
            .sorted { distance($0) < distance($1) }

        let combined = nearbyGreen + rest
        let trimmed = Array(combined.prefix(Self.maxDisplayPins))

        #if DEBUG
        print("[ApplyPreScreen] Applying \(results.count) results to pool of \(fullPool.count)")
        let allGreen = updatedPool.filter { $0.preScreenMatches?.isEmpty == false }
        print("[ApplyPreScreen] Green matches in pool: \(allGreen.count) (\(nearbyGreen.count) nearby, \(allGreen.count - nearbyGreen.count) beyond cap)")
        for s in allGreen {
            print("[ApplyPreScreen]   GREEN: \(s.name) → \(s.preScreenMatches!) dist=\(Int(distance(s)))m")
        }
        print("[ApplyPreScreen] Promotion cap: \(Int(promotionCap))m, Final display: \(trimmed.count) pins (\(trimmed.filter { $0.preScreenMatches?.isEmpty == false }.count) green)")
        #endif

        suggestions = trimmed
        preScreenComplete = true
    }
}
