import SwiftUI
@preconcurrency import MapKit
import CoreLocation

// MARK: - Custom search location (Explore mode)

/// Holds a geocoded city name + coordinate so the user can search remote cities.
struct CustomSearchLocation: Equatable {
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Combined task identity for `.task(id:)` — re-fires search when either
/// the query text OR the custom location changes.
private struct SearchTaskID: Equatable, Hashable {
    let query: String
    let activeFilterIDs: Set<String>   // IDs of active pick pills — triggers re-search on toggle
    let customLocation: CustomSearchLocation?
    let mapTermsVersion: Int        // Incremented when user edits mapSearchTerms — triggers re-search
    let searchRadius: Double        // Triggers re-search when user changes search distance
    let refreshVersion: Int         // Incremented by manual refresh — triggers re-search

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query && lhs.activeFilterIDs == rhs.activeFilterIDs
        && lhs.customLocation == rhs.customLocation
        && lhs.mapTermsVersion == rhs.mapTermsVersion
        && lhs.searchRadius == rhs.searchRadius
        && lhs.refreshVersion == rhs.refreshVersion
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(activeFilterIDs)
        hasher.combine(customLocation?.name)
        hasher.combine(customLocation?.coordinate.latitude)
        hasher.combine(customLocation?.coordinate.longitude)
        hasher.combine(mapTermsVersion)
        hasher.combine(searchRadius)
        hasher.combine(refreshVersion)
    }
}

// MARK: - Unified List Item

/// Wrapper for the unified top section — verified community spots and green-matched
/// potential spots interleaved by distance.
private enum UnifiedListItem: Identifiable {
    case verified(Spot)
    case potentialMatched(MKMapItem)

    var id: String {
        switch self {
        case .verified(let spot):
            return "v_\(spot.id)"
        case .potentialMatched(let mapItem):
            return "p_\(mapItem.name?.lowercased() ?? UUID().uuidString)"
        }
    }

    /// Distance in meters from a reference coordinate, for sorting.
    func distanceMeters(from location: CLLocationCoordinate2D?) -> Double {
        guard let loc = location else { return .greatestFiniteMagnitude }
        let ref = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        switch self {
        case .verified(let spot):
            return ref.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
        case .potentialMatched(let mapItem):
            let coord = mapItem.placemark.coordinate
            return ref.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        }
    }
}

// MARK: - Community Spot Row

