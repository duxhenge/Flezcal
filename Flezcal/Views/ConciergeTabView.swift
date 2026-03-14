import SwiftUI
import CoreLocation
@preconcurrency import MapKit

// MARK: - Main Concierge View

/// Guided search flow that walks the user through selecting a category and location,
/// then hands off to the existing Map tab with results loaded.
///
/// Uses integer step index instead of enum with associated values
/// to avoid Swift type-checker timeouts on @ViewBuilder switches.
struct ConciergeTabView: View {
    let locationManager: LocationManager
    @Binding var activePickIDs: Set<String>
    @Binding var selectedTab: Int
    @Binding var pendingSpotsLocation: CustomSearchLocation?
    @Binding var pendingMapCenter: CLLocationCoordinate2D?
    @Binding var pendingMapPicks: [FoodCategory]?

    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var searchResultStore: SearchResultStore
    @EnvironmentObject var authService: AuthService

    // Step indices
    private static let stepWelcome = 0
    private static let stepSelectCategory = 1
    private static let stepCategoryNotFound = 2
    private static let stepCategorySelected = 3
    private static let stepSelectLocation = 4
    private static let stepConfirmLocation = 5

    @State private var currentStep = 0
    @State private var selectedCategory: FoodCategory?
    @State private var notFoundQuery = ""
    @State private var selectedLocation: CustomSearchLocation?
    @State private var categoryInput = ""
    @State private var autocompleteSuggestions: [FoodCategory] = []
    @State private var showCreateCustom = false
    @State private var pickIDsBeforeCreate: Set<String> = []
    @StateObject private var customService = CustomCategoryService()

    private let charcoal = Color(white: 0.12)
    private let gold = Color(red: 0.85, green: 0.65, blue: 0.25)

    var body: some View {
        ZStack {
            if currentStep == Self.stepWelcome {
                welcomeView
            }
            if currentStep == Self.stepSelectCategory {
                categoryView
            }
            if currentStep == Self.stepCategoryNotFound {
                notFoundView
            }
            if currentStep == Self.stepCategorySelected {
                confirmedView
            }
            if currentStep == Self.stepSelectLocation {
                locationView
            }
            if currentStep == Self.stepConfirmLocation {
                confirmLocationView
            }
        }
        .task { await customService.fetchAll() }
        .sheet(isPresented: $showCreateCustom, onDismiss: handleCreateCustomDismiss) {
            CreateCustomCategoryView()
                .environmentObject(picksService)
                .environmentObject(authService)
        }
    }

    // MARK: - Step Views (each is a trivial computed property)

    private var welcomeView: some View {
        ConciergeWelcomeScreen(
            charcoal: charcoal,
            gold: gold,
            onBegin: {
                categoryInput = ""
                autocompleteSuggestions = []
                withAnimation { currentStep = Self.stepSelectCategory }
            },
            onSkip: { selectedTab = AppTab.explore }
        )
    }

    private var categoryView: some View {
        ConciergeCategoryScreen(
            categoryInput: $categoryInput,
            autocompleteSuggestions: $autocompleteSuggestions,
            picksService: picksService,
            customService: customService,
            gold: gold,
            onSelect: { cat in
                selectedCategory = cat
                withAnimation { currentStep = Self.stepCategorySelected }
            },
            onNotFound: { query in
                notFoundQuery = query
                withAnimation { currentStep = Self.stepCategoryNotFound }
            },
            onStartOver: { resetToWelcome() }
        )
    }

    private var notFoundView: some View {
        ConciergeCategoryNotFoundScreen(
            query: notFoundQuery,
            gold: gold,
            onTryAnother: {
                categoryInput = ""
                autocompleteSuggestions = []
                withAnimation { currentStep = Self.stepSelectCategory }
            },
            onCreateNew: {
                pickIDsBeforeCreate = Set(picksService.picks.map(\.id))
                showCreateCustom = true
            },
            onStartOver: { resetToWelcome() }
        )
    }

    private var confirmedView: some View {
        ConciergeCategoryConfirmedScreen(
            category: selectedCategory ?? FoodCategory.allCategories[0],
            gold: gold,
            onNext: { withAnimation { currentStep = Self.stepSelectLocation } },
            onStartOver: { resetToWelcome() }
        )
    }

