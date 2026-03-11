import SwiftUI
@preconcurrency import MapKit
import CoreLocation

struct MapTabView: View {
    /// Set by ContentView when a .showOnMap notification arrives from the List tab.
    /// MapTabView picks it up, centers the camera, and opens the ghost pin sheet.
    @Binding var pendingMapSuggestion: SuggestedSpot?
    /// Set by ContentView when a .showAreaOnMap notification arrives from the List tab.
    /// MapTabView centers the camera on this coordinate and runs fetchAndPreScreen.
    @Binding var pendingMapCenter: CLLocationCoordinate2D?
    /// Pre-built results from the Spots tab — when non-nil, injected directly
    /// into suggestionService instead of running a fresh search.
    @Binding var pendingMapResults: [SuggestedSpot]?
    /// Shared Flezcal filter state — synced with Spots tab via ContentView.
    @Binding var activePickIDs: Set<String>
    /// Community Map mode — shows all verified spots, hides ghost pins.
    @Binding var showCommunityMap: Bool

    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var rankingService: RankingService
    @StateObject private var suggestionService = SuggestionService()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedSpot: Spot?
    @State private var selectedSuggestion: SuggestedSpot?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var emptyStateDismissed = false
    @State private var initialRegionSeen = false
    /// Center of the last region that actually triggered a fetch.
    /// Used to suppress no-op .onEnd firings during camera micro-settling.
    @State private var lastFetchedCenter: CLLocationCoordinate2D? = nil
    /// True when the map has moved enough to warrant a new ghost-pin fetch
    /// but the user hasn't tapped "Search This Area" yet.
    @State private var showSearchHereButton = false
    /// Ghost pin placed via "Show on Map" from Explore. Stored separately from
    /// selectedSuggestion so it persists after the sheet is dismissed.
    @State private var showOnMapPin: SuggestedSpot? = nil
    /// Auto-fetches on boot. MapKit fires .onEnd once with a fallback region
    /// before the user's real location resolves (skipped by the >5° guard),
    /// then again with the real location. Two ensures ghost pins appear.
    @State private var bootFetchesRemaining = 2
    /// Suppresses the next "Search This Area" button appearance.  Set true
    /// before an auto-zoom so the camera settle doesn't show the button.
    @State private var suppressSearchButton = false
    /// True when "Search This Area" appeared because the user toggled pills,
    /// not because they panned. When true, the button searches with the
    /// currently active picks instead of resetting to all-on.
    // Pill selections are user-controlled only — never reset programmatically.
    /// Pin-type visibility toggles — all on by default.
    @State private var showVerifiedPins = true
    @State private var showPossiblePins = true
    @State private var showUncheckedPins = true
    @State private var showNoPinsAlert = false
    /// Shows a sheet listing all current map pins in distance order.
    @State private var showPinList = false
    /// Worm easter egg — tapping the worm shows a prompt to enable Community Map.
    @State private var showCommunityEasterEgg = false
    /// Which categories to show in Community Map mode.
    @State private var communityMapFilter: CommunityMapFilter = .top50
    /// Set true when picks change while the map tab is off-screen.
    /// Triggers an auto-fetch when the user returns to the map.
    @State private var picksChangedWhileAway = false

    /// Deeper scan state — Wave 2 is deferred until the user taps "Do a Deeper Scan?"
    @State private var showDeeperScanButton = false
    @State private var deeperScanPool: [SuggestedSpot] = []
    @State private var deeperScanPicks: [FoodCategory] = []
    @State private var wave1Results: [String: Set<String>] = [:]

    // On-demand website check — runs when the user taps a ghost pin
    @State private var multiCheckResult: MultiCategoryCheckResult? = nil
    @State private var websiteCheckTask: Task<Void, Never>? = nil
    let websiteChecker: WebsiteCheckService

    /// Finds an existing Spot in Firestore that matches a SuggestedSpot.
    /// Used to route taps on ghost pins directly to SpotDetailView when
    /// the venue is already in the database.
    private func existingSpot(for suggestion: SuggestedSpot) -> Spot? {
        guard let coord = suggestion.mapItem.placemark.location?.coordinate,
              let name = suggestion.mapItem.name else { return nil }
        return spotService.findExistingSpot(
            name: name, latitude: coord.latitude, longitude: coord.longitude
        )
    }

    /// Handles tapping a ghost pin or show-on-map pin.
    /// If the venue already exists in Firestore, opens SpotDetailView directly.
    /// Otherwise opens SuggestedSpotSheet for the Add Spot / Add Flezcal flow.
    private func handleSuggestionTap(_ suggestion: SuggestedSpot) {
        // Shift camera so the pin sits 3/4 up the map, above the slide-up sheet.
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(
                cameraRegion(centeredAbove: suggestion.coordinate)
            )
        }

