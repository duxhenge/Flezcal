import SwiftUI
import MapKit

struct BusinessSearchView: View {
    let category: SpotCategory
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var photoService: PhotoService
    @StateObject private var searchService = LocationSearchService()
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedMapItem: MKMapItem?
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search restaurants, bars, stores...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit { performSearch() }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchService.clearResults()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()

                // Results
                if searchService.isSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if searchService.searchResults.isEmpty && !searchText.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term or check the spelling.")
                    )
                    Spacer()
                } else {
                    List(searchService.searchResults, id: \.self) { item in
                        Button {
                            selectedMapItem = item
                            showConfirmation = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? "Unknown Business")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                if let address = item.placemark.formattedAddress {
                                    Text(address)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if let category = item.pointOfInterestCategory?.displayName {
                                    Text(category)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Find Business")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showConfirmation) {
                if let mapItem = selectedMapItem {
                    ConfirmSpotView(mapItem: mapItem, categories: [category]) {
                        dismiss()
                    }
                    .environmentObject(authService)
                    .environmentObject(spotService)
                    .environmentObject(photoService)
                }
            }
        }
    }

    private func performSearch() {
        Task {
            await searchService.search(query: searchText)
        }
    }
}

// MARK: - Confirm Spot View

struct ConfirmSpotView: View {
    let mapItem: MKMapItem
    /// Categories to assign to the spot. Multi-category comes from the
    /// multi-pick website check; single-category from BusinessSearchView.
    let categories: [SpotCategory]
    /// When true the spot is marked community-verified on creation (ghost pin / Explore search).
    var preVerified: Bool = false
    /// Website-detected categories to store on the spot (from ghost pin flow).
    var websiteDetectedCategories: [String]? = nil
    let onSaved: () -> Void

    /// Primary category — first in the list, used wherever the old single-category
    /// code path still needs one value (pin colour, offerings label, etc.).
    private var category: SpotCategory { categories.first ?? .mezcal }

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var photoService: PhotoService
    @Environment(\.dismiss) private var dismiss

