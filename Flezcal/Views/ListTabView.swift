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

/// Combined task identity for `.task(id:)` — re-fires search when the
/// query text, location, active picks, or search terms change.
///
/// Two modes:
///   - searchText empty → category browse (taggedMultiSearch, same as Map tab)
///   - searchText non-empty → venue-name search (add-spot workflow)
private struct SearchTaskID: Equatable, Hashable {
    let query: String              // Venue-name search text (empty = category browse)
    let activeFilterIDs: Set<String>   // IDs of active pick pills — triggers re-search on toggle
    let customLocation: CustomSearchLocation?
    let mapTermsVersion: Int        // Incremented when user edits mapSearchTerms — triggers re-search
    let refreshVersion: Int         // Incremented by manual refresh — triggers re-search

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query && lhs.activeFilterIDs == rhs.activeFilterIDs
        && lhs.customLocation == rhs.customLocation
        && lhs.mapTermsVersion == rhs.mapTermsVersion
        && lhs.refreshVersion == rhs.refreshVersion
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(activeFilterIDs)
        hasher.combine(customLocation?.name)
        hasher.combine(customLocation?.coordinate.latitude)
        hasher.combine(customLocation?.coordinate.longitude)
        hasher.combine(mapTermsVersion)
        hasher.combine(refreshVersion)
    }
}

// MARK: - Unified List Item

/// Wrapper for the unified top section — verified community spots and green-matched
/// potential spots interleaved by distance.
private enum UnifiedListItem: Identifiable {
    case verified(Spot)
    case potentialMatched(SuggestedSpot)

    var id: String {
        switch self {
        case .verified(let spot):
            return "v_\(spot.id)"
        case .potentialMatched(let suggestion):
            return "p_\(suggestion.id)"
        }
    }

