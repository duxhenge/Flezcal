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

    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var picksService: UserPicksService
    @StateObject private var suggestionService = SuggestionService()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    /// nil = "All picks"; non-nil = single pick filter active
    @State private var selectedPickFilter: FoodCategory? = nil
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

    /// The picks currently active for fetching / filtering.
    /// nil selectedPickFilter = use all picks.
    private var activePicks: [FoodCategory] {
        if let pick = selectedPickFilter { return [pick] }
        return picksService.picks
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

    /// Fetches ghost pin suggestions then kicks off the batch homepage pre-screen.
    /// Call this everywhere that `fetchSuggestions` is called to ensure the
    /// pre-screen always follows.
    private func fetchAndPreScreen(in region: MKCoordinateRegion, picks: [FoodCategory]) {
        // Cancel any in-flight fetch + pre-screen so a new call doesn't
        // race with the previous one and overwrite green pin results.
        fetchAndPreScreenTask?.cancel()
        preScreenTask?.cancel()

        fetchAndPreScreenTask = Task {
            #if DEBUG
            print("[MapTab] fetchAndPreScreen called with \(picks.count) picks")
            #endif
            await suggestionService.fetchSuggestions(
                in: region,
                existingSpots: spotService.spots,
                picks: picks
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

            // Kick off batch homepage pre-screen after pins appear.
            // Pre-screen the FULL pool (not just displayed 25) so that
            // venues beyond the 25th closest can be promoted if they match.
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
                let results = await websiteChecker.batchPreScreen(
                    suggestions: poolToScan,
                    picks: picks
                )
                guard !Task.isCancelled else {
                    isPreScreening = false
                    return
                }
                suggestionService.applyPreScreenResults(results)
                // Update showOnMapPin's pre-screen status if it was scanned
                if let pinned = showOnMapPin,
                   let matched = results[pinned.id] {
                    showOnMapPin?.preScreenMatches = matched
                }
                isPreScreening = false
                // Show "no quick matches" banner if zero green pins
                let likelyCount = suggestionService.suggestions.filter {
                    $0.preScreenMatches?.isEmpty == false
                }.count
                let totalCount = suggestionService.suggestions.count
                #if DEBUG
                print("[PreScreen] Done. \(likelyCount) likely out of \(totalCount) suggestions.")
                #endif
                if totalCount > 0 {
                    if likelyCount == 0 {
                        preScreenBannerMessage = "No quick matches — tap any pin to search deeper"
                    } else {
                        preScreenBannerMessage = "\(likelyCount) likely match\(likelyCount == 1 ? "" : "es") — tap green pins to review"
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(8))
                        preScreenBannerMessage = nil
                    }
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

    /// Confirmed spots filtered by the active pick filter.
    /// Bridges FoodCategory → SpotFilter so SpotService.filteredSpots(for:) can be reused.
    /// For picks whose id doesn't match a SpotCategory (e.g. "ramen"), shows all spots.
    private var filteredSpots: [Spot] {
        let spotCat: SpotCategory? = selectedPickFilter.flatMap { SpotCategory(rawValue: $0.id) }
        let filter = SpotFilter(category: spotCat)
        let base = spotService.filteredSpots(for: filter)
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
            let dominated = spotNames.contains(suggestion.name.lowercased())
            #if DEBUG
            if dominated {
                print("[FilteredSuggestions] Hiding ghost pin \"\(suggestion.name)\" — matches confirmed spot name")
            }
            #endif
            return !dominated
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showListView {
                    listContent
                } else {
                    mapContent
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
            .onDisappear {
                websiteCheckTask?.cancel()
                websiteCheckTask = nil
                multiCheckResult = nil
            }
        }
    }

    // MARK: - Map View

    private var mapContent: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                ForEach(filteredSpots) { spot in
                    Annotation(spot.name, coordinate: spot.coordinate) {
                        SpotPinView(spot: spot)
                            .onTapGesture { selectedSpot = spot }
                    }
                }

                // Ghost pins — unconfirmed Apple Maps suggestions
                // Yellow = not yet scanned. Green = pre-screen found keywords.
                // Gray = scanned but no match found.
                // Filtered to exclude any that overlap with a verified spot.
                ForEach(filteredSuggestions) { suggestion in
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

                guard shouldFetch(for: context.region.center) else { return }

                // Auto-fetch ghost pins while the map is still settling on
                // launch (bootFetchesRemaining > 0), then switch to the manual
                // "Search This Area" button.  We allow 2 auto-fetches because
                // MapKit fires .onEnd once with a fallback region before the
                // user's real location resolves, producing 0 or wrong-area
                // results.  The second settle (after location resolves) re-
                // fetches for the correct area so ghost pins appear on launch.
                if bootFetchesRemaining > 0 {
                    bootFetchesRemaining -= 1
                    lastFetchedCenter = context.region.center
                    // Boot auto-fetch: ghost pins + pre-screen so green pins
                    // appear on launch, matching Explore tab behavior.
                    fetchAndPreScreen(in: context.region, picks: activePicks)
                } else {
                    showSearchHereButton = true
                }
            }
            .onMapCameraChange { context in
                guard !initialRegionSeen else { return }
                visibleRegion = context.region
            }
            .onChange(of: selectedPickFilter) { _, _ in
                emptyStateDismissed = false
                showSearchHereButton = false
                guard let region = visibleRegion else { return }
                lastFetchedCenter = region.center
                fetchAndPreScreen(in: region, picks: activePicks)
            }
            .onChange(of: picksService.picks) { _, _ in
                // User changed their picks in My Flezcals tab — re-fetch with new picks
                selectedPickFilter = nil   // reset to "All" when picks change
                showSearchHereButton = false
                guard let region = visibleRegion else { return }
                lastFetchedCenter = region.center
                fetchAndPreScreen(in: region, picks: picksService.picks)
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

                // Center camera on the area with a neighborhood-level zoom
                let region = MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                cameraPosition = .region(region)
                lastFetchedCenter = center
                showSearchHereButton = false
                // Prevent onMapCameraChange from triggering a duplicate fetch
                // when the camera settles at the new position.
                bootFetchesRemaining = 0

                // Fetch ghost pins + pre-screen for this area
                fetchAndPreScreen(in: region, picks: activePicks)
            }

            // Filter pills — "All" + one pill per pick
            VStack(spacing: 8) {
                PicksFilterBar(picks: picksService.picks,
                               selectedPick: $selectedPickFilter)

                // Spot count + suggestion count badges
                if !spotService.isLoading {
                    HStack(spacing: 6) {
                        Text("\(visibleSpots.count) spot\(visibleSpots.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                        if !visibleSuggestions.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                                Text("\(visibleSuggestions.count) suggested")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                        }
                    }
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
                            fetchAndPreScreen(in: region, picks: activePicks)
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

            // Pre-screen results banner — appears after batch scan completes.
            // Positioned at bottom (same area as the spinner) so it's a natural
            // visual transition: spinner disappears → banner appears.
            if let message = preScreenBannerMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        .onTapGesture { preScreenBannerMessage = nil }
                }
                .padding(.bottom, 24)
                .transition(.opacity)
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
                    category: selectedPickFilter ?? picksService.picks.first ?? .mezcal,
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
                           selectedPick: $selectedPickFilter)
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
                    categoryName: selectedPickFilter?.displayName.lowercased() ?? "spot",
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

// MARK: - Picks-based filter bar

/// Replaces the old SpotCategory-based CategoryFilterBar.
/// Shows "All" + one pill per user pick.
struct PicksFilterBar: View {
    let picks: [FoodCategory]
    @Binding var selectedPick: FoodCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" pill
                filterPill(label: "All", category: nil, color: .orange, isSelected: selectedPick == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPick = nil }
                }

                // One pill per pick
                ForEach(picks) { pick in
                    filterPill(label: pick.displayName, category: pick,
                                color: pick.color, isSelected: selectedPick == pick) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPick = (selectedPick == pick) ? nil : pick
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
            HStack(spacing: 4) {
                if let category { FoodCategoryIcon(category: category, size: 18) }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(isSelected ? color : Color(.systemBackground)))
            .foregroundStyle(isSelected ? .white : .primary)
            .overlay(Capsule().stroke(Color.secondary.opacity(0.3),
                                      lineWidth: isSelected ? 0 : 1))
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

// MARK: - Legacy SpotFilter (kept for compatibility with ListTabView)
// SpotFilter is still used by ListTabView's confirmed-spot filtering.
// New FoodCategory-based filtering uses PicksFilterBar above.

struct SpotFilter: Equatable {
    let category: SpotCategory?
    static let all = SpotFilter(category: nil)
    static var allFilters: [SpotFilter] {
        [.all] + SpotCategory.allCases.map { SpotFilter(category: $0) }
    }
    var displayName: String { category?.displayName ?? "All" }
    var color: Color { category?.color ?? .orange }
}

struct CategoryFilterBar: View {
    @Binding var selectedFilter: SpotFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpotFilter.allFilters, id: \.displayName) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = filter }
                    } label: {
                        HStack(spacing: 4) {
                            if let cat = filter.category {
                                CategoryIcon(category: cat, size: 16)
                            }
                            Text(filter.displayName)
                                .font(.subheadline)
                                .fontWeight(selectedFilter == filter ? .semibold : .regular)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(selectedFilter == filter
                                                   ? filter.color : Color(.systemBackground)))
                        .foregroundStyle(selectedFilter == filter ? .white : .primary)
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.3),
                                                   lineWidth: selectedFilter == filter ? 0 : 1))
                    }
                }
            }
            .padding(.horizontal)
        }
    }
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
               websiteChecker: WebsiteCheckService())
        .environmentObject(SpotService())
        .environmentObject(UserPicksService())
}
