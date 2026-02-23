import SwiftUI
import MapKit
import CoreLocation

struct MapTabView: View {
    /// Set by ContentView when a .showOnMap notification arrives from the List tab.
    /// MapTabView picks it up, centers the camera, and opens the ghost pin sheet.
    @Binding var pendingMapSuggestion: SuggestedSpot?

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
    private let websiteChecker = WebsiteCheckService()

    // Batch pre-screen — homepage-only scan triggered after ghost pin fetch
    @State private var preScreenTask: Task<Void, Never>? = nil
    @State private var showNoMatchBanner = false
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
        Task {
            await suggestionService.fetchSuggestions(
                in: region,
                existingSpots: spotService.spots,
                picks: picks
            )
            // Kick off batch homepage pre-screen after pins appear
            preScreenTask?.cancel()
            showNoMatchBanner = false
            suggestionService.preScreenComplete = false
            isPreScreening = true
            let suggestions = suggestionService.suggestions
            preScreenTask = Task {
                let results = await websiteChecker.batchPreScreen(
                    suggestions: suggestions,
                    picks: picks
                )
                guard !Task.isCancelled else {
                    isPreScreening = false
                    return
                }
                suggestionService.applyPreScreenResults(results)
                isPreScreening = false
                // Show "no quick matches" banner if zero green pins
                let hasAnyLikely = suggestionService.suggestions.contains {
                    $0.preScreenMatches?.isEmpty == false
                }
                if !hasAnyLikely && !suggestionService.suggestions.isEmpty {
                    showNoMatchBanner = true
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        showNoMatchBanner = false
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
                    }
                    Button {
                        Task { await spotService.fetchSpots() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
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
                    }
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
                // Yellow = unknown/not scanned. Green = homepage pre-screen found keywords.
                ForEach(suggestionService.suggestions) { suggestion in
                    Annotation(suggestion.name, coordinate: suggestion.coordinate) {
                        GhostPinView(
                            category: suggestion.suggestedCategory,
                            isLikely: suggestion.preScreenMatches?.isEmpty == false,
                            likelyCategories: (suggestion.preScreenMatches ?? [])
                                .compactMap { id in FoodCategory.allCategories.first { $0.id == id } }
                        )
                            .onTapGesture {
                                websiteCheckTask?.cancel()
                                multiCheckResult = nil
                                selectedSuggestion = suggestion
                                // Check the primary category (full 3-pass) then check
                                // all remaining user picks against the HTML cache — zero
                                // extra API cost for the additional picks.
                                let primaryPick = suggestion.suggestedCategory
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
                }

                // Persistent ghost pin for venues sent from Explore "Show on Map".
                // Uses showOnMapPin (not selectedSuggestion) so it survives sheet dismissal.
                // Only shown when the venue isn't already in suggestionService.suggestions.
                if let pinned = showOnMapPin,
                   !suggestionService.suggestions.contains(where: { $0.id == pinned.id }) {
                    Annotation("", coordinate: pinned.coordinate) {
                        VStack(spacing: 0) {
                            GhostPinView(category: pinned.suggestedCategory)
                                .scaleEffect(1.3)
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(pinned.suggestedCategory.color.opacity(0.85))
                                .offset(y: -2)
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
                // User changed their picks in My Picks tab — re-fetch with new picks
                selectedPickFilter = nil   // reset to "All" when picks change
                showSearchHereButton = false
                guard let region = visibleRegion else { return }
                lastFetchedCenter = region.center
                fetchAndPreScreen(in: region, picks: picksService.picks)
            }
            .onChange(of: pendingMapSuggestion) { _, newValue in
                guard let suggestion = newValue else { return }
                pendingMapSuggestion = nil   // consume immediately

                // Center camera on the venue
                cameraPosition = .region(MKCoordinateRegion(
                    center: suggestion.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))

                // Open the ghost pin sheet + run website check (same as ghost pin tap)
                websiteCheckTask?.cancel()
                multiCheckResult = nil
                showOnMapPin = suggestion  // persist pin after sheet dismissal
                selectedSuggestion = suggestion
                let primaryPick = suggestion.suggestedCategory
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

            // "Search This Area" button — shown after the user pans/zooms
            if showSearchHereButton {
                VStack {
                    Spacer()
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: showSearchHereButton)
            }

            // "No quick matches" banner — shown when pre-screen found zero green pins
            if showNoMatchBanner {
                VStack {
                    Text("No quick matches yet — tap any pin to search deeper")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        .onTapGesture { showNoMatchBanner = false }
                    Spacer()
                }
                .padding(.top, 60)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: showNoMatchBanner)
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

            // Empty state
            if !spotService.isLoading && spotService.errorMessage == nil
                && visibleSpots.isEmpty && !emptyStateDismissed {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 16) {
                        FoodCategoryIcon(
                            category: selectedPickFilter ?? picksService.picks.first ?? .mezcal,
                            size: 56
                        )
                        Text("No spots here yet")
                            .font(.headline)
                        Text("Be the first to add a \(selectedPickFilter?.displayName.lowercased() ?? "spot") here!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            NotificationCenter.default.post(name: .switchToSpots, object: nil)
                        } label: {
                            Label("Search for a Spot", systemImage: "magnifyingglass")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(24)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { emptyStateDismissed = true }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - List View

    private var listContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search spots...", text: $searchText)
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
                VStack(spacing: 12) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No spots found")
                        .font(.headline)
                    Text(searchText.isEmpty
                         ? "Be the first to add a \(selectedPickFilter?.displayName.lowercased() ?? "spot") here!"
                         : "Try a different search term.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
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
                if spot.reviewCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                        Text(String(format: "%.1f", spot.averageRating))
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

#Preview {
    MapTabView(pendingMapSuggestion: .constant(nil))
        .environmentObject(SpotService())
        .environmentObject(UserPicksService())
}
