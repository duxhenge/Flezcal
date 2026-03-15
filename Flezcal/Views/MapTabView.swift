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
    /// into searchResultStore instead of running a fresh search.
    @Binding var pendingMapResults: [SuggestedSpot]?
    /// One-shot picks override from Concierge — when non-nil, used instead of
    /// activePicks so trending/custom categories resolve correctly.
    @Binding var pendingMapPicks: [FoodCategory]?
    /// Shared Flezcal filter state — synced with Spots tab via ContentView.
    @Binding var activePickIDs: Set<String>
    /// Community Map mode — shows all verified spots, hides ghost pins.
    @Binding var showCommunityMap: Bool

    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var rankingService: RankingService
    @EnvironmentObject var searchResultStore: SearchResultStore
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
    /// Auto-fetches once on boot. MapKit fires .onEnd with a fallback region
    /// (continent-scale, skipped by the >5° guard) then again with the real
    /// user location — which triggers the one and only boot fetch.
    /// Set to 0 immediately after firing so tab switches can never re-trigger.
    @State private var bootFetchesRemaining = 1
    // Pill selections are user-controlled only — never reset programmatically.
    /// Pin-type visibility toggles — all on by default.
    @State private var showVerifiedPins = true
    @State private var showPossiblePins = true
    @State private var showUncheckedPins = true
    @State private var showNoPinsAlert = false
    /// Worm easter egg — tapping the worm shows a prompt to enable Community Map.
    @State private var showCommunityEasterEgg = false
    /// Which categories to show in Community Map mode.
    @State private var communityMapFilter: CommunityMapFilter = .top50
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
    /// If the venue already exists in Firestore, opens SpotDetailView and runs a
    /// website check for the current picks (ghost pin stays on the map and may turn green).
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
            // Open SpotDetailView — ghost pin STAYS on the map (no confirm() call).
            // The pin persists so the user can see it turn green if the check succeeds.
            selectedSpot = existing

            // Run website check for current picks against this existing spot.
            // If matches are found, update the ghost pin's preScreenMatches → green.
            websiteCheckTask?.cancel()
            let primaryPick = bestPrimaryPick(for: suggestion)
            let allPicks = activePicks
            let suggestionID = suggestion.id
            websiteCheckTask = Task {
                let result = await websiteChecker.checkAllPicks(
                    suggestion.mapItem,
                    picks: allPicks,
                    primaryPick: primaryPick
                )
                guard !Task.isCancelled else { return }
                let matchedCats = Set(result.confirmed.map(\.id))
                if !matchedCats.isEmpty {
                    searchResultStore.updatePreScreenMatches(
                        for: suggestionID, matches: matchedCats
                    )
                }
            }
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

    // MARK: - Helpers

    /// Shows alert when all pin toggles are turned off.
    private func checkAllPinsOff() {
        if !showVerifiedPins && !showPossiblePins && !showUncheckedPins {
            showNoPinsAlert = true
        }
    }

    /// The picks currently active for fetching / filtering.
    /// Resolves IDs from the user's picks first, then falls back to
    /// `allKnownCategories` so voice-injected categories (not in the
    /// user's 3 picks) still produce search results.
    private var activePicks: [FoodCategory] {
        let fromPicks = picksService.picks.filter { activePickIDs.contains($0.id) }
        let pickIDs = Set(fromPicks.map(\.id))
        let extraIDs = activePickIDs.subtracting(pickIDs)
        guard !extraIDs.isEmpty else { return fromPicks }
        // Check built-in + legacy categories first, then custom/trending picks
        let extras = FoodCategory.allKnownCategories.filter { extraIDs.contains($0.id) }
        let resolvedIDs = Set(extras.map(\.id))
        let stillMissing = extraIDs.subtracting(resolvedIDs)
        let customExtras = FoodCategory.activeCustomPicksSnapshot.filter { stillMissing.contains($0.id) }
        return fromPicks + extras + customExtras
    }

    /// The picks to show in the filter bar. Includes the user's normal picks
    /// plus any extra categories injected by Concierge or voice search so the
    /// user can see what's being searched (e.g. "Brisket" pill appears even if
    /// Brisket isn't in their My Flezcals list).
    private var displayPicks: [FoodCategory] {
        let userPicks = picksService.picks
        let userPickIDs = Set(userPicks.map(\.id))
        let extraIDs = activePickIDs.subtracting(userPickIDs)
        guard !extraIDs.isEmpty else { return userPicks }
        // Resolve the extra IDs into FoodCategory objects
        var extras: [FoodCategory] = []
        for id in extraIDs {
            if let cat = FoodCategory.allKnownCategories.first(where: { $0.id == id }) {
                extras.append(cat)
            } else if let cat = FoodCategory.activeCustomPicksSnapshot.first(where: { $0.id == id }) {
                extras.append(cat)
            }
        }
        return extras + userPicks
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
               !searchResultStore.suggestions.contains(where: { $0.id == pinned.id }) {
                coordinates.append(pinned.coordinate)
            }
        }

        guard !coordinates.isEmpty else { return }

        // Single pin: center on it with a comfortable zoom level
        if coordinates.count == 1 {
            let center = coordinates[0]
            lastFetchedCenter = center
            searchResultStore.lastFetchCenter = CLLocation(
                latitude: center.latitude, longitude: center.longitude
            )
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

        // Update lastFetchedCenter so shouldFetch returns false when the
        // camera settles at the new position — prevents "Search This Area"
        // from appearing after a programmatic zoom.
        lastFetchedCenter = center
        // Also sync the store's center so the redundant-fetch guard sees the
        // zoom-to-fit position, not just the original search origin. This prevents
        // tab-switch .onEnd fires from bypassing the 500m guard.
        searchResultStore.lastFetchCenter = CLLocation(
            latitude: center.latitude, longitude: center.longitude
        )

        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    /// Convenience wrapper — delegates to the store, passing map-specific extras
    /// (showOnMapPin, communityMap guard) and wiring the zoom + pre-screen callbacks.
    private func fetchAndPreScreen(in region: MKCoordinateRegion, picks: [FoodCategory], zoomToFit: Bool = false, caller: String = "unknown") {
        // Community Map mode — no ghost pin fetches needed
        guard !showCommunityMap else { return }
        #if DEBUG
        print("[MapTab] fetchAndPreScreen called by: \(caller) bootRemaining=\(bootFetchesRemaining)")
        #endif
        showSearchHereButton = false
        // Boot is complete once any fetch starts. Prevents tab-switch .onEnd
        // fires from re-entering the boot branch and triggering phantom searches.
        bootFetchesRemaining = 0

        var extras: [SuggestedSpot] = []
        if let pinned = showOnMapPin { extras.append(pinned) }

        searchResultStore.fetchAndPreScreen(
            in: region,
            picks: picks,
            existingSpots: spotService.spots,
            radius: picksService.searchRadiusDegrees,
            websiteChecker: websiteChecker,
            extraSuggestions: extras,
            zoomToFit: zoomToFit
        )
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

    /// Lowercased names of confirmed spots that pass the current category filter.
    /// Used by the store's filtering methods to suppress ghost pins that duplicate a confirmed spot.
    private var existingSpotNames: Set<String> {
        Set(filteredSpots.map { $0.name.lowercased() })
    }

    /// Ghost pins filtered to exclude any that share a name with a confirmed spot.
    /// Delegates to SearchResultStore for the canonical implementation.
    private var filteredSuggestions: [SuggestedSpot] {
        searchResultStore.filteredSuggestions(existingSpotNames: existingSpotNames)
    }

    private var visibleSuggestions: [SuggestedSpot] {
        guard let region = visibleRegion else { return searchResultStore.suggestions }
        let b = bounds(for: region)
        return searchResultStore.suggestions.filter { s in
            s.coordinate.latitude  >= b.minLat && s.coordinate.latitude  <= b.maxLat &&
            s.coordinate.longitude >= b.minLon && s.coordinate.longitude <= b.maxLon
        }
    }

    /// Ghost pins that matched on pre-screen (green — "possible Flezcal spots").
    /// Delegates to SearchResultStore.splitByPreScreen for the canonical implementation.
    private var possibleSuggestions: [SuggestedSpot] {
        searchResultStore.splitByPreScreen(activePickIDs: activePickIDs, existingSpotNames: existingSpotNames).matched
    }

    /// Ghost pins not yet scanned or scanned with no match (yellow/gray).
    /// Further filtered by activePickIDs so the count matches visibleGhostPins.
    private var uncheckedSuggestions: [SuggestedSpot] {
        searchResultStore.splitByPreScreen(activePickIDs: activePickIDs, existingSpotNames: existingSpotNames).other
            .filter { activePickIDs.contains($0.suggestedCategory.id) }
    }

    /// Ghost pins filtered by pin-type toggles AND active pick IDs.
    /// Delegates to SearchResultStore.visiblePins for the canonical implementation.
    private var visibleGhostPins: [SuggestedSpot] {
        searchResultStore.visiblePins(
            activePickIDs: activePickIDs,
            existingSpotNames: existingSpotNames,
            showLikely: showPossiblePins,
            showUnchecked: showUncheckedPins,
            showCommunityMap: showCommunityMap
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            mapContent
                .tutorialTarget("mapView")
            .navigationTitle(AppConstants.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // "Show on Spots tab" — switches to the Spots tab with current map area.
                // The old pin list sheet was removed — both tabs now share SearchResultStore
                // so the Spots tab shows the same results with full search/filter UX.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        let center = visibleRegion?.center
                            ?? CLLocationCoordinate2D(latitude: 42.3876, longitude: -71.0995)
                        let name = "Map Area"
                        var info: [String: Any] = [
                            "latitude": center.latitude,
                            "longitude": center.longitude,
                            "name": name
                        ]
                        let allSuggestions = searchResultStore.suggestions
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
                        searchResultStore.confirm(suggestion)
                        multiCheckResult = nil
                    },
                    onDismiss: {
                        searchResultStore.dismiss(suggestion)
                        multiCheckResult = nil
                    },
                    userPicks: picksService.picks
                )
                .presentationDetents([.medium, .large])
            }
            .task {
                await spotService.fetchSpots()
            }
            .onAppear {
                // Consume any pending zoom that was set while the Map tab was off-screen
                // (e.g. Wave 2 completed on the Spots tab). The .onChange observers missed
                // the transition because the view wasn't active, so catch it here.
                if searchResultStore.pendingZoomToFit, searchResultStore.preScreenComplete {
                    searchResultStore.pendingZoomToFit = false
                    zoomToFitPins()
                }
            }
            .onDisappear {
                websiteCheckTask?.cancel()
                websiteCheckTask = nil
                multiCheckResult = nil
            }
            .alert("No \(AppBranding.namePlural) selected", isPresented: $showNoPinsAlert) {
                Button("OK", role: .cancel) { }
            }
            .confirmationDialog("Easter Egg! 🐛", isPresented: $showCommunityEasterEgg, titleVisibility: .visible) {
                Button("Top 50 \(AppBranding.namePlural)") {
                    communityMapFilter = .top50
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCommunityMap = true
                    }
                }
                Button("All Verified \(AppBranding.namePlural)") {
                    communityMapFilter = .all
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCommunityMap = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Show verified \(AppBranding.name) spots in your search area.")
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
                // Green = website confirmed keywords for user's picks.
                // Yellow = plausible venue, unconfirmed.
                // Filtered to exclude any that overlap with a verified spot,
                // and respects pin-type toggle visibility.
                ForEach(visibleGhostPins) { suggestion in
                    let isGreen = suggestion.preScreenMatches?.isEmpty == false
                    Annotation(suggestion.name, coordinate: suggestion.coordinate) {
                        GhostPinView(
                            category: suggestion.suggestedCategory,
                            isLikely: isGreen,
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
                // Only shown when the venue isn't already in searchResultStore.suggestions.
                if let pinned = showOnMapPin,
                   !searchResultStore.suggestions.contains(where: { $0.id == pinned.id }) {
                    let pinnedIsGreen = pinned.preScreenMatches?.isEmpty == false
                    Annotation("", coordinate: pinned.coordinate) {
                        VStack(spacing: 0) {
                            GhostPinView(
                                category: pinned.suggestedCategory,
                                isLikely: pinnedIsGreen,
                                likelyCategories: (pinned.preScreenMatches ?? [])
                                    .compactMap { id in FoodCategory.allCategories.first { $0.id == id } }
                            )
                                .scaleEffect(1.3)
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(
                                    pinnedIsGreen
                                        ? Color.green.opacity(0.85)
                                        : Color.yellow
                                )
                                .offset(y: -2)
                        }
                        .onTapGesture {
                            handleSuggestionTap(pinned)
                        }
                    }
                }
            }
            // ── SEARCH STABILITY CONTRACT — PROTECTED ──────────────────
            // .onEnd fires on EVERY camera settle including tab switches.
            // After boot (bootFetchesRemaining == 0), .onEnd must ONLY show
            // the "Search This Area" button — NEVER call fetchAndPreScreen.
            // See SearchResultStore.fetchAndPreScreen doc for the full contract.
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                initialRegionSeen = true

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
                    // Set to 0 immediately — one boot fetch is all we need.
                    // The store's redundant-fetch guard handles duplicates.
                    // MUST be 0 before the fetch so tab-switch .onEnd can never re-trigger.
                    bootFetchesRemaining = 0
                    lastFetchedCenter = context.region.center
                    fetchAndPreScreen(in: context.region, picks: activePicks, zoomToFit: true, caller: "boot.onEnd")
                } else {
                    // User panned/zoomed after boot — show "Search This Area" button.
                    // NEVER cancel store tasks or wipe deeper scan state here.
                    // The store owns its own task lifecycle; camera events are irrelevant.
                    guard shouldFetch(for: context.region.center) else { return }
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
            .onChange(of: searchResultStore.preScreenComplete) { _, complete in
                guard complete else { return }
                // Zoom to fit pins after Wave 1 or Wave 2 completes, if requested
                if searchResultStore.pendingZoomToFit {
                    searchResultStore.pendingZoomToFit = false
                    zoomToFitPins()
                }
                // Update showOnMapPin's pre-screen matches from the store
                if let pinned = showOnMapPin,
                   let poolMatch = searchResultStore.fullPool.first(where: { $0.id == pinned.id }),
                   let matches = poolMatch.preScreenMatches {
                    showOnMapPin?.preScreenMatches = matches
                }
            }
            .onChange(of: searchResultStore.pendingZoomToFit) { _, pending in
                // Handles the case where the redundant-fetch guard skipped
                // a new fetch but the caller requested zoom-to-fit.
                // The data is already in the store, so zoom immediately.
                guard pending, searchResultStore.preScreenComplete else { return }
                searchResultStore.pendingZoomToFit = false
                zoomToFitPins()
            }
            .onChange(of: showVerifiedPins) { _, _ in checkAllPinsOff() }
            .onChange(of: showPossiblePins) { _, _ in checkAllPinsOff() }
            .onChange(of: showUncheckedPins) { _, _ in checkAllPinsOff() }
            .onChange(of: picksService.picks) { _, _ in
                // User changed their picks — clear cache so a future search uses
                // the new picks' keywords. Don't auto-fetch; show the button instead
                // so the user controls when a new search runs.
                Task { await websiteChecker.clearHTMLCache() }
                bootFetchesRemaining = 0
                emptyStateDismissed = false
                showSearchHereButton = true
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
                // One-shot picks override from Concierge — use these instead
                // of activePicks so trending/custom categories resolve correctly.
                let overridePicks = pendingMapPicks
                pendingMapPicks = nil

                lastFetchedCenter = center
                showSearchHereButton = false
                bootFetchesRemaining = 0
                // Clear any pending zoom from a boot fetch so it doesn't
                // overwrite the camera position we're about to set.
                searchResultStore.pendingZoomToFit = false

                if let results = incomingResults, !results.isEmpty {
                    // Injected from Spots tab — show these exact results, no fresh search.
                    searchResultStore.cancelInFlight()
                    // Clear any stale "Show on Map" pin so it doesn't overlap
                    // with the same venue in the injected results.
                    showOnMapPin = nil

                    searchResultStore.injectResults(results)
                    #if DEBUG
                    print("[MapTab] Injected \(results.count) results from Spots tab → filteredSuggestions=\(filteredSuggestions.count) visibleGhostPins=\(visibleGhostPins.count)")
                    for r in results.prefix(10) {
                        let isGreen = r.preScreenMatches?.isEmpty == false
                        print("[MapTab]   \(r.name): green=\(isGreen) preScreen=\(r.preScreenMatches ?? [])")
                    }
                    #endif

                    // Zoom to fit the injected green pins.
                    let greenCoords = results
                        .filter { $0.preScreenMatches?.isEmpty == false }
                        .map(\.coordinate)
                    let allCoords = results.map(\.coordinate)
                    let fallbackCenter = center
                    if !greenCoords.isEmpty {
                        zoomToFitPins(overridePins: greenCoords)
                    } else if !allCoords.isEmpty {
                        zoomToFitPins(overridePins: allCoords)
                    } else {
                        zoomToFitPins(overridePins: [fallbackCenter])
                    }
                } else if overridePicks != nil {
                    // Concierge or explicit location change — user requested a search
                    // at a new area with specific picks. This is the only case where
                    // the pendingMapCenter handler should trigger a fresh fetch.
                    let picks = overridePicks!
                    let span = picksService.searchRadiusDegrees
                    let region = MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                    )
                    cameraPosition = .region(region)
                    searchResultStore.cancelInFlight()
                    fetchAndPreScreen(in: region, picks: picks, zoomToFit: true, caller: "pendingMapCenter.concierge")
                } else {
                    // Normal "Show on Map" from Spots tab — store already has the data.
                    // Just center the camera and zoom to fit existing pins. No fetch.
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: center,
                        distance: 50000  // ~50km view
                    ))
                    if !searchResultStore.suggestions.isEmpty {
                        zoomToFitPins()
                    }
                }
            }

            // Filter pills — one toggleable pill per pick
            VStack(spacing: 8) {
                PicksFilterBar(picks: displayPicks,
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
                            // Explicit user action — clear the redundant-fetch guard
                            // so the store always runs a fresh search.
                            searchResultStore.cancelInFlight()
                            fetchAndPreScreen(in: region, picks: activePicks, zoomToFit: true, caller: "searchThisAreaButton")
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

            // "Search Wider Area?" + result banner — stacked at the bottom.
            // The banner sits above the button so they don't overlap.
            if searchResultStore.showDeeperScanButton && !showSearchHereButton || searchResultStore.preScreenBannerMessage != nil {
                VStack(spacing: 8) {
                    Spacer()
                    if let message = searchResultStore.preScreenBannerMessage {
                        Text(message)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                            .onTapGesture { searchResultStore.preScreenBannerMessage = nil }
                            .transition(.opacity)
                    }
                    if searchResultStore.showDeeperScanButton && !showSearchHereButton {
                        Button {
                            searchResultStore.runDeeperScan(websiteChecker: websiteChecker)
                        } label: {
                            Label("Scan More Spots?", systemImage: "magnifyingglass")
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
                .animation(.easeInOut(duration: 0.25), value: searchResultStore.showDeeperScanButton)
                .animation(.easeInOut(duration: 0.3), value: searchResultStore.preScreenBannerMessage)
            }

            // Ghost pin fetch indicator — shows while SearchResultStore is
            // querying Apple Maps, before the pre-screen phase begins.
            if searchResultStore.isLoading && !searchResultStore.isPreScreening {
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
                .animation(.easeInOut(duration: 0.25), value: searchResultStore.isLoading)
            }

            // Pre-screen scanning indicator
            if searchResultStore.isPreScreening {
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
                .animation(.easeInOut(duration: 0.25), value: searchResultStore.isPreScreening)
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
            .frame(minWidth: UIScreen.main.bounds.width)
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

#Preview {
    MapTabView(pendingMapSuggestion: .constant(nil),
               pendingMapCenter: .constant(nil),
               pendingMapResults: .constant(nil),
               pendingMapPicks: .constant(nil),
               activePickIDs: .constant(Set(["mezcal", "flan", "tacos"])),
               showCommunityMap: .constant(false),
               websiteChecker: WebsiteCheckService())
        .environmentObject(SpotService())
        .environmentObject(UserPicksService())
        .environmentObject(SearchResultStore())
}