    private var locationView: some View {
        ConciergeLocationScreen(
            category: selectedCategory ?? FoodCategory.allCategories[0],
            locationManager: locationManager,
            gold: gold,
            onNearMe: { coord in
                guard let cat = selectedCategory, let coord else { return }
                executeSearch(category: cat, location: CustomSearchLocation(
                    name: "Current Location", coordinate: coord
                ))
            },
            onLocationSelected: { loc in
                guard let cat = selectedCategory else { return }
                executeSearch(category: cat, location: loc)
            },
            onStartOver: { resetToWelcome() }
        )
    }

    private var confirmLocationView: some View {
        ConciergeConfirmLocationScreen(
            category: selectedCategory ?? FoodCategory.allCategories[0],
            location: selectedLocation ?? CustomSearchLocation(
                name: "Unknown",
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)
            ),
            gold: gold,
            onConfirm: {
                guard let cat = selectedCategory, let loc = selectedLocation else { return }
                executeSearch(category: cat, location: loc)
            },
            onChange: { withAnimation { currentStep = Self.stepSelectLocation } },
            onStartOver: { resetToWelcome() }
        )
    }

    // MARK: - Actions

    private func executeSearch(category: FoodCategory, location: CustomSearchLocation) {
        FoodCategory.registerTemporaryCategory(category)
        activePickIDs = [category.id]
        // Hand off to both tabs via the shared store:
        // 1. pendingMapCenter triggers the Map's .onChange handler (even off-screen)
        //    which cancels the boot fetch, runs fetchAndPreScreen at this location,
        //    and populates SearchResultStore — the single source of truth.
        // 2. pendingSpotsLocation sets the Spots tab's location bar display.
        // Both tabs then read from the same store data.
        pendingMapCenter = location.coordinate
        pendingMapPicks = [category]
        pendingSpotsLocation = location
        selectedTab = AppTab.spots
        resetToWelcome()
    }

    private func handleCreateCustomDismiss() {
        let currentIDs = Set(picksService.picks.map(\.id))
        let newIDs = currentIDs.subtracting(pickIDsBeforeCreate)
        if let newID = newIDs.first,
           let newCategory = picksService.picks.first(where: { $0.id == newID }) {
            selectedCategory = newCategory
            withAnimation { currentStep = Self.stepCategorySelected }
        }
    }

    private func resetToWelcome() {
        categoryInput = ""
        autocompleteSuggestions = []
        selectedCategory = nil
        selectedLocation = nil
        notFoundQuery = ""
        withAnimation { currentStep = Self.stepWelcome }
    }
}

// MARK: - Welcome Screen