    @State private var mezcalOfferings: [String] = [""]
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var showFirstSpotCelebration = false
    @State private var existingSpot: Spot?
    @State private var successMessage = ""
    @State private var showSuccessOverlay = false
    @State private var overlayScale: CGFloat = 0.3
    /// Holds the saved Spot so the user can navigate to its detail view.
    @State private var savedSpot: Spot?
    @State private var showSignIn = false
    /// Tracks that the user tapped "save" before signing in — auto-proceed after.
    @State private var pendingSaveAfterSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Map preview
                    if let coordinate = mapItem.placemark.location?.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        ))) {
                            Annotation(mapItem.name ?? "", coordinate: coordinate) {
                                if let foodCat = FoodCategory.by(id: category.rawValue) {
                                    ConfirmPinView(category: foodCat)
                                }
                            }
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        // Verified badge
                        Label("Verified via Apple Maps", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        // Business name
                        Text(mapItem.name ?? "Unknown Business")
                            .font(.title3)
                            .fontWeight(.bold)

                        // Address
                        if let address = mapItem.placemark.formattedAddress {
                            Label(address, systemImage: "mappin")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Existing spot notice
                        if let existing = existingSpot {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()

                                Label("This spot already exists in \(AppConstants.appName)", systemImage: "info.circle.fill")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.blue)

                                HStack(spacing: 4) {
                                    ForEach(existing.categories) { cat in
                                        Label(cat.displayName, systemImage: cat.icon)
                                            .font(.caption)
                                            .foregroundStyle(cat.color)
                                    }
                                }
                                // Per-category ratings for existing spot
                                let ratedCats = existing.categories.filter { existing.rating(for: $0) != nil && existing.rating(for: $0)!.count > 0 }
                                if !ratedCats.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(ratedCats) { cat in
                                            if let catRating = existing.rating(for: cat) {
                                                HStack(spacing: 4) {
                                                    CategoryIcon(category: cat, size: 12)
                                                    Text(cat.displayName)
                                                        .font(.caption2)
                                                    FlanBarView(rating: catRating.average, size: 10, spacing: 1)
                                                    Text(String(format: "%.1f", catRating.average))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Show which new categories will be added
                                let newCats = categories.filter { cat in !existing.categories.contains(cat) }
                                if !newCats.isEmpty {
                                    let names = newCats.map(\.displayName).joined(separator: " & ")
                                    Label("This will also add \(names) to this spot!", systemImage: "plus.circle.fill")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.green)
                                }

                                // Show existing offerings for this category
                                let existingOfferings = existing.offerings(for: category)
                                if !existingOfferings.isEmpty {
                                    Text("\(category.offeringsLabel) already listed:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(existingOfferings, id: \.self) { item in
                                        Label(item, systemImage: "checkmark")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                }

                                Text("You can add \(category.offeringsLabel.lowercased()) not yet on the list below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            // Category badge for new spots
                            Label("Adding as \(category.displayName) spot", systemImage: category.icon)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(category.color)
                        }

                        // Offerings input
                        Divider()

                        Text(existingSpot != nil ? "Add New \(category.offeringsLabel)" : category.offeringsLabel)
                            .font(.headline)

                        Text(existingSpot != nil
                             ? "Add any \(category.offeringsLabel.lowercased()) not already listed above."
                             : category.offeringsExamples)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let knownOfferings = CommunityOfferings.suggestions(for: category, from: spotService.spots)

                        ForEach(mezcalOfferings.indices, id: \.self) { index in
                            HStack {
                                OfferingInputField(
                                    text: $mezcalOfferings[index],
                                    placeholder: "One \(category.offeringSingular) per field",
                                    knownOfferings: knownOfferings,
                                    suggestionIcon: category.icon,
                                    useVeladoraIcon: category == .mezcal
                                )

                                if mezcalOfferings.count > 1 {
                                    Button {
                                        mezcalOfferings.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }

                        Button {
                            mezcalOfferings.append("")
                        } label: {
                            Label("Add Another", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal)

                    // Save button — sign-in required, triggers inline sheet if needed
                    Button {
                        if authService.isSignedIn {
                            saveSpot()
                        } else {
                            pendingSaveAfterSignIn = true
                            showSignIn = true
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Label(existingSpot != nil ? "Update This Spot" : "Add This Spot",
                                  systemImage: existingSpot != nil ? "arrow.triangle.2.circlepath" : "plus.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.horizontal)
                    .disabled(isSaving)
                }
                .padding(.vertical)
            }
            .navigationTitle(existingSpot != nil ? "Update Spot" : "Confirm Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                checkForExistingSpot()
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .environmentObject(authService)
                    .presentationDetents([.medium])
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                if signedIn && pendingSaveAfterSignIn {
                    pendingSaveAfterSignIn = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        saveSpot()
                    }
                }
            }
            .alert("Success!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                    onSaved()
                }
            } message: {
                Text("\(successMessage)\n\nYou can rate individual categories from the spot's detail page.")
            }
            .alert("🍮 ¡Eres un Flanático!", isPresented: $showFirstSpotCelebration) {
                Button("¡Vámonos!") {
                    dismiss()
                    onSaved()
                }
            } message: {
                Text("You added your first spot to Flezcal! The community thanks you. You are now officially a Flanático. 🥃\n\nVisit the spot to rate individual categories.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(spotService.errorMessage ?? "Failed to save. Please try again.")
            }
            // Success overlay — brief animated confirmation before alert appears
            .overlay {
                if showSuccessOverlay {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 16) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.orange)
                                .scaleEffect(overlayScale)
                                .animation(.spring(response: 0.45, dampingFraction: 0.55), value: overlayScale)
                            Text("Spot Added! 🍮")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func checkForExistingSpot() {
        guard let coordinate = mapItem.placemark.location?.coordinate,
              let name = mapItem.name else { return }
        existingSpot = spotService.findExistingSpot(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func saveSpot() {
        guard let coordinate = mapItem.placemark.location?.coordinate,
              let userID = authService.userID else {
            // Surface the error so the button doesn't silently do nothing
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            showError = true
            return
        }

        isSaving = true

        // Split on commas so "A, B, C" becomes three separate brands
        let filteredOfferings = mezcalOfferings
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        Task {
            if let existing = existingSpot {
                var didSomething = false
                var messages: [String] = []

                // Add any new categories not already on the spot
                let newCats = categories.filter { cat in !existing.categories.contains(cat) }
                if !newCats.isEmpty {
                    let catSuccess = await spotService.addCategories(spotID: existing.id, newCategories: newCats, addedBy: userID)
                    if catSuccess {
                        let names = newCats.map(\.displayName).joined(separator: ", ")
                        messages.append("\(names) added to \(existing.name).")
                        didSomething = true

                        // Auto-create verifications for the newly added categories
                        let verificationService = VerificationService()
                        for cat in newCats {
                            _ = await verificationService.submitVote(
                                spotID: existing.id,
                                userID: userID,
                                category: cat,
                                vote: true
                            )
                        }
                    }
                }

                // Merge offerings for the primary category
                if !filteredOfferings.isEmpty {
                    let offeringsSuccess = await spotService.addOfferings(spotID: existing.id, category: category, newOfferings: filteredOfferings)
                    if offeringsSuccess {
                        messages.append("\(category.offeringsLabel) have been updated.")
                        didSomething = true
                    }
                }

                isSaving = false
                // Make the existing spot available for rating
                savedSpot = spotService.findExistingSpot(
                    name: existing.name,
                    latitude: existing.latitude,
                    longitude: existing.longitude
                ) ?? existing
                if didSomething {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    successMessage = messages.joined(separator: " ")
                    showSuccess = true
                } else {
                    successMessage = "This spot is already in \(AppConstants.appName). No changes to make."
                    showSuccess = true
                }
            } else {
                // Create new spot
                let categoryAttribution = Dictionary(uniqueKeysWithValues: categories.map { ($0.rawValue, userID) })
                let spot = Spot(
                    name: mapItem.name ?? "Unknown",
                    address: mapItem.placemark.formattedAddress ?? "Unknown address",
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    mapItemName: mapItem.name ?? "",
                    categories: categories,
                    addedByUserID: userID,
                    addedDate: Date(),
                    averageRating: 0,
                    reviewCount: 0,
                    offerings: filteredOfferings.isEmpty ? nil : [category.rawValue: filteredOfferings],
                    websiteURL: mapItem.url?.absoluteString,
                    communityVerified: preVerified,
                    categoryAddedBy: categoryAttribution,
                    websiteDetectedCategories: websiteDetectedCategories
                )

                let isFirstSpot = spotService.spots.filter { $0.addedByUserID == userID }.isEmpty
                let success = await spotService.addSpot(spot)
                isSaving = false
                if success {
                    savedSpot = spot

                    // Auto-create verification documents for each confirmed category
                    // The user adding a spot IS their verification (vote: true)
                    Task {
                        let verificationService = VerificationService()
                        for cat in categories {
                            _ = await verificationService.submitVote(
                                spotID: spot.id,
                                userID: userID,
                                category: cat,
                                vote: true
                            )
                        }
                    }

                    // Show pin-drop animation
                    withAnimation { showSuccessOverlay = true }
                    overlayScale = 0.3
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { overlayScale = 1.0 }

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    // Generate map snapshot photo in background (non-blocking)
                    Task.detached(priority: .background) {
                        if let snapshot = await photoService.generateMapSnapshot(coordinate: coordinate),
                           let url = await photoService.uploadSpotPhoto(snapshot, spotID: spot.id) {
                            await photoService.savePhotoURL(url, spotID: spot.id)
                        }
                    }

                    // Dismiss overlay after 1.4s then show success alert/celebration
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { showSuccessOverlay = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if isFirstSpot {
                                showFirstSpotCelebration = true
                            } else {
                                successMessage = "\(mapItem.name ?? "This spot") has been added to \(AppConstants.appName)."
                                showSuccess = true
                            }
                        }
                    }
                } else {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    showError = true
                }
            }
        }
    }
}

// MARK: - Confirm Pin View

/// Mini map pin used in ConfirmSpotView's map preview.
/// Mirrors SpotPinView's style but takes a FoodCategory so the veladora
/// renders correctly for mezcal instead of a generic SF Symbol.
private struct ConfirmPinView: View {
    let category: FoodCategory

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(category.color)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                FoodCategoryIcon(category: category, size: 22)
            }
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(category.color)
                .offset(y: -3)
        }
    }
}

// MARK: - CLPlacemark Extension

extension CLPlacemark {
    var formattedAddress: String? {
        let streetParts = [subThoroughfare, thoroughfare].compactMap { $0 }
        let street = streetParts.isEmpty ? nil : streetParts.joined(separator: " ")
        let components = [street, locality, administrativeArea, postalCode].compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}

// MARK: - MKPointOfInterestCategory Extension

extension MKPointOfInterestCategory {
    var displayName: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .bakery: return "Bakery"
        case .cafe: return "Cafe"
        case .nightlife: return "Nightlife"
        case .foodMarket: return "Food Market"
        case .store: return "Store"
        case .winery: return "Winery"
        case .brewery: return "Brewery"
        case .hotel: return "Restaurant & Inn"
        default: return "Business"
        }
    }
}
