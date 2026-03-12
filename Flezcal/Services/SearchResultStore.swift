import Foundation
@preconcurrency import MapKit
import CoreLocation

// MARK: - SuggestedSpot

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

// MARK: - SearchResultStore

/// Single source of truth for search results shared between Map and Spots tabs.
///
/// Replaces the previous architecture where `SuggestionService` (Map),
/// `ExplorePanel` (Spots), and `ContentView` (relay) each held independent
/// copies of the same data. Now both tabs read from this one store.
///
/// **What this store owns:**
/// - The canonical `[SuggestedSpot]` array (`suggestions` / `fullPool`)
/// - Pre-screen state (`preScreenComplete`)
/// - Fetch lifecycle (`isLoading`, `fetchGeneration`)
/// - Unified filtering (replaces 4 duplicate filter implementations)
///
/// **What this store does NOT own:**
/// - MKLocalSearch configuration (delegated to `LocationSearchService`)
/// - Website checking / HTML scanning (stays in `WebsiteCheckService`)
/// - Venue-name search (stays local in `ExplorePanel`)
@MainActor
class SearchResultStore: ObservableObject {
    // ── Canonical data ──────────────────────────────────────────────────

    @Published var suggestions: [SuggestedSpot] = []
    @Published var isLoading = false
    /// True once the batch homepage pre-screen has finished for the current suggestions.
    @Published var preScreenComplete = false

    /// Full pool of venues found by the last fetchSuggestions call, before
    /// trimming to `maxDisplayPins`. Stored so `batchPreScreen` can scan all
    /// of them — venues that match the user's picks are promoted into the
    /// displayed `suggestions` even if they weren't in the closest 25.
    var fullPool: [SuggestedSpot] = []

    /// Reference center from the last fetch — used for distance sorting
    /// when applying pre-screen results.
    var lastFetchCenter: CLLocation?

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

    // MARK: - Fetch suggestions

    /// Fetch suggestions near the given map region for the user's chosen picks.
    ///
    /// Strategy: run each pick's mapSearchTerms as text queries, collect every
    /// result into one pool, deduplicate by name, sort by distance to region
    /// center, then show the closest `maxDisplayPins`. The full pool is kept
    /// in `fullPool` so the pre-screen can scan every venue — green matches
    /// are promoted into the displayed set even if they weren't in the initial 25.
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
        print("[SearchResultStore] Fetching for region center (\(String(format: "%.4f", region.center.latitude)), \(String(format: "%.4f", region.center.longitude))), picks: \(picks.map(\.id)), \(taggedQueries.count) unique queries: \(taggedQueries.map(\.query))")
        #endif

        // Existing confirmed spot names — never re-suggest these.
        // Exclude hidden spots so ghost pins reappear when user removes all categories.
        let existingNames = Set(existingSpots.filter { !$0.isHidden }.map { $0.name.lowercased() })

        // Reference point for distance sorting in applyPreScreenResults
        let regionCenter = CLLocation(latitude: region.center.latitude,
                                      longitude: region.center.longitude)

        // ── Delegate to the unified search engine ────────────────────────
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
                print("[SearchResultStore] Skipped \"\(name)\" — already a confirmed spot")
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
        print("[SearchResultStore] Pool: \(pool.count) unique venues → closest \(found.count) kept (full pool: \(validPool.count))")
        print("[SearchResultStore] Venues: \(found.map(\.name).joined(separator: ", "))")
        #endif

        // A newer fetch started while we were running — discard our results entirely.
        guard fetchGeneration == myGeneration else { isLoading = false; return }