struct ConciergeWelcomeScreen: View {
    let charcoal: Color
    let gold: Color
    let onBegin: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            charcoal.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(gold)
                Text("Concierge")
                    .font(.system(size: 36, weight: .light))
                    .tracking(4)
                    .foregroundStyle(.white)
                Text("Let me help you find the perfect spot")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button(action: onBegin) {
                    Text("Guided Search")
                        .font(.headline)
                        .foregroundStyle(charcoal)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(gold))
                }
                Button(action: onSkip) {
                    Text("I know what I'm looking for")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Category Selection Screen

struct ConciergeCategoryScreen: View {
    @Binding var categoryInput: String
    @Binding var autocompleteSuggestions: [FoodCategory]
    let picksService: UserPicksService
    let customService: CustomCategoryService
    let gold: Color
    let onSelect: (FoodCategory) -> Void
    let onNotFound: (String) -> Void
    let onStartOver: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ConciergeHeader(gold: gold)
            VStack(spacing: 20) {
                Text("What kind of dish or drink\nare you looking for?")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)
                categorySearchField
                Spacer()
                ConciergeStartOverButton(action: onStartOver)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFocused = true }
        }
    }

    private var categorySearchField: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("e.g. Tacos, Mezcal, Ramen…", text: $categoryInput)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit { handleSubmit() }
                    .onChange(of: categoryInput) { _, newValue in
                        updateSuggestions(for: newValue)
                    }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if !autocompleteSuggestions.isEmpty {
                ConciergeCategoryDropdown(
                    suggestions: autocompleteSuggestions,
                    searchText: categoryInput,
                    onSelect: { cat in
                        isFocused = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(cat)
                    }
                )
            }
        }
        .padding(.horizontal, 24)
    }

    private func handleSubmit() {
        if let first = autocompleteSuggestions.first {
            isFocused = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(first)
        } else {
            let query = categoryInput.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            onNotFound(query)
        }
    }

    private func updateSuggestions(for input: String) {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.count >= 2 else {
            autocompleteSuggestions = []
            return
        }

        // Build one unified pool: Top 50 + trending (as FoodCategory) + user picks
        let trendingAsFoodCats = customService.customCategories.map { $0.toFoodCategory() }
        var pool = FoodCategory.allCategories + trendingAsFoodCats
        for pick in picksService.picks where !pool.contains(where: { $0.id == pick.id }) {
            pool.append(pick)
        }

        // Single search pass across the unified pool
        var matches: [FoodCategory] = []
        for cat in pool {
            let catName = cat.displayName.lowercased()
            let nameMatch = catName.hasPrefix(lower) || catName.contains(lower)
            let keywordMatch = cat.websiteKeywords.contains { $0.lowercased().hasPrefix(lower) || $0.lowercased().contains(lower) }
            let termMatch = cat.mapSearchTerms.contains { $0.lowercased().hasPrefix(lower) || $0.lowercased().contains(lower) }
            if nameMatch || keywordMatch || termMatch { matches.append(cat) }
        }
        matches.sort { a, b in
            let ap = a.displayName.lowercased().hasPrefix(lower)
            let bp = b.displayName.lowercased().hasPrefix(lower)
            if ap != bp { return ap }
            return a.displayName < b.displayName
        }
        autocompleteSuggestions = Array(matches.prefix(5))
    }
}

// MARK: - Category Autocomplete Dropdown

