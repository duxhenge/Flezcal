import SwiftUI
import MapKit
import CoreLocation

// MARK: - List mode

/// Controls whether the list shows confirmed community spots or live Apple Maps search results.
enum ListMode: String, CaseIterable {
    case community = "Community"
    case explore   = "Explore"
}

// MARK: - Custom search location (Explore mode)

/// Holds a geocoded city name + coordinate so the user can search remote cities.
private struct CustomSearchLocation: Equatable {
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
    let customLocation: CustomSearchLocation?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query && lhs.customLocation == rhs.customLocation
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(customLocation?.name)
        hasher.combine(customLocation?.coordinate.latitude)
        hasher.combine(customLocation?.coordinate.longitude)
    }
}

// MARK: - Community Spot Row

struct ListTabRowView: View {
    let spot: Spot
    let userLocation: CLLocationCoordinate2D?

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
                Text(shortAddress(from: spot.address))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedDistanceMiles(from: userLocation, to: spot.coordinate) ?? "—")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                if spot.reviewCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                        Text(String(format: "%.1f", spot.averageRating))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                } else if spot.communityVerified {
                    Text("Verified")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
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

// MARK: - Explore Result Row

/// A single Apple Maps result shown in Explore mode.
struct ExploreResultRowView: View {
    let mapItem: MKMapItem
    let userLocation: CLLocationCoordinate2D?

    private var subtitle: String {
        mapItem.placemark.formattedAddress ?? mapItem.placemark.locality ?? ""
    }

    private var categoryLabel: String {
        mapItem.pointOfInterestCategory.map { poiCategoryName($0) } ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            // Generic venue icon
            Image(systemName: venueIcon(for: mapItem.pointOfInterestCategory))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))

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
    let selectedFilter: SpotFilter
    let currentLocation: () -> CLLocationCoordinate2D?
    /// Passed as a plain let — NOT @EnvironmentObject — so SpotService publishes
    /// do not re-render ExplorePanel and cancel the in-flight .task(id: searchText).
    let spotService: SpotService
    /// User's active picks — plain let (stability contract). Used by checkAllPicks
    /// to check all picks against the HTML cache at zero extra API cost.
    let userPicks: [FoodCategory]

    @StateObject private var searchService = LocationSearchService()

    // Sheet state lives here so changes never re-render ListTabView
    @State private var selectedSuggestion: SuggestedSpot? = nil
    @State private var multiCheckResult: MultiCategoryCheckResult? = nil
    @State private var websiteCheckTask: Task<Void, Never>? = nil
    private let websiteChecker = WebsiteCheckService()

    // Custom search location — all @State, no @EnvironmentObject (stability contract)
    @State private var customLocation: CustomSearchLocation? = nil
    @State private var isEditingLocation = false
    @State private var locationInputText = ""
    @State private var isGeocodingLocation = false
    @State private var geocodeError: String? = nil

    /// The coordinate to use for searches. Custom location if set, otherwise GPS.
    private var effectiveLocation: CLLocationCoordinate2D? {
        customLocation?.coordinate ?? currentLocation()
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Custom location chip ────────────────────────────────
            locationBar

            // ── Main content ────────────────────────────────────────
            // While searching, keep previous results visible instead of
            // flashing "No results" on every keystroke.  Only show the
            // empty / no-results states once the search has settled.
            Group {
                if searchText.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Search any venue")
                            .font(.headline)
                        Text("Type a name, cuisine, or address to search Apple Maps — then add what you find to Flezcal.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if searchService.searchResults.isEmpty && !searchService.isSearching {
                    // Only show "No results" when the search has finished
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                        Text("Try a different name or location.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    Spacer()
                } else if searchService.searchResults.isEmpty && searchService.isSearching {
                    // First search with no previous results to show
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else {
                    // Results list — stays visible while a new search is in flight
                    HStack {
                        Text("\(searchService.searchResults.count) result\(searchService.searchResults.count == 1 ? "" : "s") from Apple Maps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if searchService.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)

                    List(searchService.searchResults, id: \.self) { mapItem in
                        HStack(spacing: 0) {
                            Button {
                                selectResult(mapItem)
                            } label: {
                                ExploreResultRowView(
                                    mapItem: mapItem,
                                    userLocation: effectiveLocation
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
                source: .exploreSearch
            )
        }
        .task(id: SearchTaskID(query: searchText, customLocation: customLocation)) {
            let query = searchText
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                searchService.clearResults()
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await searchService.search(query: query, userLocation: effectiveLocation)
        }
        .onDisappear {
            // Cancel any in-flight website check so it doesn't write
            // back to @State after the view is gone.
            websiteCheckTask?.cancel()
            websiteCheckTask = nil
            multiCheckResult = nil
        }
    }

    /// Resolve the primary FoodCategory for a search result.
    /// Uses the active filter if set, otherwise the user's first pick.
    private var primaryFoodCategory: FoodCategory {
        if let spotCat = selectedFilter.category,
           let foodCat = FoodCategory.allCategories.first(where: { $0.id == spotCat.rawValue }) {
            return foodCat
        }
        return userPicks.first ?? FoodCategory.mezcal
    }

    private func selectResult(_ mapItem: MKMapItem) {
        websiteCheckTask?.cancel()
        multiCheckResult = nil
        let foodCat = primaryFoodCategory
        selectedSuggestion = SuggestedSpot(mapItem: mapItem, suggestedCategory: foodCat)
        let picks = userPicks
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

    // MARK: Location bar

    @ViewBuilder
    private var locationBar: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: customLocation != nil ? "location.circle.fill" : "location.circle")
                    .foregroundStyle(customLocation != nil ? .blue : .secondary)
                    .font(.subheadline)

                if isEditingLocation {
                    TextField("City name (e.g. Ajijic, Mexico)", text: $locationInputText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .onSubmit { geocodeCity(locationInputText) }

                    if isGeocodingLocation {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button { geocodeCity(locationInputText) } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(locationInputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Button {
                        isEditingLocation = false
                        locationInputText = ""
                        geocodeError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                } else if let custom = customLocation {
                    Text("Near: \(custom.name)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        locationInputText = custom.name
                        isEditingLocation = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundStyle(.blue)
                            .font(.subheadline)
                    }

                    Button {
                        customLocation = nil
                        geocodeError = nil
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .font(.subheadline)
                    }
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

            if let error = geocodeError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Custom location geocoding

    private func geocodeCity(_ cityName: String) {
        let trimmed = cityName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isGeocodingLocation = true
        geocodeError = nil

        Task {
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(trimmed)
                if let placemark = placemarks.first,
                   let coord = placemark.location?.coordinate {
                    let displayName = [placemark.locality, placemark.administrativeArea, placemark.country]
                        .compactMap { $0 }
                        .prefix(2)
                        .joined(separator: ", ")
                    customLocation = CustomSearchLocation(
                        name: displayName.isEmpty ? trimmed : displayName,
                        coordinate: coord
                    )
                    isEditingLocation = false
                    locationInputText = ""
                    geocodeError = nil
                } else {
                    geocodeError = "City not found"
                }
            } catch {
                geocodeError = "Couldn't look up location"
            }
            isGeocodingLocation = false
        }
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

    init(locationManager: LocationManager, picksService: UserPicksService) {
        self.locationManager = locationManager
        self.currentLocation = { [locationManager] in locationManager.userLocation }
        self.picksService = picksService
    }

    @State private var selectedFilter: FoodCategory? = nil   // nil = "All"
    @State private var selectedSpot: Spot?
    @State private var searchText = ""
    @State private var listMode: ListMode = .community


    // MARK: Community data

    private var filteredAndSortedSpots: [Spot] {
        let spotFilter = SpotFilter(category: selectedFilter.flatMap { SpotCategory(rawValue: $0.id) })
        let categoryFiltered = spotService.filteredSpots(for: spotFilter)
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
        return textFiltered.sorted { a, b in
            guard let user = currentLocation() else { return a.name < b.name }
            let userCL = CLLocation(latitude: user.latitude, longitude: user.longitude)
            let distA = userCL.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
            let distB = userCL.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
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
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        listMode == .community
                            ? "Search spots, mezcals…"
                            : "Search any restaurant, bar, store…",
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
                .padding(.horizontal)
                .padding(.top, 8)

                // Category filter — shown in both modes
                PicksFilterBar(picks: picksService.picks, selectedPick: $selectedFilter)
                    .padding(.top, 8)

                // ── Content ───────────────────────────────────────────────────
                switch listMode {
                case .community:
                    communityContent
                case .explore:
                    ExplorePanel(
                        searchText: $searchText,
                        selectedFilter: SpotFilter(category: selectedFilter.flatMap { SpotCategory(rawValue: $0.id) }),
                        currentLocation: currentLocation,
                        spotService: spotService,
                        userPicks: picksService.picks
                    )
                }
            }
            .navigationTitle("Nearby")
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
            .onChange(of: listMode) { _, _ in
                searchText = ""
            }
            .task {
                await spotService.fetchSpots()
            }
        }
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
                VStack(spacing: 12) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No spots found")
                        .font(.headline)
                    Text(searchText.isEmpty
                         ? "Be the first to add a \(selectedFilter?.displayName.lowercased() ?? "flan or mezcal") spot!"
                         : "Try a different search term.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                List(filteredAndSortedSpots) { spot in
                    Button {
                        selectedSpot = spot
                    } label: {
                        ListTabRowView(spot: spot, userLocation: currentLocation())
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
    }


}

#Preview {
    ListTabView(locationManager: LocationManager(), picksService: UserPicksService())
        .environmentObject(SpotService())
}
