import SwiftUI
import MapKit
import PhotosUI

struct SpotDetailView: View {
    let spot: Spot
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var photoService: PhotoService
    @EnvironmentObject var picksService: UserPicksService
    @StateObject private var reviewService = ReviewService()
    @Environment(\.dismiss) private var dismiss

    @State private var showWriteReview = false
    @State private var showReportSpotAlert = false
    @State private var showReportConfirmation = false
    @State private var showAddMezcals = false
    @State private var showPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var localPhotoURL: String?   // optimistic local update after upload

    // Add-category state
    @State private var showAddCategory = false
    @State private var isConfirmingVisit = false
    @State private var showVisitConfirmed = false

    private let websiteChecker = WebsiteCheckService()

    /// Live version of this spot from SpotService, reflecting any in-session mutations
    /// (e.g. communityVerified flip, report updates). Falls back to the original `let spot`.
    private var liveSpot: Spot {
        spotService.spots.first { $0.id == spot.id } ?? spot
    }

    /// Best available photo URL: user upload overrides auto-snapshot
    private var displayPhotoURL: String? { localPhotoURL ?? liveSpot.displayPhotoURL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hero image — shows user/auto photo if available, otherwise map preview
                    ZStack(alignment: .bottomTrailing) {
                        if let urlStr = displayPhotoURL, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    mapPreview
                                default:
                                    mapPreview.overlay(ProgressView())
                                }
                            }
                            .frame(height: 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            mapPreview
                        }