struct ConciergeCategoryDropdown: View {
    let suggestions: [FoodCategory]
    let searchText: String
    let onSelect: (FoodCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { category in
                Button { onSelect(category) } label: {
                    row(for: category)
                }
                .buttonStyle(.plain)
                if category.id != suggestions.last?.id {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func row(for category: FoodCategory) -> some View {
        HStack(spacing: 10) {
            Text(category.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(matchReason(for: category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func matchReason(for category: FoodCategory) -> String {
        let lower = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lower.isEmpty else { return category.displayName }
        // Trending / custom categories have IDs starting with "custom_"
        if category.id.hasPrefix("custom_") { return "Trending Flezcal" }
        let catName = category.displayName.lowercased()
        if catName.hasPrefix(lower) || catName.contains(lower) { return "Top 50 Flezcal" }
        if let kw = category.websiteKeywords.first(where: { $0.lowercased().contains(lower) }) {
            return "Includes \(kw.lowercased()) varieties"
        }
        if let term = category.mapSearchTerms.first(where: { $0.lowercased().contains(lower) }) {
            return "Searches for \"\(term.lowercased())\""
        }
        return "Related category"
    }
}

// MARK: - Category Not Found Screen

struct ConciergeCategoryNotFoundScreen: View {
    let query: String
    let gold: Color
    let onTryAnother: () -> Void
    let onCreateNew: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ConciergeHeader(gold: gold)
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("That offering isn't available yet")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("\"\(query)\" doesn't match any existing Flezcal categories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                actionButtons
                Spacer()
                ConciergeStartOverButton(action: onStartOver)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onTryAnother) {
                Label("Try Another", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(.white)
            }
            Button(action: onCreateNew) {
                Label("Create a New Flezcal", systemImage: "plus.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().stroke(Color.orange, lineWidth: 1.5))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Category Confirmed Screen

struct ConciergeCategoryConfirmedScreen: View {
    let category: FoodCategory
    let gold: Color
    let onNext: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ConciergeHeader(gold: gold)
            VStack(spacing: 24) {
                Spacer()
                Text(category.emoji).font(.system(size: 72))
                Text(category.displayName).font(.title.weight(.semibold))
                Text("Great choice!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onNext) {
                    Text("Next")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.orange))
                }
                ConciergeStartOverButton(action: onStartOver)
            }
        }
    }
}

// MARK: - Location Screen

struct ConciergeLocationScreen: View {
    let category: FoodCategory
    let locationManager: LocationManager
    let gold: Color
    let onNearMe: (CLLocationCoordinate2D?) -> Void
    let onLocationSelected: (CustomSearchLocation) -> Void
    let onStartOver: () -> Void

    @StateObject private var locationCompleter = LocationCompleterService()
    @State private var locationInput = ""
    @State private var isResolving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ConciergeHeader(gold: gold)
            ScrollView {
                VStack(spacing: 24) {
                    if !isFocused {
                        categoryChip
                        Text("Where would you like to look?")
                            .font(.title3.weight(.medium))
                            .multilineTextAlignment(.center)
                        nearMeButton
                        orDivider
                    }
                    Text(isFocused ? "Type a city, neighborhood, or landmark" : "Search for another location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    locationSearchField
                }
                .padding(.bottom, 200)
            }
            .scrollDismissesKeyboard(.interactively)
            if !isFocused {
                ConciergeStartOverButton(action: onStartOver)
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var categoryChip: some View {
        HStack(spacing: 8) {
            Text(category.emoji).font(.title3)
            Text(category.displayName).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(category.color.opacity(0.15)))
        .padding(.top, 16)
    }

    private var nearMeButton: some View {
        Button { onNearMe(locationManager.userLocation) } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill").font(.title3)
                Text("Near Me").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
    }

    private var orDivider: some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            Text("or").font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
        }
        .padding(.horizontal, 32)
    }

    private var locationSearchField: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "map").foregroundStyle(.secondary)
                TextField("City, neighborhood, or landmark…", text: $locationInput)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        if let first = locationCompleter.suggestions.first {
                            resolve(first)
                        }
                    }
                    .onChange(of: locationInput) { _, newValue in
                        locationCompleter.updateQuery(newValue)
                    }
                if isResolving {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ConciergeLocationDropdown(
                suggestions: Array(locationCompleter.suggestions.prefix(5)),
                onSelect: { resolve($0) }
            )
        }
        .padding(.horizontal, 24)
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isFocused = false
        isResolving = true
        Task {
            if let resolved = await locationCompleter.resolve(completion) {
                isResolving = false
                onLocationSelected(resolved)
            } else {
                isResolving = false
            }
        }
    }
}

// MARK: - Location Dropdown

struct ConciergeLocationDropdown: View {
    let suggestions: [MKLocalSearchCompletion]
    let onSelect: (MKLocalSearchCompletion) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions, id: \.self) { completion in
                    Button { onSelect(completion) } label: {
                        row(for: completion)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 36)
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(for completion: MKLocalSearchCompletion) -> some View {
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
        .padding(.vertical, 10)
    }
}

// MARK: - Confirm Location Screen

struct ConciergeConfirmLocationScreen: View {
    let category: FoodCategory
    let location: CustomSearchLocation
    let gold: Color
    let onConfirm: () -> Void
    let onChange: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ConciergeHeader(gold: gold)
            VStack(spacing: 24) {
                Spacer()
                Text(category.emoji).font(.system(size: 48))
                Text("I'll look for \(category.displayName)")
                    .font(.title3.weight(.medium))
                locationLabel
                Text("Is that right?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                confirmButtons
                ConciergeStartOverButton(action: onStartOver)
            }
        }
    }

    private var locationLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill").foregroundStyle(.orange)
            Text("around \(location.name)").font(.title3)
        }
    }

    private var confirmButtons: some View {
        HStack(spacing: 16) {
            Button(action: onChange) {
                Text("No, change it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(.primary)
            }
            Button(action: onConfirm) {
                Text("Yes, search!")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Shared Components

struct ConciergeHeader: View {
    let gold: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(gold)
            Text("Concierge").font(.headline).tracking(1)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct ConciergeStartOverButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Start over")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }
}
