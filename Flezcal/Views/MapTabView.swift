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
    /// Shared Flezcal filter state — synced with Spots tab via ContentView.
    @Binding var activePickIDs: Set<String>

    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var picksService: UserPicksService
    @StateObject private var suggestionService = SuggestionService()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedSpot: Spot?
    @State private var selectedSuggestion: SuggestedSpot?
    @State private var showListView = false
    @State private var searchText = ""
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
    /// Number of auto-fetches remaining on boot.  MapKit fires .onEnd once
    /// with a fallback region before the user's real location resolves, so
    /// we allow 2 auto-fetches to ensure ghost pins appear for the correct area.
    @State private var bootFetchesRemaining = 2
    /// Suppresses the next "Search This Area" button appearance.  Set true
    /// before an auto-zoom so the camera settle doesn't show the button.
    @State private var suppressSearchButton = false
    /// Pin-type visibility toggles — all on by default.
    @State private var showVerifiedPins = true
    @State private var showPossiblePins = true
    @State private var showUncheckedPins = true
    @State private var showNoPinsAlert = false
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
            let allPicks = picksService.picks
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
    private func zoomToFitPins() {
        var coordinates: [CLLocationCoordinate2D] = []

        // Ghost pins (yellow/green/gray) — the search results
        for suggestion in filteredSuggestions {
            coordinates.append(suggestion.coordinate)
        }
        // Show-on-Map pin if separate from suggestions
        if let pinned = showOnMapPin,
           !suggestionService.suggestions.contains(where: { $0.id == pinned.id }) {
            coordinates.append(pinned.coordinate)
        }

        guard coordinates.count >= 2 else { return }

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
    /// Always filters to only show spots whose categories overlap with the user's
    /// active picks — a pizza spot should never appear when only mezcal/flan/tacos are on.
    /// - No picks active → empty (all toggled off).
    private var filteredSpots: [Spot] {
        // When no picks are toggled on, show nothing
        guard !activePickIDs.isEmpty else { return [] }

        let all = spotService.filteredSpots(for: SpotFilter(category: nil))
        let base = all.filter { spot in
            spot.categories.contains { cat in activePickIDs.contains(cat.rawValue) }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { spot in
            spot.name.localizedCaseInsensitiveContains(searchText) ||
            spot.address.localizedCaseInsensitiveContains(searchText) ||
            (spot.mezcalOfferings ?? []).contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
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

    /// Ghost pins filtered to exclude any that share a name with a confirmed spot.
    /// Name-only matching avoids suppressing different restaurants that happen to
    /// be near each other — important in small towns where venues cluster.
    private var filteredSuggestions: [SuggestedSpot] {
        let spotNames = Set(spotService.spots.filter { !$0.isHidden && !$0.isClosed }.map { $0.name.lowercased() })
        return suggestionService.suggestions.filter { suggestion in
            !spotNames.contains(suggestion.name.lowercased())
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
    private var possibleSuggestions: [SuggestedSpot] {
        filteredSuggestions.filter { $0.preScreenMatches?.isEmpty == false }
    }

    /// Ghost pins not yet scanned or scanned with no match (yellow/gray).
    private var uncheckedSuggestions: [SuggestedSpot] {
        filteredSuggestions.filter { $0.preScreenMatches?.isEmpty != false }
    }

    /// Ghost pins filtered by pin-type toggles AND active pick IDs.
    /// When all Flezcal pills are off, no ghost pins show.
    /// Pre-filtered to avoid conditional `if` inside MapContentBuilder's ForEach.
    private var visibleGhostPins: [SuggestedSpot] {
        // If all Flezcal pills are toggled off, hide all ghost pins too
        guard !activePickIDs.isEmpty else { return [] }
        return filteredSuggestions.filter { suggestion in
            let isGreen = suggestion.preScreenMatches?.isEmpty == false
            return isGreen ? showPossiblePins : showUncheckedPins
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showListView {
                    listContent
                } else {
                    mapContent
                        .tutorialTarget("mapView")
                }
            }
            .navigationTitle(AppConstants.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { showListView.toggle() }
                    } label: {
                        Image(systemName: showListView ? "map" : "list.bullet")
                    }
                    .accessibilityLabel(showListView ? "Show map" : "Show list")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !showListView {
                        Button {
                            withAnimation {
                                cameraPosition = .userLocation(fallback: .automatic)
                            }
                        } label: {
                            Image(systemName: "location.fill")
                        }
                        .accessibilityLabel("Center on my location")
                    }
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

                guard shouldFetch(for: context.region.center) else { return }

                // Auto-fetch ghost pins while the map is still settling on
                // launch (bootFetchesRemaining > 0), then switch to the manual
                // "Search This Area" button.  We allow 2 auto-fetches because
                // MapKit fires .onEnd once with a fallback region before the
                // user's real location resolves, producing 0 or wrong-area
                // results.  The second settle (after location resolves) re-
                // fetches for the correct area so ghost pins appear on launch.
                if bootFetchesRemaining > 0 {
                    // Skip the fallback/default region — MapKit's first .onEnd
                    // often fires with a continent-scale span (e.g. 80°) centered
                    // far from the user. Burning 12+ MKLocalSearch queries against
                    // the wrong location wastes rate limit and returns junk results.
                    // Don't decrement bootFetchesRemaining so the real location
                    // still gets its auto-fetch.
                    if context.region.span.latitudeDelta > 5.0 {
                        #if DEBUG
                        print("[MapTab] Skipping boot fetch — fallback region span \(String(format: "%.1f", context.region.span.latitudeDelta))° is too wide")
                        #endif
                        return
                    }
                    bootFetchesRemaining -= 1
                    lastFetchedCenter = context.region.center
                    // Boot auto-fetch: ghost pins + pre-screen so green pins
                    // appear on launch, matching Explore tab behavior.
                    // Zoom to fit on the final boot fetch (after real location resolves)
                    // so the user sees all pins in their area.
                    let shouldZoom = bootFetchesRemaining == 0
                    fetchAndPreScreen(in: context.region, picks: activePicks, zoomToFit: shouldZoom)
                } else {
                    showSearchHereButton = true
                    showDeeperScanButton = false
                }
            }
            .onMapCameraChange { context in
                guard !initialRegionSeen else { return }
                visibleRegion = context.region
            }
            .onChange(of: activePickIDs) { _, newIDs in
                if newIDs.isEmpty {
                    showNoPinsAlert = true
                    return  // No picks active — skip fetch, pins are hidden
                }
                emptyStateDismissed = false
                showSearchHereButton = false
                bootFetchesRemaining = 0  // prevent boot auto-fetch from racing
                guard let region = visibleRegion else { return }
                lastFetchedCenter = region.center
                fetchAndPreScreen(in: region, picks: activePicks, zoomToFit: true)
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
            .onChange(of: picksService.searchRadiusDegrees) { _, newRadius in
                // User changed search radius — re-fetch with new radius and
                // update the camera to show the new search area.
                showSearchHereButton = false
                guard let region = visibleRegion else { return }
                lastFetchedCenter = region.center
                // Zoom the map to reflect the new radius
                let newRegion = MKCoordinateRegion(
                    center: region.center,
                    span: MKCoordinateSpan(latitudeDelta: newRadius,
                                           longitudeDelta: newRadius)
                )
                cameraPosition = .region(newRegion)
                bootFetchesRemaining = 0  // prevent auto-fetch duplicate
                fetchAndPreScreen(in: newRegion, picks: activePicks)
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

                // Center camera on the area using the user's chosen search radius
                let span = picksService.searchRadiusDegrees
                let region = MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                )
                cameraPosition = .region(region)
                lastFetchedCenter = center
                showSearchHereButton = false
                // Prevent onMapCameraChange from triggering a duplicate fetch
                // when the camera settles at the new position.
                bootFetchesRemaining = 0

                // Fetch ghost pins + pre-screen for this area
                fetchAndPreScreen(in: region, picks: activePicks, zoomToFit: true)
            }

            // Filter pills — one toggleable pill per pick
            VStack(spacing: 8) {
                PicksFilterBar(picks: picksService.picks,
                               activeIDs: $activePickIDs)
                    .tutorialTarget("filterPills")

                // Pin-type toggle buttons — tap to show/hide each category
                if !spotService.isLoading {
                    HStack(spacing: 6) {
                        PinToggleButton(
                            count: visibleSpots.count,
                            label: "Verified",
                            color: .green,
                            isOn: $showVerifiedPins
                        )

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

    // MARK: - List View

    private var listContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search spots...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 8)

            PicksFilterBar(picks: picksService.picks,
                           activeIDs: $activePickIDs)
                .padding(.top, 8)

            Text("\(filteredSpots.count) spot\(filteredSpots.count == 1 ? "" : "s") found")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            if spotService.isLoading {
                Spacer()
                ProgressView("Loading spots...")
                Spacer()
            } else if filteredSpots.isEmpty {
                Spacer()
                MapEmptyListState(
                    categoryName: activePicks.first?.displayName.lowercased() ?? "spot",
                    isSearchActive: !searchText.isEmpty
                )
                Spacer()
            } else {
                List(filteredSpots) { spot in
                    Button { selectedSpot = spot } label: {
                        SpotListRowView(spot: spot)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
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

// MARK: - Spot List Row

struct SpotListRowView: View {
    let spot: Spot
    var userLocation: CLLocationCoordinate2D? = nil

    var body: some View {
        HStack(spacing: 12) {
            SpotIcons(categories: spot.categories, size: 28)
                .frame(width: 44, height: 44)
                .background(spot.primaryCategory.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(cityName(from: spot.address))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let dist = formattedDistanceMiles(from: userLocation, to: spot.coordinate) {
                    Text(dist)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .fixedSize()
                }
                if let level = displayRatingLevel {
                    HStack(spacing: 2) {
                        Text(level.emoji)
                            .font(.caption2)
                        Text(level.label)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("New")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }
            }
            .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    /// Best category rating to display — first category with reviews
    private var bestCategoryRating: CategoryRating? {
        for cat in spot.categories {
            if let rating = spot.rating(for: cat), rating.count > 0 {
                return rating
            }
        }
        return nil
    }

    /// Rating level to display — prefers per-category, falls back to legacy aggregate
    private var displayRatingLevel: RatingLevel? {
        if let catRating = bestCategoryRating {
            return RatingLevel.from(max(1, min(5, Int(catRating.average.rounded()))))
        } else if spot.reviewCount > 0 {
            return RatingLevel.from(max(1, min(5, Int(spot.averageRating.rounded()))))
        }
        return nil
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

/// Centered empty state shown in the list view when no spots match.
private struct MapEmptyListState: View {
    let categoryName: String
    let isSearchActive: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No spots found")
                .font(.headline)
            Text(isSearchActive
                 ? "Try a different search term."
                 : "Be the first to add a \(categoryName) here!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .padding()
    }
}

#Preview {
    MapTabView(pendingMapSuggestion: .constant(nil),
               pendingMapCenter: .constant(nil),
               activePickIDs: .constant(Set(["mezcal", "flan", "tortillas"])),
               websiteChecker: WebsiteCheckService())
        .environmentObject(SpotService())
        .environmentObject(UserPicksService())
}