        // Replace suggestions when results are non-empty.
        if !found.isEmpty {
            suggestions = found
            fullPool = validPool
            lastFetchCenter = regionCenter
        }
        isLoading = false
    }

    // MARK: - Inject cross-tab results

    /// Injects pre-built results from another tab (e.g. Spots → Map).
    /// Replaces any existing suggestions and marks pre-screen complete
    /// since the data already has `preScreenMatches` baked in.
    /// Deduplicates by venue name (lowercased) to prevent overlapping pins.
    func injectResults(_ results: [SuggestedSpot]) {
        var seenIDs = Set<String>()
        let unique = results.filter { seenIDs.insert($0.id).inserted }
        suggestions = Array(unique.prefix(Self.maxDisplayPins))
        fullPool = unique
        preScreenComplete = true
        isLoading = false
    }

    // MARK: - Pre-screen

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
        print("[SearchResultStore] Applying \(results.count) pre-screen results to pool of \(fullPool.count)")
        let allGreen = updatedPool.filter { $0.preScreenMatches?.isEmpty == false }
        print("[SearchResultStore] Green matches in pool: \(allGreen.count) (\(nearbyGreen.count) nearby, \(allGreen.count - nearbyGreen.count) beyond cap)")
        for s in allGreen {
            print("[SearchResultStore]   GREEN: \(s.name) → \(s.preScreenMatches!) dist=\(Int(distance(s)))m")
        }
        print("[SearchResultStore] Promotion cap: \(Int(promotionCap))m, Final display: \(trimmed.count) pins (\(trimmed.filter { $0.preScreenMatches?.isEmpty == false }.count) green)")
        #endif

        // Update fullPool with pre-screen data so subsequent reads see it
        fullPool = updatedPool
        suggestions = trimmed
        preScreenComplete = true
    }

    // MARK: - Dismiss / Confirm

    /// User said "not accurate" — hide this suggestion for the session
    func dismiss(_ suggestion: SuggestedSpot) {
        dismissedIDs.insert(suggestion.id)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    /// User confirmed a suggestion was added — remove it from suggestions
    func confirm(_ suggestion: SuggestedSpot) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    // MARK: - Unified Filtering

    /// Ghost pins filtered to exclude any that share a name with a confirmed spot.
    /// Replaces MapTabView.filteredSuggestions.
    func filteredSuggestions(existingSpotNames: Set<String>) -> [SuggestedSpot] {
        suggestions.filter { suggestion in
            !existingSpotNames.contains(suggestion.name.lowercased())
        }
    }

    /// Ghost pins filtered by pin-type toggles AND active pick IDs.
    /// Replaces MapTabView.visibleGhostPins and MapPinListView.ghostPins.
    ///
    /// - Parameters:
    ///   - activePickIDs: Currently active Flezcal pill IDs
    ///   - existingSpotNames: Lowercased names of confirmed spots (for dedup)
    ///   - showLikely: Whether "Likely" (green) pins are toggled on
    ///   - showUnchecked: Whether "Unchecked" (yellow) pins are toggled on
    ///   - showCommunityMap: Community map mode hides all ghost pins
    func visiblePins(activePickIDs: Set<String>,
                     existingSpotNames: Set<String>,
                     showLikely: Bool,
                     showUnchecked: Bool,
                     showCommunityMap: Bool = false) -> [SuggestedSpot] {
        guard !showCommunityMap else { return [] }
        guard !activePickIDs.isEmpty else { return [] }
        let filtered = filteredSuggestions(existingSpotNames: existingSpotNames)
        return filtered.filter { suggestion in
            let isGreen = suggestion.preScreenMatches?.isEmpty == false
            // Category filter: green pins match if pre-screen found any active category;
            // yellow/unchecked pins match if their originating search category is active.
            let matchesCategory: Bool
            if isGreen, let matches = suggestion.preScreenMatches {
                matchesCategory = !matches.isDisjoint(with: activePickIDs)
            } else {
                matchesCategory = activePickIDs.contains(suggestion.suggestedCategory.id)
            }
            guard matchesCategory else { return false }
            return isGreen ? showLikely : showUnchecked
        }
    }

    /// Results split into matched (pre-screen confirmed) and unmatched.
    /// Replaces ExplorePanel.splitResults and the possibleSuggestions/uncheckedSuggestions
    /// computed properties on MapTabView.
    struct SplitResults {
        let matched: [SuggestedSpot]    // green — preScreenMatches overlaps activePickIDs
        let other: [SuggestedSpot]      // yellow/gray — not matched or not yet scanned
    }

    /// Splits suggestions by pre-screen match status.
    ///
    /// - Parameters:
    ///   - activePickIDs: Currently active Flezcal pill IDs
    ///   - existingSpotNames: Lowercased names of confirmed spots (for dedup)
    ///   - nameFilter: Optional client-side venue name filter (Spots tab search text)
    func splitByPreScreen(activePickIDs: Set<String>,
                          existingSpotNames: Set<String>,
                          nameFilter: String = "") -> SplitResults {
        let filtered = filteredSuggestions(existingSpotNames: existingSpotNames)
        let trimmedNameFilter = nameFilter.trimmingCharacters(in: .whitespaces).lowercased()

        var matched: [SuggestedSpot] = []
        var other: [SuggestedSpot] = []

        for spot in filtered {
            // Client-side venue name filter — searchText narrows visible results
            if !trimmedNameFilter.isEmpty && !spot.name.lowercased().contains(trimmedNameFilter) {
                continue
            }
            if let matches = spot.preScreenMatches, !matches.isEmpty,
               !matches.isDisjoint(with: activePickIDs) {
                matched.append(spot)
            } else {
                other.append(spot)
            }
        }
        return SplitResults(matched: matched, other: other)
    }
}
