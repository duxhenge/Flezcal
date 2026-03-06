import SwiftUI
@preconcurrency import MapKit
import CoreLocation

// MARK: - List mode

/// Controls whether the list shows confirmed community spots or live Apple Maps search results.
enum ListMode: String, CaseIterable {
    case community = "Verified Spots"
    case explore   = "Potential Spots"
}

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
    let filterID: String?           // SpotFilter.category?.rawValue — triggers re-search on pill tap
    let customLocation: CustomSearchLocation?
    let mapTermsVersion: Int        // Incremented when user edits mapSearchTerms — triggers re-search
    let searchRadius: Double        // Triggers re-search when user changes search distance

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query && lhs.filterID == rhs.filterID
        && lhs.customLocation == rhs.customLocation
        && lhs.mapTermsVersion == rhs.mapTermsVersion
        && lhs.searchRadius == rhs.searchRadius
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(filterID)
        hasher.combine(customLocation?.name)
        hasher.combine(customLocation?.coordinate.latitude)
        hasher.combine(customLocation?.coordinate.longitude)
        hasher.combine(mapTermsVersion)
        hasher.combine(searchRadius)
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
                        Text(cat.emoji)
                            .font(.caption2)
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
                        Text(cat.emoji)
                            .font(.caption2)
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
                        Text(cat.emoji)
                            .font(.caption2)
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
    /// The FoodCategory the user selected in the filter bar. nil = "All".
    /// Passed as FoodCategory? (not SpotFilter) so custom picks aren't lost
    /// in the SpotCategory conversion — SpotCategory is a fixed enum that
    /// can't represent user-created categories.
    let selectedFilterCategory: FoodCategory?
    let currentLocation: () -> CLLocationCoordinate2D?
    /// User's active picks — plain let (stability contract). Used by checkAllPicks
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
    /// Tier 2 (bottom): Unmatched venues, sorted by distance.
    private var splitResults: (matched: [MKMapItem], other: [MKMapItem]) {
        let results = searchService.searchResults
        let isFilterSearch = searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let matchedIndices = preScreenMatchedIndices ?? []

        var top: [MKMapItem] = []
        var rest: [MKMapItem] = []

        for (index, item) in results.enumerated() {
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
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else if searchService.searchResults.isEmpty && !searchService.isSearching {
                    Spacer()
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
                    .padding()
                    Spacer()
                } else {
                    // Results list — stays visible while a new search is in flight
                    let isFilterSearch = searchText.trimmingCharacters(in: .whitespaces).isEmpty
                    let split = splitResults
                    let displayCount = split.matched.count + split.other.count

                    List {
                        // ── Status banner (auto-searches only) ──
                        if isFilterSearch {
                            // When a specific category is selected, use its name (e.g. "mezcal").
                            // When "All" is selected (multiple picks), use "Flezcal" as the noun.
                            let singleCategory = selectedFilterCategory?.displayName.lowercased()
                            let isMultiSearch = singleCategory == nil

                            Section {
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
                                    .listRowSeparator(.hidden)
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
                                    .listRowSeparator(.hidden)
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
                                    .listRowSeparator(.hidden)
                                }
                            }
                        }

                        // ── User-typed search: plain count header ──
                        if !isFilterSearch {
                            Section {
                                HStack {
                                    Text("\(displayCount) result\(displayCount == 1 ? "" : "s") from Apple Maps")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if searchService.isSearching {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .listRowSeparator(.hidden)
                            }
                        }

                        // ── Matched results (pre-screen confirmed) ──
                        if !split.matched.isEmpty {
                            Section {
                                ForEach(split.matched, id: \.self) { mapItem in
                                    exploreRow(mapItem, isMatched: true)
                                }
                            }
                        }

                        // ── Other nearby results ──
                        Section {
                            ForEach(split.other, id: \.self) { mapItem in
                                exploreRow(mapItem, isMatched: false)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
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
                userPicks: searchScopedPicks
            )
        }
        .task(id: SearchTaskID(
            query: searchText,
            filterID: selectedFilterCategory?.id,
            customLocation: customLocation,
            mapTermsVersion: mapTermsVersion,
            searchRadius: searchRadiusDegrees
        )) {
            let userTypedText = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            #if DEBUG
            print("[Explore] .task fired — searchText='\(searchText)' filter=\(selectedFilterCategory?.displayName ?? "All") customLoc=\(customLocation?.name ?? "nil") userTyped=\(userTypedText)")
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
            } else if let foodCat = selectedFilterCategory {
                // Filter pill active — multi-query search using all mapSearchTerms.
                // Niche terms like "mezcal" return few Apple Maps hits on their own,
                // so we also search broader terms like "bar" and "restaurant" to find
                // nearby venues, then let the website pre-screen re-rank the ones
                // that actually carry the item.
                await searchService.multiSearch(
                    queries: foodCat.mapSearchTerms,
                    userLocation: effectiveLocation,
                    radius: searchRadiusDegrees
                )
            } else {
                // "All" filter — multi-query search combining terms from all picks.
                // A single "restaurant" query misses venues that Apple Maps classifies
                // as bars, cafes, or nightlife. Using each pick's mapSearchTerms ensures
                // niche venues (mezcal bars, flan bakeries) appear in the results for
                // the pre-screen to scan and promote.
                var allTerms: [String] = []
                var seen = Set<String>()
                for pick in userPicks {
                    for term in pick.mapSearchTerms {
                        let key = term.lowercased()
                        if seen.insert(key).inserted {
                            allTerms.append(term)
                        }
                    }
                }
                // Fall back to "restaurant" if the user has no picks
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
            // Extract (index, url) pairs on @MainActor before crossing into the
            // WebsiteCheckService actor — MKMapItem is non-Sendable.
            let itemURLs: [(index: Int, url: URL)] = items.enumerated().compactMap { index, item in
                guard let url = item.url else { return nil }
                return (index: index, url: url)
            }

            // Two-wave pre-screen: scan the first 10 results (most relevant)
            // first so green badges appear at the top of the list quickly,
            // then scan the remaining results in a second wave.
            let wave1Count = min(10, itemURLs.count)
            let wave1 = Array(itemURLs.prefix(wave1Count))
            let wave2 = Array(itemURLs.dropFirst(wave1Count))

            #if DEBUG
            print("[Explore] starting wave 1 pre-screen: \(wave1.count) items")
            #endif

            // ── Wave 1: top results ──
            var matched = await websiteChecker.batchPreScreenMapItems(wave1, picks: picks)
            guard !Task.isCancelled else {
                isPreScreening = false
                return
            }
            // Show wave 1 results immediately so green badges appear fast.
            preScreenMatchedIndices = matched
            #if DEBUG
            print("[Explore] wave 1 done: \(matched.count) matches out of \(wave1.count)")
            #endif

            // ── Wave 2: remaining results ──
            if !wave2.isEmpty {
                let wave2Matched = await websiteChecker.batchPreScreenMapItems(wave2, picks: picks)
                guard !Task.isCancelled else {
                    isPreScreening = false
                    return
                }
                matched = matched.union(wave2Matched)
                preScreenMatchedIndices = matched
                #if DEBUG
                print("[Explore] wave 2 done: \(wave2Matched.count) matches out of \(wave2.count)")
                #endif
            }

            #if DEBUG
            print("[Explore] pre-screen complete: \(matched.count) matches out of \(items.count)")
            #endif
            isPreScreening = false
        }
        .onDisappear {
            // Cancel any in-flight website check so it doesn't write
            // back to @State after the view is gone.
            websiteCheckTask?.cancel()
            websiteCheckTask = nil
            multiCheckResult = nil
            preScreenMatchedIndices = nil
            isPreScreening = false
        }
    }

    /// Resolve the primary FoodCategory for a search result.
    /// Uses the active filter if set, otherwise the user's first pick.
    private var primaryFoodCategory: FoodCategory {
        if let foodCat = selectedFilterCategory {
            return foodCat
        }
        return userPicks.first ?? FoodCategory.mezcal
    }

    /// Picks scoped to the active filter — all picks when "All", single pick otherwise.
    private var activePicks: [FoodCategory] {
        if selectedFilterCategory != nil {
            return [primaryFoodCategory]
        }
        return userPicks
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
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
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

    init(locationManager: LocationManager, picksService: UserPicksService, websiteChecker: WebsiteCheckService) {
        self.locationManager = locationManager
        self.currentLocation = { [locationManager] in locationManager.userLocation }
        self.picksService = picksService
        self.websiteChecker = websiteChecker
    }

    @State private var selectedFilter: FoodCategory? = nil   // nil = "All"
    @State private var selectedSpot: Spot?
    @State private var searchText = ""
    @State private var listMode: ListMode = .community

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

    /// Search placeholder that reflects the active filter.
    private var explorePlaceholder: String {
        if let filter = selectedFilter {
            return "Search for \(filter.displayName.lowercased()) spots…"
        }
        let names = picksService.picks.prefix(3).map { $0.displayName.lowercased() }
        if names.count <= 2 {
            return "Search for \(names.joined(separator: " & ")) spots…"
        }
        return "Search for all your picks…"
    }

    // MARK: Community data

    private var filteredAndSortedSpots: [Spot] {
        let spotFilter = SpotFilter(category: selectedFilter.flatMap { SpotCategory(rawValue: $0.id) })
        let categoryFiltered = spotService.filteredSpots(for: spotFilter)

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

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Mode toggle ───────────────────────────────────────────────
                Picker("Mode", selection: $listMode) {
                    ForEach(ListMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // ── Search bar ────────────────────────────────────────────────
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            listMode == .community
                                ? "Search spots, mezcals…"
                                : explorePlaceholder,
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
                    if listMode == .explore {
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

                // Category filter — shown in both modes
                PicksFilterBar(picks: picksService.picks, selectedPick: $selectedFilter)
                    .padding(.top, 8)

                // Spot search customization — Explore mode only
                if listMode == .explore {
                    spotSearchButton
                    searchRadiusLabel
                }

                // ── Content ───────────────────────────────────────────────────
                switch listMode {
                case .community:
                    communityContent
                case .explore:
                    ExplorePanel(
                        searchText: $searchText,
                        selectedFilterCategory: selectedFilter,
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
                        websiteChecker: websiteChecker
                    )
                }
            }
            .navigationTitle("Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await spotService.fetchSpots() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
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
                .presentationDetents([.medium, .large])
            }
            .onChange(of: listMode) { _, _ in
                searchText = ""
            }
            .task {
                await spotService.fetchSpots()
            }
        }
    }

    // MARK: Spot search customization

    @ViewBuilder
    private var spotSearchButton: some View {
        Button {
            if let filter = selectedFilter {
                editingSpotSearchCategory = filter
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

    // MARK: Search radius label (read-only)

    /// Read-only label showing the current search distance setting.
    /// The interactive picker lives on My Flezcals — this just shows the value
    /// so users know the setting exists and what it's set to.
    @ViewBuilder
    private var searchRadiusLabel: some View {
        let miles = UserPicksService.radiusInMiles(picksService.searchRadiusDegrees)
        let km = UserPicksService.radiusInKm(picksService.searchRadiusDegrees)
        HStack(spacing: 6) {
            Image(systemName: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Searching within \(miles) mi / \(km) km")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Change in My Flezcals")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.top, 2)
    }

    // MARK: Community content

    private var communityContent: some View {
        Group {
            if !spotService.isLoading {
                Text("\(filteredAndSortedSpots.count) spot\(filteredAndSortedSpots.count == 1 ? "" : "s")\(searchText.isEmpty ? "" : " found")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            if spotService.isLoading {
                Spacer()
                ProgressView("Loading spots…")
                Spacer()
            } else if filteredAndSortedSpots.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No verified spots yet")
                        .font(.headline)
                    if searchText.isEmpty {
                        Text("Be the first to add a \(selectedFilter?.displayName.lowercased() ?? "flan or mezcal") spot!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        // Nudge to switch to Potential Spots
                        Button {
                            withAnimation { listMode = .explore }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.subheadline)
                                Text("Search Potential Spots")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)

                        Text("Potential Spots scans nearby menus to find places that might carry what you're looking for.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        Text("Try a different search term.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)
                .padding()
                Spacer()
            } else {
                List {
                    ForEach(filteredAndSortedSpots) { spot in
                        Button {
                            selectedSpot = spot
                        } label: {
                            ListTabRowView(spot: spot, userLocation: effectiveLocation)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    // Nudge to discover more spots via Potential Spots search
                    Button {
                        withAnimation { listMode = .explore }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Find more spots")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Search nearby menus for potential matches")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
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
    ListTabView(locationManager: LocationManager(), picksService: UserPicksService(), websiteChecker: WebsiteCheckService())
        .environmentObject(SpotService())
}
