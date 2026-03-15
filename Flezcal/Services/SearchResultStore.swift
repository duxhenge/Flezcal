import Foundation
@preconcurrency import MapKit
import CoreLocation
import os

private let searchLog = Logger(subsystem: "com.flezcal.app", category: "SearchResultStore")

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
    /// True while the homepage pre-screen scan is running (Wave 1 or Wave 2).
    @Published var isPreScreening = false
    /// Status banner shown after Wave 1 completes: "X possible Flezcal spots"
    /// or "No quick matches." Auto-dismissed after 8 seconds.
    @Published var preScreenBannerMessage: String? = nil
    /// True when Wave 2 pool exists and user can tap "Search Wider Area?"
    @Published var showDeeperScanButton = false

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

    /// Chain venues that are almost never relevant for specialty food searches.
    /// Filtered out unless the venue name also contains a pick keyword.
    private static let chainExclusions: Set<String> = [
        "dunkin", "starbucks", "mcdonald's", "burger king", "wendy's",
        "taco bell", "subway", "chick-fil-a", "popeyes", "five guys",
    ]

    /// Returns true if `nameLower` contains any pick's websiteKeyword (word-boundary match).
    /// Used as an escape hatch so relevant chains/cafes aren't over-filtered.
    private static func venueNameMatchesAnyPick(_ nameLower: String, picks: [FoodCategory]) -> Bool {
        for pick in picks {
            for keyword in pick.websiteKeywords where keyword.count >= 3 {
                let escaped = NSRegularExpression.escapedPattern(for: keyword.lowercased())
                if nameLower.range(of: "\\b\(escaped)\\b", options: .regularExpression) != nil {
                    return true
                }
            }
        }
        return false
    }

    // ── Task management (private — views cannot cancel these) ───────────

    /// The current fetch + Wave 1 pre-screen task. Only replaced by a new
    /// fetchAndPreScreen call or cancelled by explicit cancelInFlight().
    private var fetchTask: Task<Void, Never>?
    /// The current pre-screen scanning task (Wave 1 or Wave 2).
    private var preScreenTask: Task<Void, Never>?
    /// Auto-dismiss task for the banner message.
    private var bannerDismissTask: Task<Void, Never>?
    /// Wave 2 pool — remaining venues beyond the closest 25.
    private var deeperScanPool: [SuggestedSpot] = []
    /// Picks used for the current Wave 2 scan.
    private var deeperScanPicks: [FoodCategory] = []
    /// Wave 1 pre-screen results — merged with Wave 2 when user initiates deeper scan.
    private var wave1Results: [String: Set<String>] = [:]
    /// IDs from the initial `fetchSuggestions` closest-25 — set once per fetch,
    /// never mutated by `applyPreScreenResults`. This ensures the "original 25"
    /// identity is stable across cached pre-screen → Wave 1 → Wave 2 passes.
    private var originalSuggestionIDs: Set<String> = []
    /// Pick IDs from the last completed or in-flight fetchAndPreScreen call.
    /// Combined with `lastFetchCenter` to detect redundant fetch requests.
    private var lastFetchPickIDs: Set<String> = []

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

        // Existing confirmed spot names whose categories OVERLAP with current picks.
        // Only these are filtered out — spots with non-overlapping categories stay in
        // the pool as ghost pins, so users can discover new categories at known venues.
        // Exclude hidden spots so ghost pins reappear when user removes all categories.
        let pickIDs = Set(picks.map(\.id))
        let existingNames = Set(
            existingSpots
                .filter { spot in
                    !spot.isHidden &&
                    spot.categories.contains { cat in pickIDs.contains(cat.rawValue) }
                }
                .map { $0.name.lowercased() }
        )

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
            // Bidirectional substring match — aligns with SpotService.findExistingSpot()
            // which uses localizedCaseInsensitiveContains. Either name containing the
            // other catches "The Winsor House" vs "Winsor House" and similar variants.
            if existingNames.contains(where: { existing in
                key.contains(existing) || existing.contains(key)
            }) {
                #if DEBUG
                print("[SearchResultStore] Skipped \"\(name)\" — already a confirmed spot for active picks")
                #endif
                continue
            }
            if !seenNames.insert(key).inserted { continue }
            let category = picksByID[result.tag] ?? picks[0]
            pool.append(SuggestedSpot(mapItem: result.item, suggestedCategory: category))
        }

        // ── Irrelevant venue filter ────────────────────────────────────
        // Remove obviously wrong venues that Apple Maps returns due to
        // broad POI matching (e.g. Dunkin Donuts for "lobster rolls").
        // Conservative: keeps any venue whose name matches a pick keyword.
        let cafeNaturalPickIDs: Set<String> = [
            "tea", "coffee", "pastry", "matcha", "bubble_tea",
        ]
        let anyCafePick = !pickIDs.isDisjoint(with: cafeNaturalPickIDs)

        pool = pool.filter { suggestion in
            let nameLower = suggestion.name.lowercased()

            // 1. POI category filter: remove .cafe venues unless a pick is
            //    cafe-related or the venue name contains a pick keyword.
            if !anyCafePick,
               suggestion.mapItem.pointOfInterestCategory == .cafe {
                if Self.venueNameMatchesAnyPick(nameLower, picks: picks) { return true }
                #if DEBUG
                print("[SearchResultStore] Filtered café \"\(suggestion.name)\" — no pick keyword in name")
                #endif
                return false
            }

            // 2. Chain name filter: remove known chains unless venue name
            //    contains a pick keyword (e.g. a chain that added your pick).
            if Self.chainExclusions.contains(where: { nameLower.contains($0) }) {
                if Self.venueNameMatchesAnyPick(nameLower, picks: picks) { return true }
                #if DEBUG
                print("[SearchResultStore] Filtered chain \"\(suggestion.name)\" — no pick keyword in name")
                #endif
                return false
            }

            return true
        }

        // Name-match pass: if a venue's name contains any of a pick's keywords
        // (word-boundary match), mark it green immediately — no website scan needed.
        // Checks displayName + websiteKeywords so variant spellings like "Pierogies"
        // or "Pierogy" are caught, not just the canonical displayName.
        // Does NOT check mapSearchTerms — those are broad MKLocalSearch queries
        // (e.g. "polish restaurant") that would false-positive on any "restaurant" name.
        // e.g. "Kung Fu Tea" contains \btea\b → green for Tea category.
        pool = pool.map { suggestion in
            var updated = suggestion
            let venueName = suggestion.name.lowercased()
            var nameMatchedCategories = Set<String>()
            for pick in picks {
                let terms = Set(
                    ([pick.displayName] + pick.websiteKeywords)
                        .map { $0.lowercased() }
                ).filter { $0.count >= 3 }
                for term in terms {
                    let escaped = NSRegularExpression.escapedPattern(for: term)
                    if let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: .caseInsensitive),
                       regex.firstMatch(in: venueName, range: NSRange(venueName.startIndex..., in: venueName)) != nil {
                        nameMatchedCategories.insert(pick.id)
                        break // One match per pick is enough
                    }
                }
            }
            if !nameMatchedCategories.isEmpty {
                updated.preScreenMatches = nameMatchedCategories
            }
            return updated
        }

        // Remove dismissed venues from the pool
        let validPool = pool.filter { !dismissedIDs.contains($0.id) }
        let found = Array(validPool.prefix(Self.maxDisplayPins))

        #if DEBUG
        print("[SearchResultStore] Pool: \(pool.count) unique venues → closest \(found.count) kept (full pool: \(validPool.count))")
        // Distance distribution: show distance for each of the first 25 + a few beyond
        let debugCenter = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let debugLimit = min(30, validPool.count)
        for i in 0..<debugLimit {
            let s = validPool[i]
            let dist = CLLocation(latitude: s.coordinate.latitude, longitude: s.coordinate.longitude).distance(from: debugCenter)
            let isGreen = s.preScreenMatches?.isEmpty == false
            let marker = i < Self.maxDisplayPins ? "W1" : "W2"
            print("[SearchResultStore]   [\(marker)] #\(i+1) \(s.name) — \(String(format: "%.1f", dist / 1000))km \(isGreen ? "🟢" : "🟡")")
        }
        if validPool.count > debugLimit {
            let lastS = validPool[validPool.count - 1]
            let lastDist = CLLocation(latitude: lastS.coordinate.latitude, longitude: lastS.coordinate.longitude).distance(from: debugCenter)
            print("[SearchResultStore]   ... #\(validPool.count) \(lastS.name) — \(String(format: "%.1f", lastDist / 1000))km")
        }
        #endif

        // A newer fetch started while we were running — discard our results entirely.
        guard fetchGeneration == myGeneration else { isLoading = false; return }

        // Replace suggestions when results are non-empty.
        if !found.isEmpty {
            suggestions = found
            fullPool = validPool
            lastFetchCenter = regionCenter
            // Lock in the "original 25" identity — stable across all
            // applyPreScreenResults passes (cached, Wave 1, Wave 2).
            originalSuggestionIDs = Set(found.map(\.id))
        }
        isLoading = false
    }

    // MARK: - Inject cross-tab results

    /// Injects pre-built results from another tab (e.g. Spots → Map).
    /// Replaces any existing suggestions and marks pre-screen complete
    /// since the data already has `preScreenMatches` baked in.
    /// Deduplicates by venue name (lowercased) to prevent overlapping pins.
    /// Preserves Wave 2 greens: the closest 25 are the "originals", plus all
    /// green pins from beyond the 25 (same logic as applyPreScreenResults).
    func injectResults(_ results: [SuggestedSpot]) {
        var seenIDs = Set<String>()
        let unique = results.filter { seenIDs.insert($0.id).inserted }
        let originals = Array(unique.prefix(Self.maxDisplayPins))
        let originalIDs = Set(originals.map(\.id))
        // Keep green pins from beyond the original 25 (Wave 2 promotions)
        let extraGreens = Array(unique.dropFirst(Self.maxDisplayPins).filter {
            $0.preScreenMatches?.isEmpty == false
        })
        let displayed = originals + extraGreens
        searchLog.info("injectResults: \(unique.count) unique → \(originals.count) originals + \(extraGreens.count) extra greens = \(displayed.count) displayed")
        suggestions = displayed
        fullPool = unique
        originalSuggestionIDs = originalIDs
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
    /// - Parameters:
    ///   - results: Pre-screen results dict (venue ID → matched category IDs)
    ///   - markComplete: Whether to set `preScreenComplete = true`
    ///   - promotePoolGreens: Whether to add new greens from the wider pool beyond
    ///     the original 25. `false` for cached pre-screen and Wave 1 (keep exactly 25),
    ///     `true` for Wave 2 (add discovered greens on top of the original 25).
    func applyPreScreenResults(_ results: [String: Set<String>],
                               markComplete: Bool = true,
                               promotePoolGreens: Bool = false) {
        // Apply pre-screen results to the full pool first.
        // Merge with existing matches (e.g. name-match) rather than replacing,
        // so a venue that was green from its name stays green even if the
        // website scan finds nothing.
        let updatedPool = fullPool.map { suggestion in
            var updated = suggestion
            if let matched = results[suggestion.id] {
                if let existing = updated.preScreenMatches, !existing.isEmpty {
                    // Merge: keep name-match results, add website-match results
                    updated.preScreenMatches = existing.union(matched)
                } else {
                    updated.preScreenMatches = matched
                }
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

        // Wave 1 (promotePoolGreens=false): exactly maxDisplayPins (25) total.
        // The original 25 get updated with pre-screen data (some turn green,
        // rest stay yellow). No new pins are added from the wider pool.
        //
        // Wave 2 (promotePoolGreens=true): ADDS green pins from the wider pool
        // on top of the original 25. Yellows from the original 25 stay.
        //
        // CRITICAL: `originalSuggestionIDs` (stable, set once per fetch) tracks
        // the original 25. Without this, each pass inflates the set.

        // Update the original 25 with pre-screen results, preserving distance order.
        let updatedOriginals = updatedPool.filter { originalSuggestionIDs.contains($0.id) }

        // New green pins from wider pool (only included when promotePoolGreens=true)
        let newGreens: [SuggestedSpot]
        if promotePoolGreens {
            newGreens = updatedPool
                .filter { $0.preScreenMatches?.isEmpty == false && !originalSuggestionIDs.contains($0.id) }
                .sorted { distance($0) < distance($1) }
        } else {
            newGreens = []
        }

        let trimmed = updatedOriginals + newGreens

        let originalGreen = updatedOriginals.filter { $0.preScreenMatches?.isEmpty == false }.count
        let originalYellow = updatedOriginals.count - originalGreen
        searchLog.info("Original 25: \(originalGreen) green + \(originalYellow) yellow. New greens: \(newGreens.count). Total: \(trimmed.count) [promote=\(promotePoolGreens)]")
        #if DEBUG
        print("[SearchResultStore] Applying \(results.count) pre-screen results to pool of \(fullPool.count) [promote=\(promotePoolGreens)]")
        print("[SearchResultStore] Original 25: \(originalGreen) green + \(originalYellow) yellow. New greens from pool: \(newGreens.count). Total: \(trimmed.count)")
        for s in newGreens {
            print("[SearchResultStore]   NEW GREEN: \(s.name) → \(s.preScreenMatches!) dist=\(Int(distance(s)))m")
        }
        #endif

        // Update fullPool with pre-screen data so subsequent reads see it
        fullPool = updatedPool
        suggestions = trimmed
        if markComplete {
            preScreenComplete = true
        }
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

    /// Updates preScreenMatches for a specific suggestion after a website check.
    /// Used when tapping an existing-spot ghost pin triggers checkAllPicks —
    /// if the check confirms categories, the ghost pin turns green on the map.
    func updatePreScreenMatches(for id: String, matches: Set<String>) {
        suggestions = suggestions.map { suggestion in
            guard suggestion.id == id else { return suggestion }
            var updated = suggestion
            let existing = updated.preScreenMatches ?? Set()
            updated.preScreenMatches = existing.union(matches)
            return updated
        }
        fullPool = fullPool.map { suggestion in
            guard suggestion.id == id else { return suggestion }
            var updated = suggestion
            let existing = updated.preScreenMatches ?? Set()
            updated.preScreenMatches = existing.union(matches)
            return updated
        }
    }

    // MARK: - Restore Ghost Pin

    /// Re-injects a venue as a yellow ghost pin after the user removed all
    /// categories. Uses MKLocalSearch to find the venue's MKMapItem so the
    /// ghost pin has full Apple Maps metadata (URL, phone, etc.).
    func restoreGhostPin(name: String, coordinate: CLLocationCoordinate2D,
                         suggestedCategory: FoodCategory) {
        // Remove from dismissedIDs so it's not filtered out
        dismissedIDs.remove(name.lowercased())

        // Quick MKLocalSearch to get the MKMapItem back
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = name
            request.region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )

            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first(where: {
                   ($0.name ?? "").lowercased() == name.lowercased()
               }) ?? response.mapItems.first {
                let ghost = SuggestedSpot(mapItem: item,
                                           suggestedCategory: suggestedCategory)
                // Insert at the front so it's visible immediately
                if !suggestions.contains(where: { $0.id == ghost.id }) {
                    suggestions.insert(ghost, at: 0)
                }
            }
        }
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
        let other: [SuggestedSpot]      // yellow — unconfirmed or not yet scanned
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

    // MARK: - Fetch + Pre-Screen (owned by the store)

    /// Set to `true` when a fetchAndPreScreen requested zoom-to-fit, then
    /// flipped back to `false` after the map zooms. MapTabView observes both
    /// `preScreenComplete` and `pendingZoomToFit` to trigger the zoom.
    @Published var pendingZoomToFit = false

    /// Fetches ghost pin suggestions then kicks off the batch homepage pre-screen.
    /// Both tabs call this — the store manages its own tasks internally.
    /// Views cannot cancel these tasks; only `cancelInFlight()` can.
    ///
    /// ## SEARCH STABILITY CONTRACT — PROTECTED
    /// No search may run without explicit user action. The three allowed triggers:
    /// 1. **Boot** — one auto-fetch at user location (MapTabView, bootFetchesRemaining)
    /// 2. **"Search This Area" button** — user taps explicitly
    /// 3. **Custom location set** — user typed a location or used Concierge (first time only)
    ///
    /// Tab switches, camera settles, pill toggles, and `.task(id:)` re-fires
    /// must NEVER trigger a new search. If you add a new call site, you must
    /// prove it only fires from direct user input.
    func fetchAndPreScreen(
        in region: MKCoordinateRegion,
        picks: [FoodCategory],
        existingSpots: [Spot],
        radius: Double = 0.5,
        websiteChecker: WebsiteCheckService,
        extraSuggestions: [SuggestedSpot] = [],
        zoomToFit: Bool = false
    ) {
        // ── Redundant-fetch guard ──────────────────────────────────────
        // If we already have results (or an in-flight fetch) for the same
        // picks and nearby center, skip. This prevents boot re-fires and
        // programmatic camera settles from destroying completed results.
        let incomingPickIDs = Set(picks.map(\.id))
        let hasResultsOrInFlight = !suggestions.isEmpty || fetchTask != nil
        if hasResultsOrInFlight,
           incomingPickIDs == lastFetchPickIDs,
           let prev = lastFetchCenter {
            let incoming = CLLocation(latitude: region.center.latitude,
                                      longitude: region.center.longitude)
            // < 500m = same search area
            if prev.distance(from: incoming) < 500 {
                searchLog.info("Skipping redundant fetch — same picks + center (\(String(format: "%.0f", prev.distance(from: incoming)))m)")
                #if DEBUG
                print("[SearchResultStore] Skipping redundant fetch — same picks + center (distance \(String(format: "%.0f", prev.distance(from: incoming)))m)")
                #endif
                // Honor zoom request even though we're skipping the fetch —
                // the data is already here, so signal the map to zoom.
                if zoomToFit, !suggestions.isEmpty {
                    pendingZoomToFit = true
                }
                return
            }
        }

        // ── Diagnostic: which guard condition failed? ────────────────────
        let guardIncoming = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let guardDist = lastFetchCenter.map { guardIncoming.distance(from: $0) } ?? -1
        searchLog.info("NEW FETCH starting — hasResults=\(hasResultsOrInFlight) picksMatch=\(incomingPickIDs == self.lastFetchPickIDs) hasCenter=\(self.lastFetchCenter != nil) dist=\(String(format: "%.0f", guardDist))m suggestions=\(self.suggestions.count) lastPickIDs=\(self.lastFetchPickIDs.sorted()) incomingPickIDs=\(incomingPickIDs.sorted())")
        // Cancel any in-flight fetch + pre-screen so a new call doesn't
        // race with the previous one and overwrite green pin results.
        fetchTask?.cancel()
        preScreenTask?.cancel()
        bannerDismissTask?.cancel()
        showDeeperScanButton = false
        deeperScanPool = []
        preScreenBannerMessage = nil
        preScreenComplete = false  // Reset before setting pendingZoomToFit to prevent
                                   // the .onChange(of: pendingZoomToFit) observer from
                                   // firing zoomToFitPins() with stale suggestions.
        pendingZoomToFit = zoomToFit
        lastFetchPickIDs = incomingPickIDs
        lastFetchCenter = CLLocation(latitude: region.center.latitude,
                                      longitude: region.center.longitude)

        fetchTask = Task {
            #if DEBUG
            print("[SearchResultStore] fetchAndPreScreen called with \(picks.count) picks, radius \(radius)")
            #endif
            await fetchSuggestions(
                in: region,
                existingSpots: existingSpots,
                picks: picks,
                radius: radius
            )
            guard !Task.isCancelled else {
                isPreScreening = false
                return
            }

            // Instant pass: apply any cached pre-screen results immediately.
            let pool = fullPool
            let cachedResults = await websiteChecker.cachedPreScreen(
                suggestions: pool,
                picks: picks
            )
            if !cachedResults.isEmpty {
                // markComplete: false — this is a preview pass from cache.
                // Don't set preScreenComplete yet; Wave 1 will set it when
                // the full scan finishes. Setting it here would consume
                // pendingZoomToFit before the real results are ready.
                applyPreScreenResults(cachedResults, markComplete: false)
                #if DEBUG
                let greenCount = cachedResults.values.filter { !$0.isEmpty }.count
                print("[SearchResultStore] Instant cache hit: \(greenCount) green out of \(cachedResults.count) cached")
                #endif
            }

            // Kick off Wave 1: scan the closest 25 venues (the displayed set)
            // so green pins appear fast. Wave 2 (remaining pool) is deferred
            // until the user taps "Search Wider Area?"
            // (preScreenComplete already reset synchronously in fetchAndPreScreen)
            preScreenBannerMessage = nil
            isPreScreening = true
            var poolToScan = fullPool
            for extra in extraSuggestions {
                if !poolToScan.contains(where: { $0.id == extra.id }) {
                    poolToScan.append(extra)
                }
            }

            preScreenTask = Task {
                let wave1Count = min(25, poolToScan.count)
                let wave1 = Array(poolToScan.prefix(wave1Count))
                let wave2 = Array(poolToScan.dropFirst(wave1Count))

                // ── Wave 1: closest venues (fast results) ──
                let w1Results = await websiteChecker.batchPreScreen(
                    suggestions: wave1,
                    picks: picks
                )
                guard !Task.isCancelled else {
                    isPreScreening = false
                    return
                }
                applyPreScreenResults(w1Results)
                #if DEBUG
                let w1Green = w1Results.values.filter { !$0.isEmpty }.count
                print("[SearchResultStore] Wave 1 done: \(w1Green) green out of \(wave1.count) closest venues")
                #endif

                isPreScreening = false

                // Show Wave 1 result banner
                let likelyCount = suggestions.filter {
                    $0.preScreenMatches?.isEmpty == false
                }.count
                let totalCount = suggestions.count
                searchLog.info("Wave 1 complete. \(likelyCount) likely out of \(totalCount) total. \(wave2.count) deferred.")
                #if DEBUG
                print("[SearchResultStore] Wave 1 complete. \(likelyCount) likely out of \(totalCount) suggestions. \(wave2.count) venues deferred.")
                #endif
                if totalCount > 0 {
                    if likelyCount == 0 {
                        preScreenBannerMessage = "No quick matches. Tap any pin to search deeper."
                    } else {
                        preScreenBannerMessage = "\(likelyCount) possible \(AppBranding.name) spot\(likelyCount == 1 ? "" : "s"). Tap green pins to review."
                    }
                    bannerDismissTask = Task {
                        try? await Task.sleep(for: .seconds(8))
                        guard !Task.isCancelled else { return }
                        preScreenBannerMessage = nil
                    }
                }

                // Store Wave 2 pool for the "Search Wider Area?" button.
                if !wave2.isEmpty {
                    wave1Results = w1Results
                    deeperScanPool = wave2
                    deeperScanPicks = picks
                    showDeeperScanButton = true
                }
            }
        }
    }

    /// Wave 2: runs only when the user taps "Scan More Spots?".
    /// Scans the remaining pool beyond the closest 25 and promotes
    /// any green matches into the displayed set.
    func runDeeperScan(websiteChecker: WebsiteCheckService) {
        showDeeperScanButton = false
        preScreenTask?.cancel()
        bannerDismissTask?.cancel()
        preScreenBannerMessage = nil
        isPreScreening = true
        // Reset preScreenComplete so it transitions false→true when Wave 2
        // finishes, triggering the .onChange observer in MapTabView.
        preScreenComplete = false
        // Zoom to fit after Wave 2 so the map expands to show new green pins
        // from the wider pool. Without this, Wave 2 greens are outside the
        // viewport and the map appears to revert to Wave 1 on tab switch.
        pendingZoomToFit = true

        let pool = deeperScanPool
        let picks = deeperScanPicks
        let w1 = wave1Results

        preScreenTask = Task {
            let w2Results = await websiteChecker.batchPreScreen(
                suggestions: pool,
                picks: picks
            )
            guard !Task.isCancelled else {
                isPreScreening = false
                return
            }
            // Merge Wave 2 into Wave 1 results and re-apply for promotion.
            var allResults = w1
            for (key, value) in w2Results {
                allResults[key] = value
            }
            applyPreScreenResults(allResults, promotePoolGreens: true)
            #if DEBUG
            let w2Green = w2Results.values.filter { !$0.isEmpty }.count
            print("[SearchResultStore] Wave 2 done: \(w2Green) green out of \(pool.count) remaining venues")
            #endif

            isPreScreening = false
            deeperScanPool = []

            // Show final result banner
            let likelyCount = suggestions.filter {
                $0.preScreenMatches?.isEmpty == false
            }.count
            let totalCount = suggestions.count
            searchLog.info("Wave 2 complete. \(likelyCount) likely out of \(totalCount) total.")
            #if DEBUG
            print("[SearchResultStore] Deeper scan complete. \(likelyCount) likely out of \(totalCount) suggestions.")
            #endif
            if totalCount > 0 {
                if likelyCount == 0 {
                    preScreenBannerMessage = "No quick matches. Tap any pin to search deeper."
                } else {
                    preScreenBannerMessage = "\(likelyCount) possible \(AppBranding.name) spot\(likelyCount == 1 ? "" : "s"). Tap green pins to review."
                }
                bannerDismissTask = Task {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    preScreenBannerMessage = nil
                }
            }
        }
    }

    /// Cancel in-flight fetch + pre-screen tasks.
    /// Only call this for explicit user actions (e.g. "Search This Area" button tap).
    /// Camera events, tab switches, and programmatic moves should NEVER call this.
    ///
    /// **IMPORTANT:** Does NOT clear `lastFetchPickIDs` or `lastFetchCenter`.
    /// Those protect the redundant-fetch guard. Clearing them here previously
    /// caused phantom re-searches on tab switch. The next `fetchAndPreScreen`
    /// call overwrites them with new values anyway.
    func cancelInFlight() {
        fetchTask?.cancel()
        preScreenTask?.cancel()
        bannerDismissTask?.cancel()
        isPreScreening = false
        showDeeperScanButton = false
        preScreenBannerMessage = nil
        // Keep lastFetchPickIDs and lastFetchCenter intact — they protect
        // the redundant-fetch guard. The next fetchAndPreScreen call will
        // overwrite them with the new values anyway.
        originalSuggestionIDs = []
    }
}