        // Check if this venue is already a confirmed spot
        if let existing = existingSpot(for: suggestion) {
            // Unhide if soft-deleted so the green verified pin shows
            if existing.isHidden {
                Task {
                    _ = await spotService.addCategories(
                        spotID: existing.id, newCategories: [], addedBy: nil
                    )
                }
            }
            // Remove the ghost pin since we're showing the real spot
            suggestionService.confirm(suggestion)
            // Open SpotDetailView — same experience as tapping a spot in the list
            selectedSpot = existing
        } else {
            // New venue — open SuggestedSpotSheet with website check
            websiteCheckTask?.cancel()
            multiCheckResult = nil
            selectedSuggestion = suggestion
            let primaryPick = bestPrimaryPick(for: suggestion)
            let allPicks = activePicks
            websiteCheckTask = Task {
                let result = await websiteChecker.checkAllPicks(
                    suggestion.mapItem,
                    picks: allPicks,
                    primaryPick: primaryPick
                )
                guard !Task.isCancelled else { return }
                multiCheckResult = result
            }
        }
    }

    // Batch fetch + pre-screen — homepage-only scan triggered after ghost pin fetch
    @State private var fetchAndPreScreenTask: Task<Void, Never>? = nil
    @State private var preScreenTask: Task<Void, Never>? = nil
    @State private var preScreenBannerMessage: String? = nil
    @State private var isPreScreening = false

    // MARK: - Helpers

    /// Shows alert when all pin toggles are turned off.
    private func checkAllPinsOff() {
        if !showVerifiedPins && !showPossiblePins && !showUncheckedPins {
            showNoPinsAlert = true
        }
    }

    /// The picks currently active for fetching / filtering.
    /// Only includes picks whose IDs are in activePickIDs.
    private var activePicks: [FoodCategory] {
        picksService.picks.filter { activePickIDs.contains($0.id) }
    }

    private typealias RegionBounds = (minLat: Double, maxLat: Double,
                                      minLon: Double, maxLon: Double)

    /// Shift factor: the pin's coordinate sits this fraction from the top of the
    /// visible map.  0.25 = 3/4 up the screen, leaving the bottom 3/4 for the sheet.
    private static let pinVerticalFraction: Double = 0.25

    /// Returns a camera region whose center is shifted south so that `coordinate`
    /// appears roughly 3/4 of the way up the visible map area.  The bottom quarter
    /// of the map is expected to be covered by the slide-up sheet.
    private func cameraRegion(centeredAbove coordinate: CLLocationCoordinate2D,
                              span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.01,
                                                                        longitudeDelta: 0.01)
    ) -> MKCoordinateRegion {
        // Move the center south by half the span minus the desired offset.
        // With fraction = 0.25, the pin sits 25% from the top → center shifts
        // south by 25% of the span height.
        let offset = span.latitudeDelta * Self.pinVerticalFraction
        let shifted = CLLocationCoordinate2D(
            latitude: coordinate.latitude - offset,
            longitude: coordinate.longitude
        )
        return MKCoordinateRegion(center: shifted, span: span)
    }

    /// Chooses the best primary pick for the full 3-pass website check.
    /// If the pin is green (pre-screen found matches), prefer one of the
    /// matched categories — that's what the user expects the check to verify.
    /// Falls back to suggestedCategory if no pre-screen data (yellow pins).
    private func bestPrimaryPick(for suggestion: SuggestedSpot) -> FoodCategory {
        guard let matches = suggestion.preScreenMatches, !matches.isEmpty else {
            return suggestion.suggestedCategory
        }
        // Prefer a matched category that's in the user's active picks
        if let pickMatch = picksService.picks.first(where: { matches.contains($0.id) }) {
            return pickMatch
        }
        // Fallback: first matched category from allScannable
        if let matchID = matches.first,
           let cat = FoodCategory.allScannable.first(where: { $0.id == matchID }) {
            return cat
        }
        return suggestion.suggestedCategory
    }

    private static let fetchMoveThresholdMeters: Double = 50

    private func shouldFetch(for newCenter: CLLocationCoordinate2D) -> Bool {
        guard let last = lastFetchedCenter else { return true }
        let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
        let b = CLLocation(latitude: newCenter.latitude, longitude: newCenter.longitude)
        return a.distance(from: b) >= Self.fetchMoveThresholdMeters
    }

    /// Zooms the map camera to fit all ghost pin suggestions with comfortable
    /// padding.  Only uses search-result pins (suggestions) — NOT confirmed
    /// spots, which may be far away and would zoom the map to continent scale.
    ///
    /// Pass `overridePins` to zoom to a specific set of coordinates (e.g.
    /// injected results from another tab) instead of the current suggestions.
    private func zoomToFitPins(overridePins: [CLLocationCoordinate2D]? = nil) {
        var coordinates: [CLLocationCoordinate2D] = []

        if let pins = overridePins {
            coordinates = pins
        } else {
            // Ghost pins (yellow/green/gray) — the search results
            for suggestion in filteredSuggestions {
                coordinates.append(suggestion.coordinate)
            }
            // Show-on-Map pin if separate from suggestions
            if let pinned = showOnMapPin,
               !suggestionService.suggestions.contains(where: { $0.id == pinned.id }) {
                coordinates.append(pinned.coordinate)
            }
        }

        guard !coordinates.isEmpty else { return }

        // Single pin: center on it with a comfortable zoom level
        if coordinates.count == 1 {
            let center = coordinates[0]
            suppressSearchButton = true
            lastFetchedCenter = center
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ))
            }
            return
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        for coord in coordinates.dropFirst() {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        // Add 20% padding so edge pins aren't clipped
        let latPad = max((maxLat - minLat) * 0.2, 0.005)
        let lonPad = max((maxLon - minLon) * 0.2, 0.005)

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) + latPad * 2,
            longitudeDelta: (maxLon - minLon) + lonPad * 2
        )
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        // Suppress the "Search This Area" button that would otherwise
        // appear when the camera settles at the new position, and update
        // lastFetchedCenter so shouldFetch returns false.
        suppressSearchButton = true
        lastFetchedCenter = center

        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    /// Fetches ghost pin suggestions then kicks off the batch homepage pre-screen.
    /// Call this everywhere that `fetchSuggestions` is called to ensure the
    /// pre-screen always follows.
    /// - Parameter zoomToFit: When true, auto-zooms the map to fit all pins after
    ///   suggestions load. Pass false for boot auto-fetches where the camera
    ///   should stay at the user's location.
    private func fetchAndPreScreen(in region: MKCoordinateRegion, picks: [FoodCategory], zoomToFit: Bool = false) {
        // Community Map mode — no ghost pin fetches needed
        guard !showCommunityMap else { return }
        // Cancel any in-flight fetch + pre-screen so a new call doesn't
        // race with the previous one and overwrite green pin results.
        fetchAndPreScreenTask?.cancel()
        preScreenTask?.cancel()
        showDeeperScanButton = false
        deeperScanPool = []

        fetchAndPreScreenTask = Task {
            #if DEBUG
            print("[MapTab] fetchAndPreScreen called with \(picks.count) picks, radius \(picksService.searchRadiusDegrees)")
            #endif
            await suggestionService.fetchSuggestions(
                in: region,
                existingSpots: spotService.spots,
                picks: picks,
                radius: picksService.searchRadiusDegrees
            )
            guard !Task.isCancelled else {
                isPreScreening = false
                return
            }

            // Instant pass: apply any cached pre-screen results immediately.
            // When the shared htmlCache already has results (e.g. from Explore tab),
            // green pins appear the moment ghost pins load — no waiting for fetches.
            let pool = suggestionService.fullPool
            let cachedResults = await websiteChecker.cachedPreScreen(
                suggestions: pool,
                picks: picks
            )
            if !cachedResults.isEmpty {
                suggestionService.applyPreScreenResults(cachedResults)
                #if DEBUG
                let greenCount = cachedResults.values.filter { !$0.isEmpty }.count
                print("[MapTab] Instant cache hit: \(greenCount) green out of \(cachedResults.count) cached")
                #endif
            }

            // Kick off Wave 1: scan the closest 25 venues (the displayed set)
            // so green pins appear fast. Wave 2 (remaining pool) is deferred
            // until the user taps "Do a Deeper Scan?".
            preScreenBannerMessage = nil
            suggestionService.preScreenComplete = false
            isPreScreening = true
            var poolToScan = suggestionService.fullPool
            // Include showOnMapPin in the pre-screen batch so it gets
            // scanned along with the other ghost pins.
            if let pinned = showOnMapPin,
               !poolToScan.contains(where: { $0.id == pinned.id }) {
                poolToScan.append(pinned)
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
                suggestionService.applyPreScreenResults(w1Results)
                if let pinned = showOnMapPin,
                   let matched = w1Results[pinned.id] {
                    showOnMapPin?.preScreenMatches = matched
                }
                #if DEBUG
                let w1Green = w1Results.values.filter { !$0.isEmpty }.count
                print("[PreScreen] Wave 1 done: \(w1Green) green out of \(wave1.count) closest venues")
                #endif

                isPreScreening = false

                // Zoom to fit the Wave 1 pin set so the user sees results.
                if zoomToFit {
                    zoomToFitPins()
                }

                // Show Wave 1 result banner
                let likelyCount = suggestionService.suggestions.filter {
                    $0.preScreenMatches?.isEmpty == false
                }.count
                let totalCount = suggestionService.suggestions.count
                #if DEBUG
                print("[PreScreen] Wave 1 complete. \(likelyCount) likely out of \(totalCount) suggestions. \(wave2.count) venues deferred.")
                #endif
                if totalCount > 0 {
                    if likelyCount == 0 {
                        preScreenBannerMessage = "No quick matches. Tap any pin to search deeper."
                    } else {
                        preScreenBannerMessage = "\(likelyCount) possible Flezcal spot\(likelyCount == 1 ? "" : "s"). Tap green pins to review."
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(8))
                        preScreenBannerMessage = nil
                    }
                }

                // Store Wave 2 pool for the "Do a Deeper Scan?" button.
                if !wave2.isEmpty {
                    wave1Results = w1Results
                    deeperScanPool = wave2
                    deeperScanPicks = picks
                    showDeeperScanButton = true
                }
            }
        }
    }

    /// Wave 2: runs only when the user taps "Do a Deeper Scan?".
    /// Scans the remaining pool beyond the closest 25 and promotes
    /// any green matches into the displayed set.
    private func runDeeperScan() {
        showDeeperScanButton = false
        preScreenTask?.cancel()
        preScreenBannerMessage = nil
        isPreScreening = true

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
            suggestionService.applyPreScreenResults(allResults)
            if let pinned = showOnMapPin,
               let matched = w2Results[pinned.id] {
                showOnMapPin?.preScreenMatches = matched
            }
            #if DEBUG
            let w2Green = w2Results.values.filter { !$0.isEmpty }.count
            print("[PreScreen] Wave 2 done: \(w2Green) green out of \(pool.count) remaining venues")
            #endif

            isPreScreening = false
            deeperScanPool = []

            // Zoom to fit the wider pin set (including promoted pins).
            zoomToFitPins()

            // Show final result banner
            let likelyCount = suggestionService.suggestions.filter {
                $0.preScreenMatches?.isEmpty == false
            }.count
            let totalCount = suggestionService.suggestions.count
            #if DEBUG
            print("[PreScreen] Deeper scan complete. \(likelyCount) likely out of \(totalCount) suggestions.")
            #endif
            if totalCount > 0 {
                if likelyCount == 0 {
                    preScreenBannerMessage = "No quick matches. Tap any pin to search deeper."
                } else {
                    preScreenBannerMessage = "\(likelyCount) possible Flezcal spot\(likelyCount == 1 ? "" : "s"). Tap green pins to review."
                }
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    preScreenBannerMessage = nil
                }
            }
        }
    }

    private func bounds(for region: MKCoordinateRegion) -> RegionBounds {
        (
            minLat: region.center.latitude  - region.span.latitudeDelta  / 2,
            maxLat: region.center.latitude  + region.span.latitudeDelta  / 2,
            minLon: region.center.longitude - region.span.longitudeDelta / 2,
            maxLon: region.center.longitude + region.span.longitudeDelta / 2
        )
    }

    /// Confirmed spots filtered by the active pick IDs (multi-toggle).
    /// In Community Map mode with `.top50` filter, returns only verified spots
    /// whose categories overlap with Top 50 rankings. With `.all`, returns all.
    /// In normal mode, filters to only spots whose categories overlap with the
    /// user's active picks. No picks active → empty (all toggled off).
    private var filteredSpots: [Spot] {
        let all = spotService.filteredSpots(for: SpotFilter(category: nil))

        // Community Map mode — show verified spots, optionally filtered by tier
        if showCommunityMap {
            switch communityMapFilter {
            case .top50:
                return all.filter { spot in
                    spot.categories.contains { cat in rankingService.isTop50(cat.rawValue) }
                }
            case .all:
                return all
            }
        }

        // Normal mode — filter by active picks
        guard !activePickIDs.isEmpty else { return [] }
        return all.filter { spot in
            spot.categories.contains { cat in activePickIDs.contains(cat.rawValue) }
        }
    }

    private var visibleSpots: [Spot] {
        guard let region = visibleRegion else { return filteredSpots }
        let b = bounds(for: region)
        return filteredSpots.filter { s in
            s.latitude  >= b.minLat && s.latitude  <= b.maxLat &&
            s.longitude >= b.minLon && s.longitude <= b.maxLon
        }
    }

    /// Ghost pins filtered to exclude any that share a name with a confirmed spot
    /// that's currently visible on the map (passes category filter). A ghost pin
    /// for "Havana Cafe" is only suppressed if a confirmed "Havana Cafe" would
    /// actually show — otherwise the user sees nothing for that venue.
    /// Name-only matching avoids suppressing different restaurants that happen to
    /// be near each other — important in small towns where venues cluster.
    private var filteredSuggestions: [SuggestedSpot] {
        let visibleSpotNames = Set(filteredSpots.map { $0.name.lowercased() })
        return suggestionService.suggestions.filter { suggestion in
            !visibleSpotNames.contains(suggestion.name.lowercased())
        }
    }

    private var visibleSuggestions: [SuggestedSpot] {
        guard let region = visibleRegion else { return suggestionService.suggestions }
        let b = bounds(for: region)
        return suggestionService.suggestions.filter { s in
            s.coordinate.latitude  >= b.minLat && s.coordinate.latitude  <= b.maxLat &&
            s.coordinate.longitude >= b.minLon && s.coordinate.longitude <= b.maxLon
        }
    }

    /// Ghost pins that matched on pre-screen (green — "possible Flezcal spots").
    /// Filtered by activePickIDs so the count matches what visibleGhostPins renders.
    /// A venue green for "cuban_food" shouldn't count when only "flan" is active.
    private var possibleSuggestions: [SuggestedSpot] {
        filteredSuggestions.filter { suggestion in
            guard let matches = suggestion.preScreenMatches, !matches.isEmpty else { return false }
            return !matches.isDisjoint(with: activePickIDs)
        }
    }

    /// Ghost pins not yet scanned or scanned with no match (yellow/gray).
    /// Filtered by activePickIDs so the count matches what visibleGhostPins renders.
    private var uncheckedSuggestions: [SuggestedSpot] {
        filteredSuggestions.filter { suggestion in
            let isGreen = suggestion.preScreenMatches?.isEmpty == false
            guard !isGreen else { return false }
            return activePickIDs.contains(suggestion.suggestedCategory.id)
        }
    }

    /// Ghost pins filtered by pin-type toggles AND active pick IDs.
    /// Hidden entirely in Community Map mode (only verified spots shown).
    /// When all Flezcal pills are off, no ghost pins show.
    /// Pre-filtered to avoid conditional `if` inside MapContentBuilder's ForEach.
    private var visibleGhostPins: [SuggestedSpot] {
        guard !showCommunityMap else { return [] }
        guard !activePickIDs.isEmpty else { return [] }
        return filteredSuggestions.filter { suggestion in
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
            return isGreen ? showPossiblePins : showUncheckedPins
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            mapContent
                .tutorialTarget("mapView")
            .navigationTitle(AppConstants.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            showPinList = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Show spots list")

                        // "Show on Spots tab" — switches to Spots tab with current results
                        Button {
                            let center = visibleRegion?.center
                                ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
                            let name = "Map Area"
                            var info: [String: Any] = [
                                "latitude": center.latitude,
                                "longitude": center.longitude,
                                "name": name
                            ]
                            let allSuggestions = suggestionService.suggestions
                            if !allSuggestions.isEmpty {
                                info["suggestions"] = allSuggestions
                            }
                            NotificationCenter.default.post(
                                name: .showSpotsAtLocation,
                                object: nil,
                                userInfo: info
                            )
                        } label: {
                            Image(systemName: "list.bullet.rectangle.fill")
                        }
                        .accessibilityLabel("Show on Spots tab")
                        .accessibilityHint("Switches to the Spots tab with the current map search results")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            cameraPosition = .userLocation(fallback: .automatic)
                        }
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    .accessibilityLabel("Center on my location")
                    Button {
                        Task { await spotService.fetchSpots() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh spots")
                }
            }
            .sheet(item: $selectedSpot) { spot in
                SpotDetailView(spot: spot)
            }
            .sheet(item: $selectedSuggestion) { suggestion in
                SuggestedSpotSheet(
                    suggestion: suggestion,
                    multiResult: multiCheckResult,
                    onConfirm: {
                        suggestionService.confirm(suggestion)
                        multiCheckResult = nil
                    },
                    onDismiss: {
                        suggestionService.dismiss(suggestion)
                        multiCheckResult = nil
                    },
                    userPicks: picksService.picks
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPinList) {
                MapPinListView(
                    suggestionService: suggestionService,
                    spotService: spotService,
                    activePickIDs: activePickIDs,
                    showVerifiedPins: showVerifiedPins,
                    showPossiblePins: showPossiblePins,
                    showUncheckedPins: showUncheckedPins,
                    showCommunityMap: showCommunityMap,
                    verifiedSpots: filteredSpots,
                    userLocation: visibleRegion?.center,
                    visibleRegion: visibleRegion,
                    onSelectSpot: { spot in
                        showPinList = false
                        selectedSpot = spot
                    },
                    onSelectSuggestion: { suggestion in
                        showPinList = false
                        handleSuggestionTap(suggestion)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .task {
                await spotService.fetchSpots()
            }
            .onAppear {
                if picksChangedWhileAway {
                    picksChangedWhileAway = false
                    // Picks were modified while the map was off-screen — fetch now
                    guard let region = visibleRegion else { return }
                    lastFetchedCenter = region.center
                    fetchAndPreScreen(in: region, picks: picksService.picks, zoomToFit: true)
                }
            }
            .onDisappear {
                websiteCheckTask?.cancel()
                websiteCheckTask = nil
                multiCheckResult = nil
            }
            .alert("No Flezcals selected", isPresented: $showNoPinsAlert) {
                Button("OK", role: .cancel) { }
            }
            .confirmationDialog("Easter Egg! 🐛", isPresented: $showCommunityEasterEgg, titleVisibility: .visible) {
                Button("Top 50 Flezcals") {
                    communityMapFilter = .top50
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCommunityMap = true
                    }
                }
                Button("All Verified Flezcals") {
                    communityMapFilter = .all
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCommunityMap = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Show verified Flezcal spots in your search area.")
            }
        }
    }

    // MARK: - Map View

    private var mapContent: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                // Verified community spots (green pins)
                if showVerifiedPins {
                    ForEach(filteredSpots) { spot in
                        Annotation(spot.name, coordinate: spot.coordinate) {
                            SpotPinView(spot: spot)
                                .onTapGesture { selectedSpot = spot }
                        }
                    }
                }

                // Ghost pins — unconfirmed Apple Maps suggestions
                // Green = pre-screen found keywords ("possible").
                // Yellow/gray = not yet scanned or no match ("unchecked").
                // Filtered to exclude any that overlap with a verified spot,
                // and respects pin-type toggle visibility.
                ForEach(visibleGhostPins) { suggestion in
                    let isGreen = suggestion.preScreenMatches?.isEmpty == false
                    let isScanned = suggestion.preScreenMatches != nil
                    Annotation(suggestion.name, coordinate: suggestion.coordinate) {
                        GhostPinView(
                            category: suggestion.suggestedCategory,
                            isLikely: isGreen,
                            isScanned: isScanned,
                            likelyCategories: (suggestion.preScreenMatches ?? [])
                                .compactMap { id in FoodCategory.allCategories.first { $0.id == id } }
                        )
                            .onTapGesture {
                                handleSuggestionTap(suggestion)
                            }
                    }
                }

                // Persistent ghost pin for venues sent from Explore "Show on Map".
                // Uses showOnMapPin (not selectedSuggestion) so it survives sheet dismissal.
                // Only shown when the venue isn't already in suggestionService.suggestions.
                if let pinned = showOnMapPin,
                   !suggestionService.suggestions.contains(where: { $0.id == pinned.id }) {
                    Annotation("", coordinate: pinned.coordinate) {
                        VStack(spacing: 0) {
                            GhostPinView(
                                category: pinned.suggestedCategory,
                                isLikely: pinned.preScreenMatches?.isEmpty == false,
                                isScanned: pinned.preScreenMatches != nil,
                                likelyCategories: (pinned.preScreenMatches ?? [])
                                    .compactMap { id in FoodCategory.allCategories.first { $0.id == id } }
                            )
                                .scaleEffect(1.3)
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(pinned.suggestedCategory.color.opacity(0.85))
                                .offset(y: -2)
                        }
                        .onTapGesture {
                            handleSuggestionTap(pinned)
                        }
                    }
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                initialRegionSeen = true

                // Consume suppress flag — auto-zoom moved the camera,
                // so don't show "Search This Area" for this settle.
                if suppressSearchButton {
                    suppressSearchButton = false
                    lastFetchedCenter = context.region.center
                    return
                }

                if bootFetchesRemaining > 0 {
                    // Skip MapKit's initial fallback region (continent-scale)
                    if context.region.span.latitudeDelta > 5.0 {
                        #if DEBUG
                        print("[MapTab] Skipping boot fetch — fallback region span \(String(format: "%.1f", context.region.span.latitudeDelta))° is too wide")
                        #endif
                        return
                    }
                    // Ignore micro-settles during boot (<50m)
                    guard shouldFetch(for: context.region.center) else { return }
                    bootFetchesRemaining -= 1
                    lastFetchedCenter = context.region.center
                    fetchAndPreScreen(in: context.region, picks: activePicks, zoomToFit: true)
                } else {
                    // User moved after boot — cancel stale searches so
                    // zoomToFitPins doesn't snap the camera back, and
                    // show the "Search This Area" button.
                    fetchAndPreScreenTask?.cancel()
                    preScreenTask?.cancel()
                    isPreScreening = false
                    showDeeperScanButton = false
                    showSearchHereButton = true
                }
            }
            .onMapCameraChange { context in
                guard !initialRegionSeen else { return }
                visibleRegion = context.region
            }
            .onChange(of: activePickIDs) { _, newIDs in
                if newIDs.isEmpty { showNoPinsAlert = true }
                emptyStateDismissed = false
                // After boot, prompt a re-search so results match the new filter.
                // visibleGhostPins hides non-matching pins immediately; the button
                // lets the user fetch fresh results for only the active categories.
                if bootFetchesRemaining == 0 {
                    showSearchHereButton = true
                }
            }
            .onChange(of: showVerifiedPins) { _, _ in checkAllPinsOff() }
            .onChange(of: showPossiblePins) { _, _ in checkAllPinsOff() }
            .onChange(of: showUncheckedPins) { _, _ in checkAllPinsOff() }
            .onChange(of: picksService.picks) { _, _ in
                // User changed their picks in My Flezcals tab — clear cache and re-fetch.
                // Cache must be cleared because it only contains scan results for the
                // previous picks, not the new ones.
                Task { await websiteChecker.clearHTMLCache() }
                // activePickIDs is reset by ContentView's onChange(of: picksService.picks)
                showSearchHereButton = false
                bootFetchesRemaining = 0  // prevent boot auto-fetch from racing
                guard let region = visibleRegion else {
                    // Map tab is off-screen — defer the fetch until the user returns
                    picksChangedWhileAway = true
                    return
                }
                lastFetchedCenter = region.center
                fetchAndPreScreen(in: region, picks: picksService.picks, zoomToFit: true)
            }
            .onChange(of: pendingMapSuggestion) { _, newValue in
                guard let suggestion = newValue else { return }
                pendingMapSuggestion = nil   // consume immediately

                showOnMapPin = suggestion  // persist pin after sheet dismissal
                handleSuggestionTap(suggestion)
            }
            .onChange(of: pendingMapCenter?.latitude) { _, _ in
                guard let center = pendingMapCenter else { return }
                pendingMapCenter = nil   // consume immediately
                let incomingResults = pendingMapResults
                pendingMapResults = nil

                lastFetchedCenter = center
                showSearchHereButton = false
                bootFetchesRemaining = 0

                if let results = incomingResults, !results.isEmpty {
                    // Injected from Spots tab — show these exact results, no fresh search.
                    // Cancel any in-flight fetch/pre-screen so they don't override our data.
                    fetchAndPreScreenTask?.cancel()
                    preScreenTask?.cancel()
                    isPreScreening = false
                    showDeeperScanButton = false

                    suggestionService.injectResults(results)
                    #if DEBUG
                    print("[MapTab] Injected \(results.count) results from Spots tab → filteredSuggestions=\(filteredSuggestions.count) visibleGhostPins=\(visibleGhostPins.count)")
                    for r in results.prefix(10) {
                        let isGreen = r.preScreenMatches?.isEmpty == false
                        print("[MapTab]   \(r.name): green=\(isGreen) preScreen=\(r.preScreenMatches ?? [])")
                    }
                    #endif

                    // Zoom to fit the injected green pins directly. We use the
                    // raw injected results' green-match coordinates instead of
                    // visibleGhostPins to avoid any timing issues with computed
                    // property recalculation and boot event races.
                    let greenCoords = results
                        .filter { $0.preScreenMatches?.isEmpty == false }
                        .map(\.coordinate)
                    let allCoords = results.map(\.coordinate)
                    let fallbackCenter = center
                    // Short delay so the zoom happens AFTER any queued boot .onEnd
                    // events, preventing a boot fetch from overriding the camera.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        suppressSearchButton = true
                        showSearchHereButton = false
                        if !greenCoords.isEmpty {
                            zoomToFitPins(overridePins: greenCoords)
                        } else if !allCoords.isEmpty {
                            zoomToFitPins(overridePins: allCoords)
                        } else {
                            zoomToFitPins(overridePins: [fallbackCenter])
                        }
                    }
                } else {
                    // No results provided — fresh fetch for this area
                    let span = picksService.searchRadiusDegrees
                    let region = MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                    )
                    cameraPosition = .region(region)
                    fetchAndPreScreen(in: region, picks: activePicks, zoomToFit: true)
                }
            }

            // Filter pills — one toggleable pill per pick
            VStack(spacing: 8) {
                PicksFilterBar(picks: picksService.picks,
                               activeIDs: $activePickIDs)
                    .tutorialTarget("filterPills")

                // Pin-type toggle buttons — tap to show/hide each category
                if !spotService.isLoading {
                    HStack(spacing: 6) {
                        // Worm easter egg — hidden Community Map trigger
                        CommunityWormButton(
                            showCommunityMap: $showCommunityMap,
                            showEasterEgg: $showCommunityEasterEgg
                        )

                        PinToggleButton(
                            count: visibleSpots.count,
                            label: "Verified",
                            color: .green,
                            isOn: $showVerifiedPins
                        )

                        // Hide Likely/Nearby toggles in Community Map mode
                        if !showCommunityMap {
                            if !possibleSuggestions.isEmpty {
                                PinToggleButton(
                                    count: possibleSuggestions.count,
                                    label: "Likely",
                                    color: .green,
                                    filled: false,
                                    isOn: $showPossiblePins
                                )
                            }

                            if !uncheckedSuggestions.isEmpty {
                                PinToggleButton(
                                    count: uncheckedSuggestions.count,
                                    label: "Nearby",
                                    color: .yellow,
                                    isOn: $showUncheckedPins
                                )
                            }
                        }
                    }
                    .tutorialTarget("pinToggles")
                }
            }
            .padding(.top, 8)

            // "Search This Area" / "Zoom in to search" — shown after the user pans/zooms.
            // maxSearchSpan prevents wasteful continent-scale searches that return
            // scattered results. 2.0° ≈ 140 miles — generous enough for metro areas.
            if showSearchHereButton {
                let tooWide = (visibleRegion?.span.latitudeDelta ?? 0) > 2.0
                VStack {
                    Spacer()
                    if tooWide {
                        Label("Zoom in to search", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .padding(.bottom, 24)
                    } else {
                        Button {
                            showSearchHereButton = false
                            // Always search with the user's current pill selection.
                            // Never reset pills — the user's explicit filter is sacred.
                            guard let region = visibleRegion else { return }
                            lastFetchedCenter = region.center
                            fetchAndPreScreen(in: region, picks: activePicks, zoomToFit: true)
                        } label: {
                            Label("Search This Area", systemImage: "magnifyingglass")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .padding(.bottom, 24)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: showSearchHereButton)
            }

            // "Do a Deeper Scan?" + result banner — stacked at the bottom.
            // The banner sits above the button so they don't overlap.
            if showDeeperScanButton && !showSearchHereButton || preScreenBannerMessage != nil {
                VStack(spacing: 8) {
                    Spacer()
                    if let message = preScreenBannerMessage {
                        Text(message)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                            .onTapGesture { preScreenBannerMessage = nil }
                            .transition(.opacity)
                    }
                    if showDeeperScanButton && !showSearchHereButton {
                        Button {
                            runDeeperScan()
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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.25), value: showDeeperScanButton)
                .animation(.easeInOut(duration: 0.3), value: preScreenBannerMessage)
            }

            // Ghost pin fetch indicator — shows while SuggestionService is
            // querying Apple Maps, before the pre-screen phase begins.
            if suggestionService.isLoading && !isPreScreening {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Finding nearby spots…")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .padding(.bottom, 24)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: suggestionService.isLoading)
            }

            // Pre-screen scanning indicator
            if isPreScreening {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning menus…")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .padding(.bottom, 24)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: isPreScreening)
            }

            // Loading overlay
            if spotService.isLoading {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading spots...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
            }

            // Error banner
            if let error = spotService.errorMessage {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.caption)
                            .lineLimit(2)
                        Spacer()
                        Button("Retry") {
                            Task { await spotService.fetchSpots() }
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
            }

            // Empty state — compact banner near top so it doesn't cover ghost pins.
            // Hidden when ghost pins (suggestions) or a "Show on Map" pin are visible,
            // since the user is intentionally viewing suggested venues.
            if !spotService.isLoading && spotService.errorMessage == nil
                && visibleSpots.isEmpty && visibleSuggestions.isEmpty
                && showOnMapPin == nil && !emptyStateDismissed {
                MapEmptyBanner(
                    category: activePicks.first ?? picksService.picks.first ?? .mezcal,
                    onSearch: {
                        NotificationCenter.default.post(name: .switchToSpots, object: nil)
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) { emptyStateDismissed = true }
                    }
                )
            }
        }
    }

}

// MARK: - Community Map Filter

/// Controls which verified spots appear in Community Map mode.
enum CommunityMapFilter {
    /// Show only spots with at least one Top 50 category.
    case top50
    /// Show all verified spots (Top 50 + Trending + custom).
    case all
}

// MARK: - Community Worm Button

/// Easter-egg worm button that toggles Community Map mode.
/// When active, shows a green circle background with a pulsing glow ring.
struct CommunityWormButton: View {
    @Binding var showCommunityMap: Bool
    @Binding var showEasterEgg: Bool
    @State private var isPulsing = false

    var body: some View {
        Button {
            if showCommunityMap {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCommunityMap = false
                }
            } else {
                showEasterEgg = true
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            Text("🐛")
                .font(.system(size: 16))
                .padding(6)
                .background(
                    Circle()
                        .fill(showCommunityMap ? Color.green.opacity(0.3) : .clear)
                )
                .background(
                    Circle()
                        .fill(Color.green.opacity(isPulsing ? 0.15 : 0))
                        .scaleEffect(isPulsing ? 1.6 : 1.0)
                )
        }
        .buttonStyle(.plain)
        .onChange(of: showCommunityMap) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }
}

// MARK: - Pin Toggle Button

/// Compact capsule button that toggles visibility of a pin type on the map.
/// Shows a colored dot, count, and label. Dimmed when toggled off.
struct PinToggleButton: View {
    let count: Int
    let label: String
    let color: Color
    /// When true the dot is a solid fill; when false it's a stroke ring
    /// (matching the ghost pin style for "Likely").
    var filled: Bool = true
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.toggle()
            }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if filled {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                    } else {
                        Circle()
                            .strokeBorder(color, lineWidth: 2)
                            .frame(width: 12, height: 12)
                    }
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                if !isOn {
                    Text("Filter off")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .opacity(isOn ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(label) pins, filter \(isOn ? "on" : "off")")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn ? "Tap to hide" : "Tap to show")
    }
}

// MARK: - Picks-based filter bar

/// Multi-toggle filter pill bar — each pill independently toggles visibility.
/// Used on both Map and Spots tabs with a shared `activeIDs` binding.
struct PicksFilterBar: View {
    let picks: [FoodCategory]
    @Binding var activeIDs: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(picks) { pick in
                    let isOn = activeIDs.contains(pick.id)
                    filterPill(label: pick.displayName, category: pick,
                               color: pick.color, isSelected: isOn) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isOn {
                                activeIDs.remove(pick.id)
                            } else {
                                activeIDs.insert(pick.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Filter pill

    @ViewBuilder
    private func filterPill(label: String, category: FoodCategory?, color: Color,
                             isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if let category { FoodCategoryIcon(category: category, size: 18) }
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                if !isSelected {
                    Text("Filter off")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Capsule().fill(isSelected ? color : Color(.systemBackground)))
            .foregroundStyle(isSelected ? .white : .primary)
            .overlay(Capsule().stroke(Color.secondary.opacity(0.3),
                                      lineWidth: isSelected ? 0 : 1))
            .opacity(isSelected ? 1.0 : 0.45)
        }
    }
}

// MARK: - Custom Map Pin

struct SpotPinView: View {
    let spot: Spot

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(spot.primaryCategory.color)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                SpotIcons(categories: spot.categories, size: 22)
            }
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(spot.primaryCategory.color)
                .offset(y: -3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spot.name), \(spot.categories.map(\.displayName).joined(separator: " and "))")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - SpotFilter (used by SpotService.filteredSpots)

struct SpotFilter: Equatable {
    let category: SpotCategory?
}

// MARK: - Map Empty States

/// Compact banner overlay shown on the map when no spots exist in the area.
private struct MapEmptyBanner: View {
    let category: FoodCategory
    let onSearch: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                FoodCategoryIcon(category: category, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No spots here yet")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Be the first to add a \(category.displayName.lowercased()) here!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss empty state")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("No spots here yet. Be the first to add a spot.")
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.top, 80)
    }
}

// MARK: - Map Pin List

/// Sheet showing the current map pins as a scrollable list, sorted by distance.
/// Observes suggestionService directly so pre-screen updates appear in real time
/// — true map↔list parity from the same live data source.
private struct MapPinListView: View {
    @ObservedObject var suggestionService: SuggestionService
    @ObservedObject var spotService: SpotService
    let activePickIDs: Set<String>
    let showVerifiedPins: Bool
    let showPossiblePins: Bool
    let showUncheckedPins: Bool
    let showCommunityMap: Bool
    let verifiedSpots: [Spot]
    let userLocation: CLLocationCoordinate2D?
    /// Current visible map region — used to cap the list to spots near the viewport.
    let visibleRegion: MKCoordinateRegion?
    let onSelectSpot: (Spot) -> Void
    let onSelectSuggestion: (SuggestedSpot) -> Void

    /// Same filtering logic as MapTabView.visibleGhostPins — single source of truth.
    /// Uses verifiedSpots (already filtered by activePickIDs) for name dedup,
    /// matching MapTabView.filteredSuggestions behavior exactly.
    private var ghostPins: [SuggestedSpot] {
        guard !showCommunityMap else { return [] }
        guard !activePickIDs.isEmpty else { return [] }
        let spotNames = Set(verifiedSpots.map { $0.name.lowercased() })
        let filtered = suggestionService.suggestions.filter { suggestion in
            !spotNames.contains(suggestion.name.lowercased())
        }
        return filtered.filter { suggestion in
            let isGreen = suggestion.preScreenMatches?.isEmpty == false
            let matchesCategory: Bool
            if isGreen, let matches = suggestion.preScreenMatches {
                matchesCategory = !matches.isDisjoint(with: activePickIDs)
            } else {
                matchesCategory = activePickIDs.contains(suggestion.suggestedCategory.id)
            }
            guard matchesCategory else { return false }
            return isGreen ? showPossiblePins : showUncheckedPins
        }
    }

    private enum ListItem: Identifiable {
        case verified(Spot)
        case ghost(SuggestedSpot)

        var id: String {
            switch self {
            case .verified(let spot): return "v_\(spot.id)"
            case .ghost(let pin): return "g_\(pin.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedItems.isEmpty {
                    Text("No spots in this area")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(sortedItems) { item in
                        switch item {
                        case .verified(let spot):
                            Button {
                                onSelectSpot(spot)
                            } label: {
                                ListTabRowView(spot: spot, userLocation: userLocation)
                            }
                            .buttonStyle(.plain)
                        case .ghost(let pin):
                            Button {
                                onSelectSuggestion(pin)
                            } label: {
                                ghostPinRow(pin)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Nearby Spots")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Verified spots capped to the map's search area so the list doesn't extend
    /// hundreds of miles beyond what's visible. Uses the farthest ghost pin as the
    /// boundary, with a 1.5× buffer. Falls back to the visible map region span.
    /// Returns empty when the Verified toggle is off.
    private var nearbyVerifiedSpots: [Spot] {
        guard showVerifiedPins else { return [] }
        guard let loc = userLocation else { return verifiedSpots }
        let ref = CLLocation(latitude: loc.latitude, longitude: loc.longitude)

        // Determine the distance cap from ghost pins or visible region
        let maxGhostDist = ghostPins.map { pin in
            ref.distance(from: CLLocation(
                latitude: pin.coordinate.latitude,
                longitude: pin.coordinate.longitude
            ))
        }.max()

        let cap: CLLocationDistance
        if let maxDist = maxGhostDist, maxDist > 0 {
            cap = maxDist * 1.5
        } else if let region = visibleRegion {
            // No ghost pins — use the visible map span
            cap = max(region.span.latitudeDelta, region.span.longitudeDelta) * 111_000
        } else {
            cap = 0.5 * 111_000  // default ~35 miles
        }

        return verifiedSpots.filter { spot in
            ref.distance(from: CLLocation(
                latitude: spot.latitude, longitude: spot.longitude
            )) <= cap
        }
    }

    private var sortedItems: [ListItem] {
        guard let loc = userLocation else {
            return nearbyVerifiedSpots.map { .verified($0) } + ghostPins.map { .ghost($0) }
        }
        let ref = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        var items: [ListItem] = nearbyVerifiedSpots.map { .verified($0) } + ghostPins.map { .ghost($0) }
        items.sort { a, b in
            func dist(_ item: ListItem) -> Double {
                switch item {
                case .verified(let spot):
                    return ref.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
                case .ghost(let pin):
                    return ref.distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
                }
            }
            return dist(a) < dist(b)
        }
        return items
    }

    private func ghostPinRow(_ pin: SuggestedSpot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Pin status icon
            let isGreen = pin.preScreenMatches?.isEmpty == false
            ZStack {
                Circle()
                    .fill(isGreen ? Color.green.opacity(0.15) : Color.yellow.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: isGreen ? "checkmark" : "questionmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isGreen ? .green : Color.yellow.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pin.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(pin.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(formattedDistanceMiles(from: userLocation, to: pin.coordinate) ?? "—")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                HStack(spacing: 4) {
                    FoodCategoryIcon(category: pin.suggestedCategory, size: 15)
                    Text(pin.suggestedCategory.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                    if isGreen {
                        Text("· Likely match")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MapTabView(pendingMapSuggestion: .constant(nil),
               pendingMapCenter: .constant(nil),
               pendingMapResults: .constant(nil),
               activePickIDs: .constant(Set(["mezcal", "flan", "tortillas"])),
               showCommunityMap: .constant(false),
               websiteChecker: WebsiteCheckService())
        .environmentObject(SpotService())
        .environmentObject(UserPicksService())
}