                        // Camera button — signed-in users can upload a photo
                        if authService.isSignedIn {
                            Button { showPhotoPicker = true } label: {
                                Group {
                                    if photoService.isUploading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "camera.fill")
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(10)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                            }
                            .disabled(photoService.isUploading)
                            .padding(12)
                        }
                    }
                    .padding(.horizontal)
                    .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
                    .onChange(of: pickerItem) { _, item in
                        Task {
                            guard let item,
                                  let data = try? await item.loadTransferable(type: Data.self),
                                  let image = UIImage(data: data) else { return }
                            await photoService.uploadAndSaveUserPhoto(image, spotID: spot.id)
                            // Refresh local URL so UI updates immediately without re-fetching
                            if photoService.uploadError == nil {
                                localPhotoURL = await photoService.fetchUserPhotoURL(spotID: spot.id)
                            }
                        }
                    }

                    // Info section
                    VStack(alignment: .leading, spacing: 12) {
                        // Category badges
                        HStack {
                            ForEach(liveSpot.categories) { cat in
                                HStack(spacing: 4) {
                                    CategoryIcon(category: cat, size: 16)
                                    Text(cat.displayName)
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(cat.color.opacity(0.15))
                                .foregroundStyle(cat.color)
                                .clipShape(Capsule())
                            }
                            Spacer()
                        }

                        // ── Import-provenance banners ──────────────────────────
                        if liveSpot.source != nil {
                            importedSpotBanner
                        }

                        // Rating row — on its own line so it never gets clipped
                        if liveSpot.reviewCount > 0 {
                            HStack(spacing: 6) {
                                StarDisplayView(rating: liveSpot.averageRating)
                                Text(String(format: "%.1f", liveSpot.averageRating))
                                    .fontWeight(.semibold)
                                Text("(\(liveSpot.reviewCount) review\(liveSpot.reviewCount == 1 ? "" : "s"))")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        } else {
                            Text("No reviews yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Fun badges row
                        if liveSpot.isPerfectPairing || liveSpot.isHiddenGem || liveSpot.isRecentlyVerified || reviewService.hasTranscendentReview {
                            HStack(spacing: 6) {
                                if liveSpot.isPerfectPairing {
                                    SpotBadge(emoji: "🍮🥃", label: "Perfect Pairing", color: .orange)
                                }
                                if liveSpot.isHiddenGem {
                                    SpotBadge(emoji: "💎", label: "Hidden Gem", color: .blue)
                                }
                                if liveSpot.isRecentlyVerified {
                                    SpotBadge(emoji: "✨", label: "New", color: .green)
                                }
                                if reviewService.hasTranscendentReview {
                                    SpotBadge(emoji: "🌟", label: "Transcendent", color: .purple)
                                }
                                Spacer()
                            }
                        }

                        // Name
                        Text(spot.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        // Address
                        Label(spot.address, systemImage: "mappin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Verified business name
                        Label("Verified: \(spot.mapItemName)", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .fixedSize(horizontal: false, vertical: true)

                        // Mezcal offerings
                        if liveSpot.hasMezcal {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Mezcal Menu")
                                        .font(.headline)
                                    Spacer()
                                    if authService.isSignedIn {
                                        Button {
                                            showAddMezcals = true
                                        } label: {
                                            Label("Add", systemImage: "plus.circle")
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(.top, 4)

                                if let offerings = liveSpot.mezcalOfferings, !offerings.isEmpty {
                                    ForEach(offerings, id: \.self) { mezcal in
                                        HStack(spacing: 6) {
                                            VeladoraIcon(size: 16)
                                            Text(mezcal)
                                                .font(.subheadline)
                                        }
                                    }
                                } else {
                                    Text("No mezcals listed yet. Be the first to add some!")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Add-category button — shown when user has picks not yet on this spot
                        let addablePicks = picksService.picks.filter { pick in
                            !liveSpot.categories.contains(where: { $0.rawValue == pick.id })
                        }
                        if authService.isSignedIn && !addablePicks.isEmpty {
                            Button {
                                showAddCategory = true
                            } label: {
                                Label("Add another category to this spot", systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal)

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            openInMaps()
                        } label: {
                            Label("Open in Maps", systemImage: "map")
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)

                        if authService.isSignedIn {
                            let alreadyReviewed = reviewService.hasUserReviewed(userID: authService.userID ?? "")
                            Button {
                                showWriteReview = true
                            } label: {
                                Label(alreadyReviewed ? "Reviewed" : "Review", systemImage: alreadyReviewed ? "checkmark" : "star.bubble")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(alreadyReviewed)
                        }
                    }
                    .padding(.horizontal)

                    // Report spot button
                    if authService.isSignedIn {
                        let userID = authService.userID ?? ""
                        let alreadyReported = liveSpot.reportedByUserIDs.contains(userID)
                        let isOwnSpot = liveSpot.addedByUserID == userID

                        if !isOwnSpot {
                            HStack {
                                Spacer()
                                if alreadyReported {
                                    Label("Spot Reported", systemImage: "flag.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button {
                                        showReportSpotAlert = true
                                    } label: {
                                        Label("Report Spot", systemImage: "flag")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Divider()
                        .padding(.horizontal)

                    // Reviews section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reviews")
                            .font(.headline)
                            .padding(.horizontal)

                        if reviewService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if reviewService.visibleReviews.isEmpty {
                            Text("No reviews yet. Be the first!")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            ForEach(reviewService.visibleReviews) { review in
                                ReviewCardView(
                                    review: review,
                                    reviewService: reviewService,
                                    currentUserID: authService.userID ?? ""
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom)
                }
                .padding(.vertical)
            }
            .navigationTitle("Spot Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showWriteReview) {
                WriteReviewView(spot: spot, reviewService: reviewService)
            }
            .sheet(isPresented: $showAddMezcals) {
                AddMezcalsSheet(spot: liveSpot)
            }
            .sheet(isPresented: $showAddCategory) {
                AddCategorySheet(
                    spot: liveSpot,
                    addablePicks: picksService.picks.filter { pick in
                        !liveSpot.categories.contains(where: { $0.rawValue == pick.id })
                    },
                    websiteChecker: websiteChecker
                )
            }
            .task {
                await reviewService.fetchReviews(for: spot.id)

                // Backfill: if this spot has no photo yet, generate one now.
                // Covers spots that were added before the photo feature existed.
                if liveSpot.displayPhotoURL == nil {
                    let coordinate = spot.coordinate
                    let spotID = spot.id
                    Task.detached(priority: .background) {
                        if let snapshot = await photoService.generateMapSnapshot(coordinate: coordinate),
                           let url = await photoService.uploadSpotPhoto(snapshot, spotID: spotID) {
                            await photoService.savePhotoURL(url, spotID: spotID)
                        }
                    }
                }
            }
            .alert("Report Spot", isPresented: $showReportSpotAlert) {
                Button("Report", role: .destructive) {
                    Task {
                        await spotService.reportSpot(spotID: spot.id, reporterUserID: authService.userID ?? "")
                        showReportConfirmation = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Report this spot as inaccurate or inappropriate? Spots with multiple reports will be automatically hidden.")
            }
            .alert("Report Submitted", isPresented: $showReportConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Thank you for helping keep \(AppConstants.appName) accurate. We'll review this spot.")
            }
        }
    }

    /// Fallback map tile shown when no photo is available yet
    private var mapPreview: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: spot.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))) {
            Annotation(spot.name, coordinate: spot.coordinate) {
                SpotPinView(spot: spot)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: spot.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = spot.name
        mapItem.openInMaps(launchOptions: nil)
    }

    // MARK: - Imported Spot Banners

    /// Shows provenance context for spots seeded from an external source.
    /// • Not yet community-verified → amber "awaiting check-in" banner + optional confirm button
    /// • Community-verified + flagged → orange caution strip
    /// • Community-verified + clean → green "community verified" badge (lightweight)
    @ViewBuilder
    private var importedSpotBanner: some View {
        let isFlagged = liveSpot.reportCount >= 2

        VStack(spacing: 8) {
            if !liveSpot.communityVerified {
                // ── Amber: awaiting first real check-in ──
                VStack(alignment: .leading, spacing: 6) {
                    Label("Curated listing — not yet visited by a Flezcal member",
                          systemImage: "clock.badge.questionmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)

                    if authService.isSignedIn {
                        Button {
                            confirmVisit()
                        } label: {
                            if isConfirmingVisit {
                                ProgressView()
                                    .tint(.orange)
                            } else {
                                Label("I've been here — confirm this spot",
                                      systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.orange)
                        .disabled(isConfirmingVisit)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            } else if isFlagged {
                // ── Orange caution: verified but currently flagged ──
                Label("Flagged by the community — accuracy uncertain",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

            } else {
                // ── Green: verified by community, no flags ──
                Label("Community verified",
                      systemImage: "person.2.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.green.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
        .alert("Spot Confirmed!", isPresented: $showVisitConfirmed) {
            Button("Thanks!", role: .cancel) {}
        } message: {
            Text("You've marked \(spot.name) as visited. This helps the whole community!")
        }
    }

    /// Marks this imported spot as community-verified in Firestore.
    private func confirmVisit() {
        isConfirmingVisit = true
        Task {
            await spotService.markCommunityVerified(spotID: spot.id)
            await MainActor.run {
                isConfirmingVisit = false
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                showVisitConfirmed = true
            }
        }
    }
}

// MARK: - Spot Badge Chip

struct SpotBadge: View {
    let emoji: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(emoji)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// MARK: - Review Card

struct ReviewCardView: View {
    let review: Review
    @ObservedObject var reviewService: ReviewService
    let currentUserID: String
    @State private var showReportAlert = false
    @State private var showReportConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: name + stars + date
            HStack {
                Text(review.userName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                StarDisplayView(rating: Double(review.rating))

                Text(review.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Comment
            Text(review.comment)
                .font(.subheadline)
                .foregroundStyle(.primary)

            // Report button (don't show for own reviews)
            if review.userID != currentUserID {
                HStack {
                    Spacer()
                    if review.reportedByUserIDs.contains(currentUserID) {
                        Label("Reported", systemImage: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            showReportAlert = true
                        } label: {
                            Label("Report", systemImage: "flag")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .alert("Report Review", isPresented: $showReportAlert) {
            Button("Report", role: .destructive) {
                Task {
                    await reviewService.reportReview(reviewID: review.id, reporterUserID: currentUserID)
                    showReportConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Report this review as inappropriate? Reviews with multiple reports will be automatically hidden.")
        }
        .alert("Report Submitted", isPresented: $showReportConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you for your report. We'll review this content.")
        }
    }
}

// MARK: - Add Mezcals Sheet

struct AddMezcalsSheet: View {
    let spot: Spot
    @EnvironmentObject var spotService: SpotService
    @Environment(\.dismiss) private var dismiss

    @State private var newOfferings: [String] = [""]
    @State private var isSaving = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Spot info
                    Text(spot.name)
                        .font(.title3)
                        .fontWeight(.bold)

                    // Existing mezcals
                    if let existing = spot.mezcalOfferings, !existing.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Already Listed")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            ForEach(existing, id: \.self) { mezcal in
                                Label(mezcal, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                        }

                        Divider()
                    }

                    // New mezcals
                    Text("Add New Mezcals")
                        .font(.headline)

                    Text("Add mezcals that aren't listed above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(newOfferings.indices, id: \.self) { index in
                        HStack {
                            MezcalInputField(text: $newOfferings[index], placeholder: "One brand per field")

                            if newOfferings.count > 1 {
                                Button {
                                    newOfferings.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    Button {
                        newOfferings.append("")
                    } label: {
                        Label("Add Another", systemImage: "plus.circle")
                            .font(.subheadline)
                    }

                    // Save button
                    Button {
                        saveMezcals()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Label("Save Mezcals", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isSaving || filteredOfferings.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Add Mezcals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Mezcals Added!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("The mezcal list for \(spot.name) has been updated.")
            }
        }
    }

    private var filteredOfferings: [String] {
        // Split on commas so "A, B, C" becomes three separate brands
        newOfferings
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func saveMezcals() {
        isSaving = true
        Task {
            let success = await spotService.addMezcalOfferings(spotID: spot.id, newOfferings: filteredOfferings)
            isSaving = false
            if success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                showSuccess = true
            }
        }
    }
}

// MARK: - Add Category Sheet

/// Sheet presented from SpotDetailView that lets the user add one of their active
/// picks to an existing confirmed spot.
///
/// Cache-first strategy:
///   1. If the spot has a stored websiteURL and it was already scanned this session,
///      return the cached result instantly (zero network calls).
///   2. Otherwise run a targeted checkWithBraveSearch() for just the selected category.
///      Max ~3 Brave calls, same as a normal ghost-pin tap.
struct AddCategorySheet: View {
    let spot: Spot
    /// Picks the user has that this spot doesn't already have
    let addablePicks: [FoodCategory]
    let websiteChecker: WebsiteCheckService

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPick: FoodCategory? = nil
    @State private var checkResult: WebsiteCheckResult? = nil
    @State private var isChecking = false
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var checkTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Spot header
                    Text(spot.name)
                        .font(.title3)
                        .fontWeight(.bold)
                    Label(spot.address, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Already-confirmed categories on this spot
                    HStack(spacing: 6) {
                        ForEach(spot.categories) { cat in
                            HStack(spacing: 4) {
                                if let foodCat = FoodCategory(spotCategory: cat) {
                                    FoodCategoryIcon(category: foodCat, size: 16)
                                } else {
                                    Text(cat.emoji).font(.system(size: 13))
                                }
                                Text(cat.displayName)
                            }
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(cat.color.opacity(0.12))
                            .foregroundStyle(cat.color)
                            .clipShape(Capsule())
                        }
                    }

                    Divider()

                    Text("Which category would you like to add?")
                        .font(.headline)

                    // Selectable pick cards
                    VStack(spacing: 10) {
                        ForEach(addablePicks) { pick in
                            Button {
                                selectPick(pick)
                            } label: {
                                HStack(spacing: 14) {
                                    FoodCategoryIcon(category: pick, size: 28)
                                        .frame(width: 50, height: 50)
                                        .background(selectedPick == pick
                                                    ? pick.color.opacity(0.2)
                                                    : Color(.systemGray6))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selectedPick == pick ? pick.color : Color.clear, lineWidth: 2)
                                        )

                                    Text(pick.displayName)
                                        .font(.headline)
                                        .foregroundStyle(selectedPick == pick ? pick.color : .primary)

                                    Spacer()

                                    if selectedPick == pick {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(pick.color)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selectedPick == pick
                                              ? pick.color.opacity(0.07)
                                              : Color(.systemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(selectedPick == pick
                                                        ? pick.color.opacity(0.3)
                                                        : Color(.systemGray4).opacity(0.5),
                                                        lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: selectedPick)
                        }
                    }

                    // Website check result banner
                    if let pick = selectedPick {
                        websiteCheckBanner(for: pick)
                            .padding(.top, 4)
                    }

                    // Confirm button
                    if let pick = selectedPick {
                        Button {
                            confirmCategory(pick)
                        } label: {
                            Group {
                                if isSaving {
                                    ProgressView()
                                } else {
                                    Label("Confirm — add \(pick.displayName) to this spot",
                                          systemImage: "plus.circle.fill")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(pick.color)
                        .disabled(isSaving || isChecking)
                    }
                }
                .padding()
            }
            .navigationTitle("Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                selectedPick = addablePicks.first
                if let first = addablePicks.first { runCheck(for: first) }
            }
            .onDisappear {
                checkTask?.cancel()
            }
            .alert("Category Added!", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                if let pick = selectedPick {
                    Text("\(pick.displayName) has been added to \(spot.name).")
                }
            }
        }
    }

    // MARK: - Website check banner

    @ViewBuilder
    private func websiteCheckBanner(for pick: FoodCategory) -> some View {
        let (icon, color, message): (String, Color, String) = {
            if isChecking {
                return ("magnifyingglass", .secondary, "Checking their website for \(pick.displayName.lowercased())…")
            }
            switch checkResult {
            case .confirmed:
                return ("checkmark.seal.fill", pick.color,
                        "We found a mention of \(pick.displayName.lowercased()) on their website.")
            case .notFound:
                return ("questionmark.circle", .secondary,
                        "No mention of \(pick.displayName.lowercased()) found online — but menus aren't always posted.")
            case .unavailable:
                return ("wifi.slash", .secondary, "No website found. Add based on your visit.")
            case nil:
                return ("magnifyingglass", .secondary, "Checking their website…")
            }
        }()

        Label(message, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(color)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func selectPick(_ pick: FoodCategory) {
        guard pick != selectedPick else { return }
        selectedPick = pick
        checkResult = nil
        runCheck(for: pick)
    }

    /// Cache-first website check — no network if URL was already scanned this session.
    private func runCheck(for pick: FoodCategory) {
        checkTask?.cancel()
        checkResult = nil
        isChecking = true

        checkTask = Task {
            // Level 1: cache lookup (async actor call, no network)
            if let urlString = spot.websiteURL {
                let cached = await websiteChecker.cachedResult(for: urlString, pick: pick)
                if let cached {
                    guard !Task.isCancelled else { return }
                    checkResult = cached
                    isChecking = false
                    return
                }
            }

            // Level 2: full targeted check (uses Brave Search only if HTML scan misses)
            // Reconstruct a minimal MKMapItem from stored spot data.
            let placemark = MKPlacemark(coordinate: spot.coordinate, addressDictionary: nil)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = spot.name

            let result = await websiteChecker.checkWithBraveSearch(
                mapItem, for: pick, knownURL: spot.websiteURL
            )
            guard !Task.isCancelled else { return }
            checkResult = result
            isChecking = false
        }
    }

    private func confirmCategory(_ pick: FoodCategory) {
        guard let spotCat = SpotCategory(rawValue: pick.id) else { return }
        isSaving = true
        Task {
            let success = await spotService.addCategories(spotID: spot.id, newCategories: [spotCat])
            await MainActor.run {
                isSaving = false
                if success {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showSuccess = true
                }
            }
        }
    }
}