struct ListTabRowView: View {
    let spot: Spot
    let userLocation: CLLocationCoordinate2D?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SpotIcons(categories: spot.categories, size: 28)
                .frame(width: 44, height: 44)
                .background(spot.primaryCategory.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Spot name (full width)
                Text(spot.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Row 2: Address + distance
                HStack(spacing: 6) {
                    if spot.isClosed {
                        Text("Closed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    } else if spot.closureReportCount > 0 {
                        Text("Reported")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                    Text(shortAddress(from: spot.address))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(formattedDistanceMiles(from: userLocation, to: spot.coordinate) ?? "—")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }

                // Row 3: Verified categories with emojis + names, or "Website mentions"
                if !spot.isClosed {
                    categoryDisplayRow
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spot.name), \(shortAddress(from: spot.address))\(spot.isClosed ? ", Closed" : "")\(spot.categories.map { ", \($0.displayName)" }.joined())")
    }

    @ViewBuilder
    private var categoryDisplayRow: some View {
        let verified = spot.categories.filter { spot.isVerified(for: $0) }
        let potential = spot.categories.filter {
            !spot.isVerified(for: $0) && spot.verificationStatus(for: $0) == .potential
        }

        if !verified.isEmpty {
            // Show verified category emojis + names
            FlowLayout(spacing: 6) {
                ForEach(verified) { cat in
                    HStack(spacing: 2) {
                        CategoryIcon(category: cat, size: 15)
                        Text(cat.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
            }
        } else if !potential.isEmpty {
            // No verified categories but website detected some
            HStack(spacing: 4) {
                Text("Website mentions:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
                ForEach(potential.prefix(3)) { cat in
                    HStack(spacing: 2) {
                        CategoryIcon(category: cat, size: 15)
                        Text(cat.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        } else if spot.isCommunityVerified || spot.hasAnyVerificationVotes {
            // Has some votes but nothing at confirmed threshold yet — show categories
            FlowLayout(spacing: 6) {
                ForEach(spot.categories) { cat in
                    HStack(spacing: 2) {
                        CategoryIcon(category: cat, size: 15)
                        Text(cat.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }
}

// MARK: - Explore Result Row

/// A single Apple Maps result shown in Explore mode.
struct ExploreResultRowView: View {
    let mapItem: MKMapItem
    let userLocation: CLLocationCoordinate2D?
    /// True when the venue's homepage matched category keywords in the pre-screen.
    var isMatched: Bool = false

    private var subtitle: String {
        mapItem.placemark.formattedAddress ?? mapItem.placemark.locality ?? ""
    }

    private var categoryLabel: String {
        mapItem.pointOfInterestCategory.map { poiCategoryName($0) } ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            // Venue icon — green checkmark overlay when pre-screen matched
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: venueIcon(for: mapItem.pointOfInterestCategory))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isMatched ? .green : .secondary)
                    .frame(width: 44, height: 44)
                    .background(isMatched ? Color.green.opacity(0.12) : Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if isMatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white).padding(1))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(mapItem.name ?? "Unknown")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !categoryLabel.isEmpty {
                    Text(categoryLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text(formattedDistanceMiles(from: userLocation, to: mapItem))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mapItem.name ?? "Unknown venue")\(isMatched ? ", likely match" : ""), \(formattedDistanceMiles(from: userLocation, to: mapItem))")
    }

    /// Maps a POI category to a suitable SF Symbol name.
    private func venueIcon(for category: MKPointOfInterestCategory?) -> String {
        guard let category else { return "mappin" }
        switch category {
        case .restaurant:   return "fork.knife"
        case .nightlife:    return "wineglass"
        case .brewery:      return "mug"
        case .winery:       return "wineglass.fill"
        case .bakery:       return "birthday.cake"
        case .foodMarket:   return "cart"
        case .cafe:         return "cup.and.saucer"
        default:            return "mappin"
        }
    }

    /// Human-readable label for a POI category.
    private func poiCategoryName(_ category: MKPointOfInterestCategory) -> String {
        switch category {
        case .restaurant:   return "Restaurant"
        case .nightlife:    return "Bar / Nightlife"
        case .brewery:      return "Brewery"
        case .winery:       return "Winery"
        case .bakery:       return "Bakery"
        case .foodMarket:   return "Food Market"
        case .cafe:         return "Café"
        default:            return ""
        }
    }
}

// MARK: - Explore Panel
//
// ⚠️  SEARCH STABILITY CONTRACT — read before modifying this view  ⚠️
//
// ExplorePanel is intentionally a separate struct from ListTabView for two
// reasons that are BOTH required for search to work correctly:
//
// REASON 1 — SpotService isolation:
//   ListTabView observes SpotService via @EnvironmentObject. Every time spots
//   load or update, ListTabView re-renders, which would cancel any in-flight
//   .task(id: searchText) if that task lived on ListTabView. By isolating the
//   search task inside ExplorePanel (which does NOT observe SpotService),
//   spot updates cannot disrupt the search.
//
// REASON 2 — @Binding keeps @StateObject alive:
//   searchText MUST be passed as @Binding, NOT as a plain `let` value.
//   If passed as `let`, SwiftUI sees a new ExplorePanel struct on every
//   keystroke (because the value changed), destroys the old one, and creates
//   a fresh @StateObject — wiping out in-flight searches. With @Binding,
//   SwiftUI treats the panel as the same view identity across re-renders,
//   so LocationSearchService stays alive for the lifetime of Explore mode.
//
// NEVER change these without understanding both reasons above:
//   - Do NOT add @EnvironmentObject SpotService or @ObservedObject LocationManager here
//   - Do NOT change `@Binding var searchText` back to `let searchText: String`
//   - Do NOT move .task(id: searchText) back to ListTabView or NavigationStack

private struct ExplorePanel: View {
    @Binding var searchText: String       // ⚠️ Must be @Binding — see contract above
    /// The picks currently active in the filter bar (multi-toggle).
    /// Empty = all pills off (no search). All picks = search everything.
    /// One pick = search just that category's terms.
    let activeFilterPicks: [FoodCategory]
    let currentLocation: () -> CLLocationCoordinate2D?
    /// User's full picks list — plain let (stability contract). Used by checkAllPicks
    /// to check all picks against the HTML cache at zero extra API cost.
    let userPicks: [FoodCategory]
    /// Shared custom location — owned by ListTabView, passed as @Binding so
    /// ExplorePanel's .task(id:) re-fires when location changes.
    @Binding var customLocation: CustomSearchLocation?
    /// Looks up an existing Spot in Firestore by name + coordinate.
    /// Plain closure (not @EnvironmentObject) to respect the stability contract.
    let findExistingSpot: (_ name: String, _ lat: Double, _ lon: Double) -> Spot?
    /// Called when a search result matches an existing spot — parent opens SpotDetailView.
    let onSelectExistingSpot: (Spot) -> Void
    /// Incremented when user edits mapSearchTerms — triggers re-search via SearchTaskID.
    let mapTermsVersion: Int
    /// User's chosen search radius in degrees — triggers re-search via SearchTaskID.
    let searchRadiusDegrees: Double
    /// Incremented by the parent to trigger a manual re-search.
    let refreshVersion: Int
    /// Green-matched map items exposed to the parent for the unified top section.
    /// Updated after Wave 1/2 pre-screen completes.
    @Binding var matchedMapItems: [MKMapItem]
    /// Number of unmatched (yellow) results — exposed to the parent for the
    /// Unchecked filter pill count. Updated alongside matchedMapItems.
    @Binding var uncheckedCount: Int
    /// Whether unchecked (yellow) rows should be visible — controlled by the
    /// parent's Unchecked toggle pill. Search still runs (for counts) but rows hide.
    let showUnchecked: Bool
    /// Whether the "Search Wider Area?" button should show — exposed to parent
    /// so it can float over the ScrollView instead of scrolling with content.
    @Binding var showDeeperScanPrompt: Bool
    /// Set to true by the parent when user taps "Search Wider Area?".
    /// ExplorePanel watches this and runs the deeper scan.
    @Binding var triggerDeeperScan: Bool
    /// Whether the search engine or pre-screen is actively working.
    /// Exposed to parent so it can show a spinner in the header.
    @Binding var isSearchActive: Bool
    @StateObject private var searchService = LocationSearchService()

    // Sheet state lives here so changes never re-render ListTabView
    @State private var selectedSuggestion: SuggestedSpot? = nil
    @State private var multiCheckResult: MultiCategoryCheckResult? = nil
    @State private var websiteCheckTask: Task<Void, Never>? = nil
    let websiteChecker: WebsiteCheckService

    /// Indices of search results whose homepage matched category keywords.
    /// nil = pre-screen not yet run. Empty = ran, no matches.
    /// Used to re-rank: matched venues sort to the top of the list.
    @State private var preScreenMatchedIndices: Set<Int>? = nil

    /// True while the batch pre-screen is actively scanning homepages.
    /// Used to show a scanning indicator and an optimistic "checking menus…" message.
    @State private var isPreScreening = false

    /// Deeper scan state — Wave 2 is deferred until the user taps "Do a Deeper Scan?"
    @State private var deeperScanURLs: [(index: Int, url: URL)] = []
    @State private var deeperScanPicks: [FoodCategory] = []
    @State private var wave1MatchedIndices: Set<Int> = []
    /// Number of results that have been pre-screened. Starts at 25 (Wave 1),
    /// expands to total results after Wave 2 runs. Controls how many yellow
    /// rows are visible and what counts as "unchecked".
    @State private var preScreenedPoolSize: Int = 25

    /// The coordinate to use for searches. Custom location if set, otherwise GPS.
    private var effectiveLocation: CLLocationCoordinate2D? {
        customLocation?.coordinate ?? currentLocation()
    }

    /// Number of pre-screen matched results (confirmed via homepage scan).
    private var matchedCount: Int {
        preScreenMatchedIndices?.count ?? 0
    }

    /// Apple Maps results split into matched (pre-screen confirmed) and unmatched.
    /// Tier 1 (top): Pre-screen matched venues, sorted by distance.
    /// Tier 2 (bottom): Unmatched venues from the pre-screened pool (first 25),
    ///   sorted by distance. Results beyond 25 are hidden until Wave 2 runs.
    private var splitResults: (matched: [MKMapItem], other: [MKMapItem]) {
        let results = searchService.searchResults
        let isFilterSearch = searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let matchedIndices = preScreenMatchedIndices ?? []
        // Only show results from the pre-screened pool. Starts at 25 (Wave 1),
        // expands after "Search Wider Area" runs Wave 2.

        var top: [MKMapItem] = []
        var rest: [MKMapItem] = []

        for (index, item) in results.prefix(preScreenedPoolSize).enumerated() {
            if isFilterSearch && matchedIndices.contains(index) {
                top.append(item)
            } else {
                rest.append(item)
            }
        }
        return (matched: top, other: rest)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Main content ────────────────────────────────────────
            // While searching, keep previous results visible instead of
            // flashing "No results" on every keystroke.  Only show the
            // empty / no-results states once the search has settled.
            Group {
                if searchService.searchResults.isEmpty && searchService.isSearching {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if searchService.searchResults.isEmpty && !searchService.isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                        Text(searchText.isEmpty
                             ? "Try searching for a specific venue."
                             : "Try a different name or location.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No results found. Try a different search.")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Results list — stays visible while a new search is in flight
                    let isFilterSearch = searchText.trimmingCharacters(in: .whitespaces).isEmpty
                    let split = splitResults
                    let displayCount = split.matched.count + split.other.count

                    LazyVStack(spacing: 0) {
                        // ── Status banner (auto-searches only) ──
                        if isFilterSearch {
                            // When a single category is active, use its name (e.g. "mezcal").
                            // When multiple picks are active, use "Flezcal" as the noun.
                            let singleCategory = activeFilterPicks.count == 1 ? activeFilterPicks[0].displayName.lowercased() : nil
                            let isMultiSearch = singleCategory == nil

                            if isPreScreening {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(isMultiSearch
                                         ? "Checking menus for your Flezcals…"
                                         : "Checking menus for \(singleCategory!)…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            } else if preScreenMatchedIndices != nil && matchedCount == 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(isMultiSearch
                                             ? "No Flezcal matches found on menus nearby"
                                             : "No \(singleCategory!) found on menus nearby")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    Text("\(displayCount) nearby venue\(displayCount == 1 ? "" : "s") shown — tap any to run a full search or confirm in person.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Label("Web searches aren't as reliable as your own knowledge — but we'll give it our best shot!", systemImage: "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            } else if matchedCount > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.green)
                                        Text(isMultiSearch
                                             ? "\(matchedCount) possible Flezcal spot\(matchedCount == 1 ? "" : "s")"
                                             : "\(matchedCount) possible \(singleCategory!) spot\(matchedCount == 1 ? "" : "s")")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    Label("Web searches aren't as reliable as your own knowledge — but we'll give it our best shot!", systemImage: "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }

                        // ── User-typed search: plain count header ──
                        if !isFilterSearch {
                            HStack {
                                Text("\(displayCount) result\(displayCount == 1 ? "" : "s") from Apple Maps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if searchService.isSearching {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }

                        // Green-matched rows are rendered by the parent in the
                        // unified top section — only show unmatched rows here.

                        // ── Unchecked nearby results (hidden when toggle is off) ──
                        if showUnchecked {
                            if !split.other.isEmpty {
                                // Section header for yellow results
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Other Nearby")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text("\(split.other.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            }

                            ForEach(split.other, id: \.self) { mapItem in
                                exploreRow(mapItem, isMatched: false)
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        } // end VStack
        .sheet(item: $selectedSuggestion) { suggestion in
            SuggestedSpotSheet(
                suggestion: suggestion,
                multiResult: multiCheckResult,
                onConfirm: {
                    selectedSuggestion = nil
                    multiCheckResult = nil
                },
                onDismiss: {
                    selectedSuggestion = nil
                    multiCheckResult = nil
                },
                source: .exploreSearch,
                userPicks: searchScopedPicks
            )
        }
        .task(id: SearchTaskID(
            query: searchText,
            activeFilterIDs: Set(activeFilterPicks.map(\.id)),
            customLocation: customLocation,
            mapTermsVersion: mapTermsVersion,
            searchRadius: searchRadiusDegrees,
            refreshVersion: refreshVersion
        )) {
            // No active picks — clear results and stop
            guard !activeFilterPicks.isEmpty else {
                searchService.clearResults()
                preScreenMatchedIndices = nil
                isPreScreening = false
                matchedMapItems = []
                uncheckedCount = 0
                return
            }

            let userTypedText = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            #if DEBUG
            print("[Explore] .task fired — searchText='\(searchText)' activePicks=\(activeFilterPicks.map(\.displayName)) customLoc=\(customLocation?.name ?? "nil") userTyped=\(userTypedText)")
            #endif

            if userTypedText {
                // User typed a venue name — single query, debounced
                let query = searchText
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    searchService.clearResults()
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else {
                    #if DEBUG
                    print("[Explore] cancelled during debounce")
                    #endif
                    return
                }
                await searchService.search(query: query, userLocation: effectiveLocation)
            } else {
                // Filter-based auto-search — combine terms from all active picks.
                // Uses each pick's mapSearchTerms to ensure niche venues
                // (mezcal bars, flan bakeries) appear in results.
                var allTerms: [String] = []
                var seen = Set<String>()
                for pick in activeFilterPicks {
                    for term in pick.mapSearchTerms {
                        let key = term.lowercased()
                        if seen.insert(key).inserted {
                            allTerms.append(term)
                        }
                    }
                }
                if allTerms.isEmpty { allTerms = ["restaurant"] }
                await searchService.multiSearch(
                    queries: allTerms,
                    userLocation: effectiveLocation,
                    radius: searchRadiusDegrees
                )
            }

            // Pre-screen: scan homepages to re-rank results (matched venues first).
            // Only for filter-based auto-searches — user-typed queries skip re-ranking.
            guard !Task.isCancelled else {
                #if DEBUG
                print("[Explore] cancelled after search")
                #endif
                return
            }
            preScreenMatchedIndices = nil
            isPreScreening = false
            let items = searchService.searchResults
            let picks = activePicks
            #if DEBUG
            print("[Explore] pre-screen gate: items=\(items.count) userTyped=\(userTypedText) picks=\(picks.map(\.displayName))")
            #endif
            guard !items.isEmpty, !userTypedText else { return }
            isPreScreening = true
            showDeeperScanPrompt = false
            deeperScanURLs = []
            preScreenedPoolSize = 25  // Reset to Wave 1 cap for new search
            // Extract (index, url) pairs on @MainActor before crossing into the
            // WebsiteCheckService actor — MKMapItem is non-Sendable.
            let itemURLs: [(index: Int, url: URL)] = items.enumerated().compactMap { index, item in
                guard let url = item.url else { return nil }
                return (index: index, url: url)
            }

            // Wave 1: scan the first 25 results so green badges appear fast.
            // Wave 2 (remaining) is deferred until the user taps "Do a Deeper Scan?".
            let wave1Count = min(25, itemURLs.count)
            let wave1 = Array(itemURLs.prefix(wave1Count))
            let wave2 = Array(itemURLs.dropFirst(wave1Count))

            #if DEBUG
            print("[Explore] starting wave 1 pre-screen: \(wave1.count) items")
            #endif

            // ── Wave 1: top results ──
            let matched = await websiteChecker.batchPreScreenMapItems(wave1, picks: picks)
            guard !Task.isCancelled else {
                isPreScreening = false
                return
            }
            preScreenMatchedIndices = matched
            updateMatchedItems()
            #if DEBUG
            print("[Explore] wave 1 done: \(matched.count) matches out of \(wave1.count). \(wave2.count) deferred.")
            #endif

            isPreScreening = false

            // Store Wave 2 for the "Search Wider Area?" button.
            if !wave2.isEmpty {
                wave1MatchedIndices = matched
                deeperScanURLs = wave2
                deeperScanPicks = picks
                showDeeperScanPrompt = true
            }
        }
        .onChange(of: triggerDeeperScan) { _, triggered in
            if triggered {
                triggerDeeperScan = false
                runDeeperScan()
            }
        }
        .onChange(of: searchService.isSearching) { _, val in
            isSearchActive = val || isPreScreening
        }
        .onChange(of: isPreScreening) { _, val in
            isSearchActive = searchService.isSearching || val
        }
        .onDisappear {
            // Cancel any in-flight website check so it doesn't write
            // back to @State after the view is gone.
            websiteCheckTask?.cancel()
            websiteCheckTask = nil
            multiCheckResult = nil
            preScreenMatchedIndices = nil
            isPreScreening = false
            showDeeperScanPrompt = false
            matchedMapItems = []
            uncheckedCount = 0
            isSearchActive = false
        }
    }

    /// Wave 2: runs only when the user taps "Do a Deeper Scan?".
    /// Scans the remaining URLs beyond the closest 25 and merges results.
    private func runDeeperScan() {
        showDeeperScanPrompt = false
        isPreScreening = true

        let urls = deeperScanURLs
        let picks = deeperScanPicks
        let w1Matched = wave1MatchedIndices

        Task {
            let wave2Matched = await websiteChecker.batchPreScreenMapItems(urls, picks: picks)
            guard !Task.isCancelled else {
                isPreScreening = false
                return
            }
            preScreenMatchedIndices = w1Matched.union(wave2Matched)
            // Expand the visible pool to include all results now that Wave 2 is done
            preScreenedPoolSize = searchService.searchResults.count
            updateMatchedItems()
            #if DEBUG
            print("[Explore] Deeper scan done: \(wave2Matched.count) matches out of \(urls.count)")
            #endif
            isPreScreening = false
            deeperScanURLs = []
        }
    }

    /// Resolve the primary FoodCategory for a search result.
    /// Uses the first active pick, or falls back to first user pick.
    private var primaryFoodCategory: FoodCategory {
        activeFilterPicks.first ?? userPicks.first ?? FoodCategory.mezcal
    }

    /// Picks scoped to the active filter — same as activeFilterPicks.
    private var activePicks: [FoodCategory] {
        activeFilterPicks
    }

    /// Updates the parent's matchedMapItems and uncheckedCount bindings.
    /// Called after Wave 1, Wave 2, and on disappear.
    private func updateMatchedItems() {
        let results = searchService.searchResults
        let indices = preScreenMatchedIndices ?? []
        let isFilterSearch = searchText.trimmingCharacters(in: .whitespaces).isEmpty
        guard isFilterSearch else {
            matchedMapItems = []
            // For user-typed searches, cap unchecked to the pre-screened pool
            uncheckedCount = min(results.count, preScreenedPoolSize)
            return
        }
        matchedMapItems = indices.sorted().compactMap { idx in
            idx < results.count ? results[idx] : nil
        }
        // Only count results from the pre-screened pool as unchecked.
        // Results beyond this haven't been scanned yet — they appear
        // after "Search Wider Area" expands the pool.
        let poolSize = min(results.count, preScreenedPoolSize)
        uncheckedCount = poolSize - matchedMapItems.count
    }

    /// A single row in the Explore results list — venue info + green checkmark
    /// for pre-screen matches + "Show on Map" button.
    @ViewBuilder
    private func exploreRow(_ mapItem: MKMapItem, isMatched: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                selectResult(mapItem)
            } label: {
                ExploreResultRowView(
                    mapItem: mapItem,
                    userLocation: effectiveLocation,
                    isMatched: isMatched
                )
            }

            // "Show on Map" shortcut — jumps to Map tab with ghost pin
            Button {
                showOnMap(mapItem)
            } label: {
                Image(systemName: "map")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Picks to use for the current search context.
    /// When the user typed custom text, scope to just the primary category —
    /// showing "we found flan!" is confusing when they searched for "tartare".
    /// When using filter-based auto-search, include all active picks.
    private var searchScopedPicks: [FoodCategory] {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return [primaryFoodCategory]
        }
        return activePicks
    }

    private func selectResult(_ mapItem: MKMapItem) {
        // Check if this venue already exists in Firestore — if so, go straight
        // to SpotDetailView (same workflow as tapping a spot in the list).
        if let coord = mapItem.placemark.location?.coordinate,
           let name = mapItem.name,
           let existing = findExistingSpot(name, coord.latitude, coord.longitude) {
            onSelectExistingSpot(existing)
            return
        }

        // New venue — open SuggestedSpotSheet with website check
        websiteCheckTask?.cancel()
        multiCheckResult = nil
        let foodCat = primaryFoodCategory
        selectedSuggestion = SuggestedSpot(mapItem: mapItem, suggestedCategory: foodCat)
        let picks = searchScopedPicks
        websiteCheckTask = Task {
            let result = await websiteChecker.checkAllPicks(
                mapItem, picks: picks, primaryPick: foodCat
            )
            guard !Task.isCancelled else { return }
            multiCheckResult = result
        }
    }

    /// Jump to the Map tab centered on this venue with a ghost pin + website check.
    private func showOnMap(_ mapItem: MKMapItem) {
        let foodCat = primaryFoodCategory
        let suggestion = SuggestedSpot(mapItem: mapItem, suggestedCategory: foodCat)
        NotificationCenter.default.post(
            name: .showOnMap,
            object: nil,
            userInfo: ["suggestion": suggestion]
        )
    }

}

// MARK: - List Tab View

struct ListTabView: View {
    @EnvironmentObject var spotService: SpotService

    // Non-reactive location accessor. LocationManager is captured by reference;
    // reading .userLocation here never causes a re-render of this view.
    private let locationManager: LocationManager
    private let currentLocation: () -> CLLocationCoordinate2D?

    // Passed as plain let (not @EnvironmentObject) to avoid re-render on picks change.
    // Only forwarded into SpotDetailView's sheet environment so the Add Category flow works.
    let picksService: UserPicksService

    // Shared with MapTabView so htmlCache carries over between tabs.
    let websiteChecker: WebsiteCheckService

    /// Shared Flezcal filter state — synced with Map tab via ContentView.
    @Binding var activePickIDs: Set<String>

    init(locationManager: LocationManager, picksService: UserPicksService, activePickIDs: Binding<Set<String>>, websiteChecker: WebsiteCheckService) {
        self.locationManager = locationManager
        self.currentLocation = { [locationManager] in locationManager.userLocation }
        self.picksService = picksService
        self._activePickIDs = activePickIDs
        self.websiteChecker = websiteChecker
    }
    @State private var selectedSpot: Spot?
    @State private var searchText = ""
    /// Result type filters — all on by default, matching Map tab's three-way toggles.
    @State private var showVerified = true
    @State private var showPossible = true
    @State private var showUnchecked = true

    // Green-matched potential spots from ExplorePanel (for unified top section)
    @State private var matchedMapItems: [MKMapItem] = []
    // Unmatched (yellow) result count from ExplorePanel (for Unchecked filter pill)
    @State private var uncheckedCount: Int = 0
    // "Search Wider Area?" button state — driven by ExplorePanel, displayed by parent
    @State private var showDeeperScanPrompt = false
    @State private var triggerDeeperScan = false
    // Search activity state — true while searching or pre-screening
    @State private var isSearchActive = false
    // Manual refresh counter — incrementing triggers a re-search
    @State private var refreshVersion = 0

    // Potential-spot sheet state (for green rows rendered by the parent)
    @State private var selectedSuggestion: SuggestedSpot? = nil
    @State private var multiCheckResult: MultiCategoryCheckResult? = nil
    @State private var websiteCheckTask: Task<Void, Never>? = nil

    // Spot search term customization
    @State private var editingSpotSearchCategory: FoodCategory? = nil
    @State private var showSpotSearchOverview = false
    @State private var mapTermsVersion = 0

    // Custom search location — shared between Explore and Verified tabs
    @State private var customLocation: CustomSearchLocation? = nil
    @State private var isEditingLocation = false
    @State private var locationInputText = ""
    @StateObject private var locationCompleter = LocationCompleterService()
    @State private var isResolvingLocation = false
    @FocusState private var isLocationFieldFocused: Bool

    /// The coordinate to use for all searches. Custom location if set, otherwise GPS.
    private var effectiveLocation: CLLocationCoordinate2D? {
        customLocation?.coordinate ?? currentLocation()
    }

    /// Whether the Explore search engine should be active — true when either
    /// Possible or Unchecked filter is on (both need search results).
    private var showExploreSearch: Bool {
        showPossible || showUnchecked
    }

    /// The picks currently active for filtering / searching.
    private var activePicks: [FoodCategory] {
        picksService.picks.filter { activePickIDs.contains($0.id) }
    }

    /// Search placeholder that reflects the active filter.
    private var explorePlaceholder: String {
        let active = activePicks
        if active.count == 1 {
            return "Search for \(active[0].displayName.lowercased()) spots…"
        }
        let names = active.prefix(3).map { $0.displayName.lowercased() }
        if names.count <= 2 {
            return "Search for \(names.joined(separator: " & ")) spots…"
        }
        return "Search for all your picks…"
    }

    // MARK: Community data

    private var filteredAndSortedSpots: [Spot] {
        // When no picks are toggled on, show nothing
        guard !activePickIDs.isEmpty else { return [] }

        // Always filter to only spots whose categories overlap with active picks.
        // A pizza spot should never appear when only mezcal/flan/tacos are selected.
        let all = spotService.filteredSpots(for: SpotFilter(category: nil))
        let categoryFiltered = all.filter { spot in
            spot.categories.contains { cat in activePickIDs.contains(cat.rawValue) }
        }

        // Text search — filter by name/address/offerings
        let textFiltered: [Spot]
        if searchText.isEmpty {
            textFiltered = categoryFiltered
        } else {
            textFiltered = categoryFiltered.filter { spot in
                spot.name.localizedCaseInsensitiveContains(searchText) ||
                spot.address.localizedCaseInsensitiveContains(searchText) ||
                (spot.mezcalOfferings ?? []).contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Distance filter — show spots within ~35 miles of the effective location
        // (custom location if set, otherwise GPS).
        // Skip the distance filter when the user is actively searching by name
        // (they clearly want to find a specific spot regardless of distance).
        // When location is unavailable, show all (sorted alphabetically).
        guard let center = effectiveLocation else {
            return textFiltered.sorted { $0.name < $1.name }
        }
        let centerCL = CLLocation(latitude: center.latitude, longitude: center.longitude)

        let results: [Spot]
        if searchText.isEmpty {
            // Match the user's chosen search radius (degrees → meters).
            let maxDistance: CLLocationDistance = picksService.searchRadiusDegrees * 111_000
            results = textFiltered.filter { spot in
                centerCL.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude)) <= maxDistance
            }
        } else {
            // Text search — no distance cutoff, show all matching spots
            results = textFiltered
        }

        return results.sorted { a, b in
            let distA = centerCL.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
            let distB = centerCL.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            return distA < distB
        }
    }

    // MARK: Unified top section

    /// Merged list of verified spots + green-matched potential spots, sorted by distance.
    /// De-duplicates: if a venue exists in both Firestore and Apple Maps results, only
    /// the verified spot is included.
    private var unifiedTopSection: [UnifiedListItem] {
        var items: [UnifiedListItem] = []

        // Verified spots (if toggle is on)
        if showVerified {
            items += filteredAndSortedSpots.map { .verified($0) }
        }

        // Green-matched potential spots (if toggle is on)
        if showPossible {
            let deduped = matchedMapItems.filter { mapItem in
                guard let name = mapItem.name,
                      let coord = mapItem.placemark.location?.coordinate else { return true }
                return spotService.findExistingSpot(
                    name: name, latitude: coord.latitude, longitude: coord.longitude
                ) == nil
            }
            items += deduped.map { .potentialMatched($0) }
        }

        // Sort everything by distance
        return items.sorted {
            $0.distanceMeters(from: effectiveLocation) < $1.distanceMeters(from: effectiveLocation)
        }
    }

    // MARK: Potential-spot tap handling

    /// Opens SuggestedSpotSheet for a green-matched potential spot (rendered in the unified section).
    private func selectPotentialResult(_ mapItem: MKMapItem) {
        // Check if venue already exists in Firestore
        if let coord = mapItem.placemark.location?.coordinate,
           let name = mapItem.name,
           let existing = spotService.findExistingSpot(
               name: name, latitude: coord.latitude, longitude: coord.longitude
           ) {
            selectedSpot = existing
            return
        }

        // New venue — open SuggestedSpotSheet with website check
        websiteCheckTask?.cancel()
        multiCheckResult = nil
        let foodCat = activePicks.first ?? FoodCategory.mezcal
        selectedSuggestion = SuggestedSpot(mapItem: mapItem, suggestedCategory: foodCat)
        let picks = activePicks
        websiteCheckTask = Task {
            let result = await websiteChecker.checkAllPicks(
                mapItem, picks: picks, primaryPick: foodCat
            )
            guard !Task.isCancelled else { return }
            multiCheckResult = result
        }
    }

    /// Posts notification to show a potential spot on the Map tab.
    private func showPotentialOnMap(_ mapItem: MKMapItem) {
        let foodCat = activePicks.first ?? FoodCategory.mezcal
        let suggestion = SuggestedSpot(mapItem: mapItem, suggestedCategory: foodCat)
        NotificationCenter.default.post(
            name: .showOnMap,
            object: nil,
            userInfo: ["suggestion": suggestion]
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter — matching Map tab's PicksFilterBar (top position)
                PicksFilterBar(picks: picksService.picks, activeIDs: $activePickIDs)
                    .padding(.top, 8)

                // ── Search bar ────────────────────────────────────────────────
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            showExploreSearch ? explorePlaceholder : "Search spots, mezcals…",
                            text: $searchText
                        )
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // "Show on Map" — switches to Map tab centered on the search area
                    if showExploreSearch {
                        Button {
                            let center = customLocation?.coordinate
                                ?? locationManager.userLocation
                                ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
                            NotificationCenter.default.post(
                                name: .showAreaOnMap,
                                object: nil,
                                userInfo: ["latitude": center.latitude,
                                           "longitude": center.longitude]
                            )
                        } label: {
                            Image(systemName: "map.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.orange)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityLabel("Show on map")
                        .accessibilityHint("Switches to the map centered on the current search area")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Location bar — shared between both tabs
                locationBar

                // Spot search customization — shown when explore search is active
                if showExploreSearch {
                    spotSearchButton
                }

                // ── Result type filters (styled like Map tab's PinToggleButtons) ──
                resultTypeFilters
                    .padding(.top, 8)

                // ── Content ───────────────────────────────────────────────────
                if !showVerified && !showPossible && !showUnchecked {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No filters active")
                            .font(.headline)
                        Text("Turn on a filter above to see spots.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else if spotService.isLoading {
                    Spacer()
                    ProgressView("Loading spots…")
                    Spacer()
                } else {
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            // ── Unified top section (verified + green potential) ──
                            let topItems = unifiedTopSection
                            if !topItems.isEmpty {
                                unifiedTopList(items: topItems)
                            } else if !showExploreSearch {
                                // Only Verified is on but no verified spots found
                                VStack(spacing: 10) {
                                    Text("No verified spots yet")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(searchText.isEmpty
                                         ? "Be the first to add a \(activePicks.first?.displayName.lowercased() ?? "flan or mezcal") spot!"
                                         : "Try a different search term.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }

                            // ── Yellow / unmatched section (ExplorePanel) ──
                            if showExploreSearch {
                                ExplorePanel(
                                    searchText: $searchText,
                                    activeFilterPicks: activePicks,
                                    currentLocation: currentLocation,
                                    userPicks: picksService.picks,
                                    customLocation: $customLocation,
                                    findExistingSpot: { name, lat, lon in
                                        spotService.findExistingSpot(name: name, latitude: lat, longitude: lon)
                                    },
                                    onSelectExistingSpot: { spot in
                                        selectedSpot = spot
                                    },
                                    mapTermsVersion: mapTermsVersion,
                                    searchRadiusDegrees: picksService.searchRadiusDegrees,
                                    refreshVersion: refreshVersion,
                                    matchedMapItems: $matchedMapItems,
                                    uncheckedCount: $uncheckedCount,
                                    showUnchecked: showUnchecked,
                                    showDeeperScanPrompt: $showDeeperScanPrompt,
                                    triggerDeeperScan: $triggerDeeperScan,
                                    isSearchActive: $isSearchActive,
                                    websiteChecker: websiteChecker
                                )
                            }
                        }

                        // "Search Wider Area?" floating button — floats over the scroll content
                        if showDeeperScanPrompt {
                            Button {
                                triggerDeeperScan = true
                            } label: {
                                Label("Search Wider Area?", systemImage: "magnifyingglass")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            }
                            .padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.easeInOut(duration: 0.25), value: showDeeperScanPrompt)
                        }
                    }
                }
            }
            .navigationTitle("Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshVersion += 1
                        Task { await spotService.fetchSpots() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isSearchActive)
                }
                // Dismiss keyboard so the tab bar is always reachable
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .sheet(item: $selectedSpot) { spot in
                SpotDetailView(spot: spot)
                    .environmentObject(picksService)
            }
            .sheet(item: $selectedSuggestion) { suggestion in
                SuggestedSpotSheet(
                    suggestion: suggestion,
                    multiResult: multiCheckResult,
                    onConfirm: {
                        selectedSuggestion = nil
                        multiCheckResult = nil
                    },
                    onDismiss: {
                        selectedSuggestion = nil
                        multiCheckResult = nil
                    },
                    source: .exploreSearch,
                    userPicks: activePicks
                )
            }
            .sheet(item: $editingSpotSearchCategory) { category in
                EditSpotSearchView(category: category, onSave: {
                    mapTermsVersion += 1
                })
                .environmentObject(picksService)
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showSpotSearchOverview) {
                SpotSearchOverviewView(
                    picks: picksService.picks,
                    onEditCategory: { category in
                        showSpotSearchOverview = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            editingSpotSearchCategory = category
                        }
                    }
                )
                .environmentObject(picksService)
                .presentationDetents([.medium, .large])
            }
            .task {
                await spotService.fetchSpots()
            }
            .onDisappear {
                websiteCheckTask?.cancel()
                websiteCheckTask = nil
                multiCheckResult = nil
            }
        }
    }

    // MARK: Result type filters (matches Map tab's PinToggleButton style)

    /// Number of de-duped green-matched potential spots (excludes venues already verified).
    private var possibleCount: Int {
        matchedMapItems.filter { mapItem in
            guard let name = mapItem.name,
                  let coord = mapItem.placemark.location?.coordinate else { return true }
            return spotService.findExistingSpot(
                name: name, latitude: coord.latitude, longitude: coord.longitude
            ) == nil
        }.count
    }

    @ViewBuilder
    private var resultTypeFilters: some View {
        HStack(spacing: 6) {
            PinToggleButton(
                count: filteredAndSortedSpots.count,
                label: "Verified",
                color: .green,
                isOn: $showVerified
            )

            if possibleCount > 0 || isSearchActive {
                PinToggleButton(
                    count: possibleCount,
                    label: "Likely",
                    color: .green,
                    filled: false,
                    isOn: $showPossible
                )
            }

            if uncheckedCount > 0 || isSearchActive {
                PinToggleButton(
                    count: uncheckedCount,
                    label: "Nearby",
                    color: .yellow,
                    isOn: $showUnchecked
                )
            }

            if isSearchActive {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
    }

    // MARK: Spot search customization

    @ViewBuilder
    private var spotSearchButton: some View {
        Button {
            let active = activePicks
            if active.count == 1 {
                editingSpotSearchCategory = active[0]
            } else {
                showSpotSearchOverview = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text("Customize Spot Search")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 4)
    }



    // MARK: Unified top list

    /// Renders the unified top section — verified spots + green-matched potential spots
    /// interleaved by distance. Counts are shown in the PinToggleButton pills above,
    /// so no section header is needed here.
    @ViewBuilder
    private func unifiedTopList(items: [UnifiedListItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                switch item {
                case .verified(let spot):
                    Button {
                        selectedSpot = spot
                    } label: {
                        ListTabRowView(spot: spot, userLocation: effectiveLocation)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                case .potentialMatched(let mapItem):
                    HStack(spacing: 0) {
                        Button {
                            selectPotentialResult(mapItem)
                        } label: {
                            ExploreResultRowView(
                                mapItem: mapItem,
                                userLocation: effectiveLocation,
                                isMatched: true
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showPotentialOnMap(mapItem)
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider().padding(.leading, 72)
            }
        }
    }

    // MARK: - Location bar (shared between tabs)

    @ViewBuilder
    private var locationBar: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: customLocation != nil ? "location.circle.fill" : "location.circle")
                    .foregroundStyle(customLocation != nil ? .blue : .secondary)
                    .font(.subheadline)

                if isEditingLocation {
                    TextField("City name (e.g. Mammoth Lakes)", text: $locationInputText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .focused($isLocationFieldFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            // If there's exactly one suggestion, select it on Return
                            if let first = locationCompleter.suggestions.first {
                                resolveAndSelect(first)
                            }
                        }
                        .onChange(of: locationInputText) { _, newValue in
                            locationCompleter.updateQuery(newValue)
                        }
                        .onAppear {
                            // Auto-focus so the keyboard opens immediately — no second tap needed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isLocationFieldFocused = true
                            }
                        }

                    if isResolvingLocation {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        isEditingLocation = false
                        isLocationFieldFocused = false
                        locationInputText = ""
                        locationCompleter.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                } else if let custom = customLocation {
                    Text("Near: \(custom.name)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    // Clear custom location — return to GPS
                    Button {
                        customLocation = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .accessibilityLabel("Clear location, use current location")
                } else {
                    Button {
                        isEditingLocation = true
                    } label: {
                        Text("Near: Current Location")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 6)

            // Autocomplete suggestions from MKLocalSearchCompleter
            if isEditingLocation && !locationCompleter.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(locationCompleter.suggestions.prefix(5), id: \.self) { completion in
                        Button {
                            resolveAndSelect(completion)
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(completion.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 36)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Custom location resolution

    /// Resolves a completer suggestion to a coordinate and sets it as the custom location.
    private func resolveAndSelect(_ completion: MKLocalSearchCompletion) {
        isResolvingLocation = true
        Task {
            if let location = await locationCompleter.resolve(completion) {
                customLocation = location
                isEditingLocation = false
                locationInputText = ""
                locationCompleter.cancel()
            }
            isResolvingLocation = false
        }
    }


}

#Preview {
    ListTabView(locationManager: LocationManager(), picksService: UserPicksService(), activePickIDs: .constant(Set(["mezcal", "flan", "tortillas"])), websiteChecker: WebsiteCheckService())
        .environmentObject(SpotService())
}