    /// Distance in meters from a reference coordinate, for sorting.
    func distanceMeters(from location: CLLocationCoordinate2D?) -> Double {
        guard let loc = location else { return .greatestFiniteMagnitude }
        let ref = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        switch self {
        case .verified(let spot):
            return ref.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
        case .potentialMatched(let suggestion):
            return ref.distance(from: CLLocation(latitude: suggestion.coordinate.latitude, longitude: suggestion.coordinate.longitude))
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
// ExplorePanel is intentionally a separate struct from ListTabView:
//
// SpotService isolation: ListTabView observes SpotService via @EnvironmentObject.
// Every time spots load or update, ListTabView re-renders, which would cancel
// any in-flight .task(id:) if that task lived on ListTabView. By isolating the
// search task inside ExplorePanel (which does NOT observe SpotService),
// spot updates cannot disrupt the search.
//
// searchText is a @Binding for client-side venue name filtering. It is NOT
// part of SearchTaskID — typing does not trigger a new MKLocalSearch.
// One Search, Two Views: all searches use taggedMultiSearch with active picks.
//
// NEVER change these:
//   - Do NOT add @EnvironmentObject SpotService or @ObservedObject LocationManager here
//   - Do NOT change `@Binding var searchText` back to `let searchText: String`

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
    /// Incremented by the parent to trigger a manual re-search.
    let refreshVersion: Int
    /// Whether unchecked (yellow) rows should be visible — controlled by the
    /// parent's Unchecked toggle pill. Search still runs (for counts) but rows hide.
    let showUnchecked: Bool
    /// Whether the "Do a Deeper Scan?" button should show — exposed to parent
    /// so it can float over the ScrollView instead of scrolling with content.
    @Binding var showDeeperScanPrompt: Bool
    /// Set to true by the parent when user taps "Do a Deeper Scan?".
    /// ExplorePanel watches this and runs the deeper scan.
    @Binding var triggerDeeperScan: Bool
    /// Whether the search engine or pre-screen is actively working.
    /// Exposed to parent so it can show a spinner in the header.
    @Binding var isSearchActive: Bool
    @StateObject private var searchService = LocationSearchService()
    /// Shared search result store — reads category browse results from here.
    /// ⚠️ NOT @EnvironmentObject SpotService — see stability contract above.
    @EnvironmentObject var searchResultStore: SearchResultStore

    // Sheet state lives here so changes never re-render ListTabView
    @State private var selectedSuggestion: SuggestedSpot? = nil
    @State private var multiCheckResult: MultiCategoryCheckResult? = nil
    @State private var websiteCheckTask: Task<Void, Never>? = nil
    let websiteChecker: WebsiteCheckService

    /// Venue-name search results — only used when the user types a name in the search bar.
    /// Category browse results live in SearchResultStore.
    @State private var venueSearchResults: [SuggestedSpot] = []

    /// True while the batch pre-screen is actively scanning homepages.
    @State private var isPreScreening = false

    /// Deeper scan state — Wave 2 is deferred until the user taps "Do a Deeper Scan?"
    @State private var deeperScanPool: [SuggestedSpot] = []
    @State private var deeperScanPicks: [FoodCategory] = []
    @State private var wave1Results: [String: Set<String>] = [:]
    @State private var deeperScanTask: Task<Void, Never>? = nil

    /// True when the current search is a venue-name search (user typed text).
    private var isVenueSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The coordinate to use for searches. Custom location if set, otherwise GPS.
    private var effectiveLocation: CLLocationCoordinate2D? {
        customLocation?.coordinate ?? currentLocation()
    }

    /// Results to display — from SearchResultStore for category browse,
    /// from local venueSearchResults for venue-name search.
    private var displayResults: [SuggestedSpot] {
        isVenueSearch ? venueSearchResults : searchResultStore.suggestions
    }

    /// Number of pre-screen matched results — derived from splitResults so
    /// the banner count always matches the items sent to the parent.
    private var matchedCount: Int {
        splitResults.matched.count
    }

    /// Results split into matched (pre-screen confirmed) and unmatched.
    /// Green-matched venues go to the parent for the unified top section.
    /// Yellow/unchecked venues render here as "Other Nearby".
    ///
    /// A venue is "matched" (green) only if its preScreenMatches overlap
    /// with the currently active pick IDs — same logic as MapTabView's
    /// visibleGhostPins, so both tabs show identical green results.
    private var splitResults: (matched: [SuggestedSpot], other: [SuggestedSpot]) {
        let activeIDs = Set(activeFilterPicks.map(\.id))
        let nameFilter = searchText.trimmingCharacters(in: .whitespaces).lowercased()

        var top: [SuggestedSpot] = []
        var rest: [SuggestedSpot] = []

        for spot in displayResults {
            // Skip venues that already exist as verified spots in Firestore.
            if findExistingSpot(spot.name, spot.coordinate.latitude, spot.coordinate.longitude) != nil {
                continue
            }
            // Client-side venue name filter — searchText narrows visible results
            // (only relevant for category browse; venue search already filtered by query)
            if !isVenueSearch && !nameFilter.isEmpty && !spot.name.lowercased().contains(nameFilter) {
                continue
            }
            if let matches = spot.preScreenMatches, !matches.isEmpty,
               !matches.isDisjoint(with: activeIDs) {
                top.append(spot)
            } else {
                rest.append(spot)
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
                if displayResults.isEmpty && isSearchActive {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if displayResults.isEmpty && !isSearchActive {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                        Text("Try a different location or adjust your Flezcals.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No results found. Try a different search.")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Results list — stays visible while a new search is in flight
                    let split = splitResults
                    let displayCount = split.matched.count + split.other.count

                    LazyVStack(spacing: 0) {
                        // ── Status banner ──
                        // When a single category is active, use its name (e.g. "mezcal").
                        // When multiple picks are active, use "Flezcal" as the noun.
                        let singleCategory = activeFilterPicks.count == 1 ? activeFilterPicks[0].displayName.lowercased() : nil
                        let isMultiSearch = singleCategory == nil

                        Group {
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
                            } else if !isPreScreening && matchedCount == 0 && !displayResults.isEmpty {
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

                            ForEach(split.other) { suggestion in
                                exploreRow(suggestion, isMatched: false)
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
            refreshVersion: refreshVersion
        )) {
            // No active picks — clear results and stop
            guard !activeFilterPicks.isEmpty else {
                venueSearchResults = []
                searchResultStore.suggestions = []
                searchResultStore.fullPool = []
                searchResultStore.preScreenComplete = false
                isPreScreening = false
                isSearchActive = false
                return
            }

            let venueSearch = isVenueSearch
            let picks = activePicks
            let center = effectiveLocation ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
            #if DEBUG
            print("[Explore] .task fired — searchText='\(searchText)' activePicks=\(picks.map(\.displayName)) customLoc=\(customLocation?.name ?? "nil") venueSearch=\(venueSearch)")
            #endif

            if venueSearch {
                // ── Venue-name search (add-spot workflow) ──────────────────
                // User typed a specific venue name. Run a dedicated MKLocalSearch
                // so they can find and add any place, not just category results.
                let query = searchText
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    venueSearchResults = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                isSearchActive = true
                await searchService.search(query: query, userLocation: effectiveLocation)
                guard !Task.isCancelled else {
                    isSearchActive = false
                    return
                }
                let foodCat = primaryFoodCategory
                venueSearchResults = searchService.searchResults.map {
                    SuggestedSpot(mapItem: $0, suggestedCategory: foodCat)
                }
            } else {
                // ── Category browse (One Search, Two Views) ───────────────
                // Delegates to SearchResultStore — same data as the Map tab.
                venueSearchResults = []  // clear any stale venue search
                isSearchActive = true
                showDeeperScanPrompt = false

                // Empty existing Spot list — fetchSuggestions filters internally.
                // Pass empty array since ExplorePanel doesn't observe SpotService.
                let region = MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                )
                await searchResultStore.fetchSuggestions(
                    in: region,
                    existingSpots: [],
                    picks: picks
                )
                guard !Task.isCancelled else {
                    isSearchActive = false
                    return
                }
            }

            // Pre-screen: scan homepages to re-rank results (matched venues first).
            guard !Task.isCancelled, !displayResults.isEmpty else {
                isSearchActive = false
                return
            }
            isPreScreening = true
            showDeeperScanPrompt = false

            // Wave 1: scan the closest 25 venues so green badges appear fast.
            let fullPool = isVenueSearch ? venueSearchResults : searchResultStore.fullPool
            let wave1 = Array(fullPool.prefix(25))
            let wave2 = Array(fullPool.dropFirst(25))

            #if DEBUG
            print("[Explore] starting wave 1 pre-screen: \(wave1.count) items")
            #endif

            let w1Results = await websiteChecker.batchPreScreen(suggestions: wave1, picks: picks)
            guard !Task.isCancelled else {
                isPreScreening = false
                isSearchActive = false
                return
            }
            // Bake pre-screen results into the data
            if isVenueSearch {
                applyPreScreenToVenueSearch(w1Results)
            } else {
                searchResultStore.applyPreScreenResults(w1Results)
            }
            #if DEBUG
            let w1Green = w1Results.values.filter { !$0.isEmpty }.count
            print("[Explore] wave 1 done: \(w1Green) matches out of \(wave1.count). \(wave2.count) deferred.")
            #endif

            isPreScreening = false

            // Store Wave 2 for the "Do a Deeper Scan?" button.
            if !wave2.isEmpty {
                wave1Results = w1Results
                deeperScanPool = wave2
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
        .onChange(of: isPreScreening) { _, val in
            if !val { isSearchActive = false }
        }
        .onDisappear {
            // Cancel any in-flight tasks so they don't write
            // back to @State after the view is gone.
            websiteCheckTask?.cancel()
            websiteCheckTask = nil
            deeperScanTask?.cancel()
            deeperScanTask = nil
            multiCheckResult = nil
            isPreScreening = false
            showDeeperScanPrompt = false
            isSearchActive = false
        }
    }

    /// Wave 2: runs only when the user taps "Do a Deeper Scan?".
    /// Scans the remaining pool beyond the closest 25 and merges results.
    private func runDeeperScan() {
        showDeeperScanPrompt = false
        isPreScreening = true

        let pool = deeperScanPool
        let picks = deeperScanPicks
        let w1 = wave1Results

        deeperScanTask?.cancel()
        deeperScanTask = Task {
            let w2Results = await websiteChecker.batchPreScreen(suggestions: pool, picks: picks)
            guard !Task.isCancelled else {
                isPreScreening = false
                return
            }
            // Merge Wave 2 into Wave 1 results and re-apply
            var allResults = w1
            for (key, value) in w2Results { allResults[key] = value }
            if isVenueSearch {
                applyPreScreenToVenueSearch(allResults)
            } else {
                searchResultStore.applyPreScreenResults(allResults)
            }
            #if DEBUG
            let w2Green = w2Results.values.filter { !$0.isEmpty }.count
            print("[Explore] Deeper scan done: \(w2Green) matches out of \(pool.count)")
            #endif
            isPreScreening = false
            deeperScanPool = []
        }
    }

    /// Bakes pre-screen results into venue search results (local state).
    /// Only used for venue-name search — category browse uses SearchResultStore.
    private func applyPreScreenToVenueSearch(_ results: [String: Set<String>]) {
        venueSearchResults = venueSearchResults.map { suggestion in
            var updated = suggestion
            if let matched = results[suggestion.id] {
                updated.preScreenMatches = matched
            }
            return updated
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

    /// A single row in the Explore results list — venue info + green checkmark
    /// for pre-screen matches + "Show on Map" button.
    @ViewBuilder
    private func exploreRow(_ suggestion: SuggestedSpot, isMatched: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                selectResult(suggestion)
            } label: {
                ExploreResultRowView(
                    mapItem: suggestion.mapItem,
                    userLocation: effectiveLocation,
                    isMatched: isMatched
                )
            }

            // "Show on Map" shortcut — jumps to Map tab with ghost pin
            Button {
                showOnMap(suggestion)
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

    /// Picks to use for the current search context — always all active picks.
    /// One Search, Two Views: search bar text is a client-side name filter,
    /// not a change in search scope.
    private var searchScopedPicks: [FoodCategory] {
        activePicks
    }

    private func selectResult(_ suggestion: SuggestedSpot) {
        // Check if this venue already exists in Firestore — if so, go straight
        // to SpotDetailView (same workflow as tapping a spot in the list).
        if let existing = findExistingSpot(suggestion.name, suggestion.coordinate.latitude, suggestion.coordinate.longitude) {
            onSelectExistingSpot(existing)
            return
        }

        // New venue — open SuggestedSpotSheet with website check
        websiteCheckTask?.cancel()
        multiCheckResult = nil
        selectedSuggestion = suggestion
        let picks = searchScopedPicks
        let primaryPick = suggestion.suggestedCategory
        websiteCheckTask = Task {
            let result = await websiteChecker.checkAllPicks(
                suggestion.mapItem, picks: picks, primaryPick: primaryPick
            )
            guard !Task.isCancelled else { return }
            multiCheckResult = result
        }
    }

    /// Jump to the Map tab centered on this venue with a ghost pin + website check.
    private func showOnMap(_ suggestion: SuggestedSpot) {
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
    @EnvironmentObject var searchResultStore: SearchResultStore

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
    /// Community Map mode — shows all verified spots, hides ghost pins.
    @Binding var showCommunityMap: Bool
    /// Set by the Map tab's list button — consumed on appear to set customLocation.
    @Binding var pendingSpotsLocation: CustomSearchLocation?

    init(locationManager: LocationManager, picksService: UserPicksService, activePickIDs: Binding<Set<String>>, showCommunityMap: Binding<Bool>, pendingSpotsLocation: Binding<CustomSearchLocation?>, websiteChecker: WebsiteCheckService) {
        self.locationManager = locationManager
        self.currentLocation = { [locationManager] in locationManager.userLocation }
        self.picksService = picksService
        self._activePickIDs = activePickIDs
        self._showCommunityMap = showCommunityMap
        self._pendingSpotsLocation = pendingSpotsLocation
        self.websiteChecker = websiteChecker
    }
    @State private var selectedSpot: Spot?
    @State private var searchText = ""
    /// Worm easter egg — tapping the worm shows a prompt to enable Community Map.
    @State private var showCommunityEasterEgg = false
    /// Result type filters — all on by default, matching Map tab's three-way toggles.
    @State private var showVerified = true
    @State private var showPossible = true
    @State private var showUnchecked = true

    /// True immediately when the user selects a new location — shows the
    /// "Searching nearby spots…" spinner without waiting for the task to fire.
    @State private var isLocationSearchPending = false

    // "Do a Deeper Scan?" button state — driven by ExplorePanel, displayed by parent
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
    @StateObject private var venueCompleter = VenueCompleterService()
    @State private var pinnedVenue: SuggestedSpot? = nil
    @State private var isResolvingLocation = false
    @FocusState private var isLocationFieldFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool

    /// The coordinate to use for all searches. Custom location if set, otherwise GPS.
    private var effectiveLocation: CLLocationCoordinate2D? {
        customLocation?.coordinate ?? currentLocation()
    }

    /// Whether the Explore search engine should be active — true when either
    /// Possible or Unchecked filter is on (both need search results).
    /// Disabled in Community Map mode (only verified spots shown).
    private var showExploreSearch: Bool {
        guard !showCommunityMap else { return false }
        return showPossible || showUnchecked
    }

    /// The picks currently active for filtering / searching.
    private var activePicks: [FoodCategory] {
        picksService.picks.filter { activePickIDs.contains($0.id) }
    }

    /// Search placeholder that reflects the active filter.
    private var explorePlaceholder: String {
        "Search for a venue to add…"
    }

    // MARK: Community data

    private var filteredAndSortedSpots: [Spot] {
        let all = spotService.filteredSpots(for: SpotFilter(category: nil))

        // Community Map mode — show all verified spots across all categories
        let categoryFiltered: [Spot]
        if showCommunityMap {
            categoryFiltered = all
        } else {
            // When no picks are toggled on, show nothing
            guard !activePickIDs.isEmpty else { return [] }

            // Always filter to only spots whose categories overlap with active picks.
            // A pizza spot should never appear when only mezcal/flan/tacos are selected.
            categoryFiltered = all.filter { spot in
                spot.categories.contains { cat in activePickIDs.contains(cat.rawValue) }
            }
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
            // 0.5° ≈ 55.5 km / 34.5 mi — consistent with SuggestionService
            let maxDistance: CLLocationDistance = 0.5 * 111_000
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

    /// Verified spots capped to the geographic scope of the explore search results.
    /// When explore results exist, verified spots beyond 1.5× the farthest search
    /// result are excluded — prevents a long tail of distant spots extending far
    /// beyond the search area. When no explore results exist, returns the full set.
    private var scopedVerifiedSpots: [Spot] {
        var spots = filteredAndSortedSpots

        // Cap to search area when explore results are available
        if showExploreSearch, !searchResultStore.suggestions.isEmpty,
           let center = effectiveLocation {
            let ref = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let maxSearchDist = searchResultStore.suggestions.map { suggestion in
                ref.distance(from: CLLocation(
                    latitude: suggestion.coordinate.latitude,
                    longitude: suggestion.coordinate.longitude
                ))
            }.max() ?? 0

            if maxSearchDist > 0 {
                let cap = maxSearchDist * 1.5
                spots = spots.filter { spot in
                    ref.distance(from: CLLocation(
                        latitude: spot.latitude,
                        longitude: spot.longitude
                    )) <= cap
                }
            }
        }

        return spots
    }

    /// Merged list of verified spots + green-matched potential spots, sorted by distance.
    /// De-duplicates: if a venue exists in both Firestore and Apple Maps results, only
    /// the verified spot is included.
    private var unifiedTopSection: [UnifiedListItem] {
        var items: [UnifiedListItem] = []

        // Verified spots (if toggle is on), capped to search area
        if showVerified {
            items += scopedVerifiedSpots.map { .verified($0) }
        }

        // Green-matched potential spots (if toggle is on)
        // Reads directly from SearchResultStore — no binding chain needed.
        if showPossible {
            let existingNames = Set(scopedVerifiedSpots.map { $0.name.lowercased() })
            let matched = searchResultStore.splitByPreScreen(
                activePickIDs: activePickIDs,
                existingSpotNames: existingNames
            ).matched
            let deduped = matched.filter { suggestion in
                spotService.findExistingSpot(
                    name: suggestion.name,
                    latitude: suggestion.coordinate.latitude,
                    longitude: suggestion.coordinate.longitude
                ) == nil
            }
            items += deduped.map { .potentialMatched($0) }
        }

        // Sort by distance
        items.sort {
            $0.distanceMeters(from: effectiveLocation) < $1.distanceMeters(from: effectiveLocation)
        }

        // Pinned venue from direct search — always at the very top
        if let pinned = pinnedVenue {
            items.insert(.potentialMatched(pinned), at: 0)
        }

        return items
    }

    // MARK: Potential-spot tap handling

    /// Opens SuggestedSpotSheet for a green-matched potential spot (rendered in the unified section).
    private func selectPotentialResult(_ suggestion: SuggestedSpot) {
        // Check if venue already exists in Firestore
        if let existing = spotService.findExistingSpot(
            name: suggestion.name,
            latitude: suggestion.coordinate.latitude,
            longitude: suggestion.coordinate.longitude
        ) {
            selectedSpot = existing
            return
        }

        // New venue — open SuggestedSpotSheet with website check
        websiteCheckTask?.cancel()
        multiCheckResult = nil
        selectedSuggestion = suggestion
        let picks = activePicks
        websiteCheckTask = Task {
            let result = await websiteChecker.checkAllPicks(
                suggestion.mapItem, picks: picks, primaryPick: suggestion.suggestedCategory
            )
            guard !Task.isCancelled else { return }
            multiCheckResult = result
        }
    }

    /// Posts notification to show a potential spot on the Map tab.
    private func showPotentialOnMap(_ suggestion: SuggestedSpot) {
        NotificationCenter.default.post(
            name: .showOnMap,
            object: nil,
            userInfo: ["suggestion": suggestion]
        )
    }

    /// Resolves a venue autocomplete suggestion and pins it at the top of the list.
    private func selectVenueFromCompleter(_ completion: MKLocalSearchCompletion) {
        venueCompleter.cancel()
        let query = searchText
        searchText = ""
        isSearchFieldFocused = false
        let category = activePicks.first ?? picksService.picks.first ?? FoodCategory.mezcal
        Task {
            guard let spot = await venueCompleter.resolve(completion, suggestedCategory: category) else {
                #if DEBUG
                print("[VenueSearch] Failed to resolve: \(query)")
                #endif
                return
            }
            pinnedVenue = spot
        }
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
                        .focused($isSearchFieldFocused)
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

                    // "Show on Map" — switches to Map tab with the same search results.
                    // Only sends results for category browse (searchText empty).
                    // Venue-name search is an add-spot workflow and shouldn't
                    // overwrite the Map tab's category results.
                    if showExploreSearch {
                        Button {
                            let center = customLocation?.coordinate
                                ?? locationManager.userLocation
                                ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
                            var info: [String: Any] = [
                                "latitude": center.latitude,
                                "longitude": center.longitude
                            ]
                            // Always include the store's suggestions so the Map tab
                            // preserves green pre-screen data instead of re-fetching.
                            // Both tabs share SearchResultStore — the data is the same.
                            if !searchResultStore.suggestions.isEmpty {
                                info["suggestions"] = searchResultStore.suggestions
                            }
                            NotificationCenter.default.post(
                                name: .showAreaOnMap,
                                object: nil,
                                userInfo: info
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

                // ── Venue autocomplete dropdown ──────────────────────────────
                if isSearchFieldFocused && !venueCompleter.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(venueCompleter.suggestions.prefix(5), id: \.self) { completion in
                            Button {
                                selectVenueFromCompleter(completion)
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(.orange)
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

                // Location bar — shared between both tabs
                locationBar

                // Spot search customization — shown when explore search is active
                if showExploreSearch {
                    spotSearchButton
                }

                // ── Result type filters (styled like Map tab's PinToggleButtons) ──
                resultTypeFilters
                    .padding(.top, 8)

                // ── Searching indicator — prominent banner when a fresh search
                //    is running and results haven't arrived yet. Shown at the
                //    parent level so it's always visible (not buried in scroll).
                //    isLocationSearchPending fires instantly on location change;
                //    isSearchActive fires once the .task(id:) begins the search. ──
                if (isLocationSearchPending || isSearchActive) && searchResultStore.suggestions.isEmpty && showExploreSearch {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Searching nearby spots…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }

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
                                    Text("Be the first to add a \(activePicks.first?.displayName.lowercased() ?? "flan or mezcal") spot!")
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
                                    refreshVersion: refreshVersion,
                                    showUnchecked: showUnchecked,
                                    showDeeperScanPrompt: $showDeeperScanPrompt,
                                    triggerDeeperScan: $triggerDeeperScan,
                                    isSearchActive: $isSearchActive,
                                    websiteChecker: websiteChecker
                                )
                            }
                        }

                        // "Do a Deeper Scan?" floating button — floats over the scroll content
                        if showDeeperScanPrompt {
                            Button {
                                triggerDeeperScan = true
                            } label: {
                                Label("Do a Deeper Scan?", systemImage: "magnifyingglass")
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
            .alert("Easter Egg! 🐛", isPresented: $showCommunityEasterEgg) {
                Button("Yes") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCommunityMap = true
                    }
                }
                Button("No", role: .cancel) { }
            } message: {
                Text("Do you want to see all user verified spots for all 50 Flezcals in your search area?")
            }
            .onChange(of: pendingSpotsLocation) { _, newLocation in
                guard let location = newLocation else { return }
                pendingSpotsLocation = nil  // consume immediately
                customLocation = location
            }
            .onChange(of: searchResultStore.suggestions) { _, newResults in
                // Clear the instant-spinner flag once results arrive
                if !newResults.isEmpty {
                    isLocationSearchPending = false
                }
            }
            .onChange(of: searchText) { _, newValue in
                venueCompleter.updateQuery(newValue)
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    venueCompleter.cancel()
                }
            }
        }
    }

    // MARK: Result type filters (matches Map tab's PinToggleButton style)

    /// Number of green-matched potential spots that will actually render.
    /// Derived from unifiedTopSection so the pill count always matches the visible rows.
    private var possibleCount: Int {
        unifiedTopSection.filter {
            if case .potentialMatched = $0 { return true }
            return false
        }.count
    }

    /// Number of unmatched (yellow/gray) results — reads from SearchResultStore.
    private var uncheckedCount: Int {
        let existingNames = Set(filteredAndSortedSpots.map { $0.name.lowercased() })
        return searchResultStore.splitByPreScreen(
            activePickIDs: activePickIDs,
            existingSpotNames: existingNames
        ).other.count
    }

    @ViewBuilder
    private var resultTypeFilters: some View {
        HStack(spacing: 6) {
            // Worm easter egg — hidden Community Map trigger
            CommunityWormButton(
                showCommunityMap: $showCommunityMap,
                showEasterEgg: $showCommunityEasterEgg
            )

            PinToggleButton(
                count: scopedVerifiedSpots.count,
                label: "Verified",
                color: .green,
                isOn: $showVerified
            )

            // Hide Likely/Nearby toggles in Community Map mode
            if !showCommunityMap {
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

                case .potentialMatched(let suggestion):
                    let isPinned = pinnedVenue?.id == suggestion.id
                    HStack(spacing: 0) {
                        Button {
                            selectPotentialResult(suggestion)
                        } label: {
                            ExploreResultRowView(
                                mapItem: suggestion.mapItem,
                                userLocation: effectiveLocation,
                                isMatched: true
                            )
                        }
                        .buttonStyle(.plain)

                        if isPinned {
                            Button {
                                pinnedVenue = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                showPotentialOnMap(suggestion)
                            } label: {
                                Image(systemName: "map")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
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

                // Go button — triggers a new search for the current location
                if showExploreSearch && !isEditingLocation {
                    Button {
                        refreshVersion += 1
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.orange)
                    }
                    .accessibilityLabel("Search this location")
                    .disabled(isSearchActive)
                }
            }
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
                // Clear stale results and show spinner immediately —
                // don't wait for .task(id:) to detect the SearchTaskID change.
                searchResultStore.suggestions = []
                searchResultStore.fullPool = []
                searchResultStore.preScreenComplete = false
                isLocationSearchPending = true

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
    ListTabView(locationManager: LocationManager(), picksService: UserPicksService(), activePickIDs: .constant(Set(["mezcal", "flan", "tortillas"])), showCommunityMap: .constant(false), pendingSpotsLocation: .constant(nil), websiteChecker: WebsiteCheckService())
        .environmentObject(SpotService())
        .environmentObject(SearchResultStore())
}
