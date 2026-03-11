import SwiftUI
import MapKit

struct SpotDetailView: View {
    let spot: Spot
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var photoService: PhotoService
    @EnvironmentObject var picksService: UserPicksService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showReportSpotAlert = false
    @State private var showReportConfirmation = false
    @State private var showAddOfferings = false
    @State private var addOfferingsCategory: SpotCategory = .mezcal
    // Add-category state
    @State private var showAddCategory = false
    @State private var isConfirmingVisit = false
    @State private var showVisitConfirmed = false

    // Community verification
    @StateObject private var verificationService = VerificationService()

    // Remove-category state
    @State private var categoryToRemove: SpotCategory?
    @State private var showRemoveCategoryAlert = false
    @State private var showRemoveCategoryFailed = false

    // Closure reporting
    @State private var showClosureReportAlert = false
    @State private var showClosureReportConfirmation = false
    @State private var showClosureReportFailed = false
    @State private var isSubmittingClosureReport = false

    // Sign-in gate
    @State private var showSignIn = false
    /// Tracks what the user tried to do before sign-in so we can auto-proceed.
    @State private var pendingDetailAction: PendingDetailAction? = nil

    private enum PendingDetailAction {
        case addFlezcal
        case addOfferings(SpotCategory)
        case reportSpot
        case reportClosure
        case confirmVisit
    }

    // Owner editing
    @State private var showOwnerEdit = false

    /// Live version of this spot from SpotService, reflecting any in-session mutations
    /// (e.g. isCommunityVerified flip, report updates). Falls back to the original `let spot`.
    private var liveSpot: Spot {
        spotService.spots.first { $0.id == spot.id } ?? spot
    }

    /// Best available photo URL for the hero image
    private var displayPhotoURL: String? { liveSpot.displayPhotoURL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hero image — shows auto photo if available, otherwise map preview
                    Group {
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
                    }
                    .padding(.horizontal)

                    // Info section
                    VStack(alignment: .leading, spacing: 12) {
                        // ── Import-provenance banners ──────────────────────────
                        if liveSpot.source != nil {
                            importedSpotBanner
                        }

                        // Consolidated Flezcal section — verification + ratings in one place
                        if !liveSpot.isClosed {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(liveSpot.categories) { category in
                                    FlezcalRowView(
                                        spot: liveSpot,
                                        category: category,
                                        verificationService: verificationService,
                                        canRemove: authService.isSignedIn
                                            && (AdminAccess.isAdmin(uid: authService.userID)
                                                || liveSpot.canRemoveCategory(category, userID: authService.userID)),
                                        onRemoveCategory: {
                                            categoryToRemove = category
                                            showRemoveCategoryAlert = true
                                        }
                                    )
                                    if category != liveSpot.categories.last {
                                        Divider()
                                    }
                                }

                                // "Add a Flezcal" button — visible to all users
                                let allAddable = SpotCategory.allCases.filter { cat in
                                    !cat.isLegacy && !liveSpot.categories.contains(cat)
                                }
                                if !allAddable.isEmpty {
                                    Divider()
                                    Button {
                                        if authService.isSignedIn {
                                            showAddCategory = true
                                        } else {
                                            pendingDetailAction = .addFlezcal
                                            showSignIn = true
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.body)
                                                .foregroundStyle(.orange)
                                            Text("Add a Flezcal")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundStyle(.orange)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Add a category to \(liveSpot.name)")
                                    .accessibilityHint("Double tap to choose a food or drink category to add")
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color(.systemGray6).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Fun badges row
                        if liveSpot.isHiddenGem || liveSpot.isRecentlyVerified {
                            HStack(spacing: 6) {
                                if liveSpot.isHiddenGem {
                                    SpotBadge(emoji: "💎", label: "Hidden Gem", color: .blue)
                                }
                                if liveSpot.isRecentlyVerified {
                                    SpotBadge(emoji: "✨", label: "New", color: .green)
                                }
                                Spacer()
                            }
                        }

                        // Owner Verified badge
                        if liveSpot.isOwnerVerified {
                            OwnerVerifiedBadge()
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

                        // Closure status banners
                        if liveSpot.isClosed {
                            Label("Permanently Closed", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if liveSpot.closureReportCount > 0 {
                            Label("Closure reported — accuracy may be uncertain",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Owner details section (brands, details, reservation)
                        if liveSpot.isOwnerVerified {
                            ownerDetailsSection
                        }

                        // Offerings per category
                        ForEach(liveSpot.categories) { cat in
                            let catOfferings = liveSpot.offerings(for: cat)
                            let isLocked = liveSpot.isCategoryLocked(cat)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(cat.offeringsLabel)
                                        .font(.headline)
                                    if isLocked {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                            .help("Locked by owner")
                                            .accessibilityLabel("Category locked by owner")
                                    }
                                    Spacer()
                                    if !isLocked {
                                        Button {
                                            if authService.isSignedIn {
                                                addOfferingsCategory = cat
                                                showAddOfferings = true
                                            } else {
                                                pendingDetailAction = .addOfferings(cat)
                                                showSignIn = true
                                            }
                                        } label: {
                                            Label("Add", systemImage: "plus.circle")
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(.top, 4)

                                if !catOfferings.isEmpty {
                                    ForEach(catOfferings, id: \.self) { item in
                                        HStack(spacing: 6) {
                                            CategoryIcon(category: cat, size: 16)
                                            Text(item)
                                                .font(.subheadline)
                                        }
                                    }
                                } else {
                                    Text("No \(cat.offeringSingular)s listed yet. Be the first to add some!")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // (Add-category button is now inside the Flezcal card above)
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
                    }
                    .padding(.horizontal)

                    // Owner "Edit Your Spot" button
                    if liveSpot.isOwner(userID: authService.userID) {
                        Button {
                            showOwnerEdit = true
                        } label: {
                            Label("Edit Your Spot", systemImage: "pencil.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .padding(.horizontal)
                        .accessibilityLabel("Edit your spot details for \(liveSpot.name)")
                    }

                    // "Own this spot?" teaser — shown on non-owner-verified spots
                    if !liveSpot.isOwnerVerified {
                        ownThisSpotTeaser
                    }

                    // Report spot button — visible to all users
                    HStack {
                        Spacer()
                        if authService.isSignedIn {
                            let userID = authService.userID ?? ""
                            let alreadyReported = liveSpot.reportedByUserIDs.contains(userID)
                            let isOwnSpot = liveSpot.addedByUserID == userID

                            if isOwnSpot {
                                EmptyView()
                            } else if alreadyReported {
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
                        } else {
                            Button {
                                pendingDetailAction = .reportSpot
                                showSignIn = true
                            } label: {
                                Label("Report Spot", systemImage: "flag")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    // Report as permanently closed — visible to all users
                    if !liveSpot.isClosed {
                        HStack {
                            Spacer()
                            Button {
                                if authService.isSignedIn {
                                    showClosureReportAlert = true
                                } else {
                                    pendingDetailAction = .reportClosure
                                    showSignIn = true
                                }
                            } label: {
                                Label("Report as permanently closed", systemImage: "building.2.crop.circle")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    Divider()
                        .padding(.horizontal)
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
            .sheet(isPresented: $showAddOfferings) {
                AddOfferingsSheet(spot: liveSpot, category: addOfferingsCategory)
            }
            .sheet(isPresented: $showOwnerEdit) {
                OwnerEditSheet(spot: liveSpot)
            }
            .sheet(isPresented: $showAddCategory) {
                AddFlezcalFlow(spot: liveSpot)
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .environmentObject(authService)
                    .presentationDetents([.medium])
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                if signedIn, let action = pendingDetailAction {
                    pendingDetailAction = nil
                    // Small delay so the sign-in sheet finishes dismissing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        switch action {
                        case .addFlezcal:
                            showAddCategory = true
                        case .addOfferings(let cat):
                            addOfferingsCategory = cat
                            showAddOfferings = true
                        case .reportSpot:
                            showReportSpotAlert = true
                        case .reportClosure:
                            showClosureReportAlert = true
                        case .confirmVisit:
                            confirmVisit()
                        }
                    }
                }
            }
            .task {
                AnalyticsService.shared.logSpotView(spotID: spot.id)
                await verificationService.fetchVerifications(for: spot.id)

                // Backfill: migrate legacy reviews → verifications (idempotent)
                do {
                    let migrationReviewService = ReviewService()
                    await migrationReviewService.fetchReviews(for: spot.id)
                    let reviews = migrationReviewService.reviews
                    if !reviews.isEmpty {
                        await verificationService.migrateReviewsToVerifications(
                            spotID: spot.id,
                            reviews: reviews,
                            spotService: spotService
                        )
                    }
                }

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
            .alert("Report as Permanently Closed", isPresented: $showClosureReportAlert) {
                Button("Yes, report it", role: .destructive) {
                    Task {
                        isSubmittingClosureReport = true
                        let service = ClosureReportService()
                        let success = await service.submitReport(
                            spotID: spot.id,
                            spotName: spot.name,
                            spotAddress: spot.address,
                            reporterUserID: authService.userID ?? ""
                        )
                        isSubmittingClosureReport = false
                        if success {
                            showClosureReportConfirmation = true
                        } else {
                            showClosureReportFailed = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure this location has permanently closed? This will be reviewed by our team.")
            }
            .alert("Closure Report Submitted", isPresented: $showClosureReportConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Thank you for letting us know. We'll review this report and take appropriate action.")
            }
            .alert("Report Failed", isPresented: $showClosureReportFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't submit the report. Please wait a moment and try again.")
            }
            .alert(
                liveSpot.categories.count <= 1 ? "Remove Spot" : "Remove Category",
                isPresented: $showRemoveCategoryAlert
            ) {
                Button("Remove", role: .destructive) {
                    if let cat = categoryToRemove {
                        Task {
                            if liveSpot.categories.count <= 1 {
                                // Last category — hide the spot entirely
                                await spotService.hideSpot(spotID: spot.id)
                                dismiss()
                            } else {
                                let success: Bool
                                if AdminAccess.isAdmin(uid: authService.userID) {
                                    success = await spotService.adminRemoveCategory(spotID: spot.id, category: cat)
                                } else {
                                    success = await spotService.removeCategory(spotID: spot.id, category: cat)
                                }
                                if !success {
                                    showRemoveCategoryFailed = true
                                }
                                #if DEBUG
                                print("[SpotDetail] removeCategory(\(cat.rawValue)) from \(spot.name): \(success ? "✅" : "❌")")
                                if success {
                                    let updatedSpot = spotService.spots.first(where: { $0.id == spot.id })
                                    print("[SpotDetail]   categories after: \(updatedSpot?.categories.map(\.rawValue) ?? [])")
                                }
                                #endif
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    categoryToRemove = nil
                }
            } message: {
                if let cat = categoryToRemove {
                    if liveSpot.categories.count <= 1 {
                        Text("This is the only category on \(spot.name). Removing \(cat.displayName) will hide the spot. It can be re-added later.")
                    } else {
                        Text("Remove \(cat.displayName) from \(spot.name)? This can be re-added later.")
                    }
                }
            }
            .alert("Removal Failed", isPresented: $showRemoveCategoryFailed) {
                Button("OK") {}
            } message: {
                Text("Could not remove the category. The change may not have been saved to the server.")
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
        .accessibilityLabel("Map showing location of \(spot.name)")
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
            if !liveSpot.isCommunityVerified {
                // ── Amber: awaiting first real check-in ──
                VStack(alignment: .leading, spacing: 6) {
                    Label("Curated listing — not yet visited by a Flezcal member",
                          systemImage: "clock.badge.questionmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)

                    Button {
                        if authService.isSignedIn {
                            confirmVisit()
                        } else {
                            pendingDetailAction = .confirmVisit
                            showSignIn = true
                        }
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
            Button("Done", role: .cancel) {}
        } message: {
            Text("You've confirmed \(spot.name). This helps the whole community!")
        }
    }

    // MARK: - Owner Details Section

    @ViewBuilder
    private var ownerDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Owner brands
            if let brands = liveSpot.ownerBrands, !brands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What They Serve")
                        .font(.headline)

                    FlowLayout(spacing: 8) {
                        ForEach(brands, id: \.self) { brand in
                            Text(brand)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.10))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Owner details text
            if let details = liveSpot.ownerDetails, !details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From the Owner")
                        .font(.headline)

                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Reservation link — uses Button + openURL so we can log the tap
            if let urlString = liveSpot.reservationURL,
               let url = URL(string: urlString) {
                Button {
                    AnalyticsService.shared.logReservationClick(spotID: spot.id)
                    openURL(url)
                } label: {
                    Label("Make a Reservation", systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Make a reservation at \(liveSpot.name)")
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Own This Spot? Teaser

    private var ownThisSpotTeaser: some View {
        let subject = "Owner Verification Request — \(spot.name)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let displayName = authService.displayName
        let body = "I'd like to claim \(spot.name) as the owner/manager. My username is \(displayName)."
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailtoString = "mailto:support@flezcal.app?subject=\(subject)&body=\(body)"

        return HStack {
            Spacer()
            if let url = URL(string: mailtoString) {
                Link(destination: url) {
                    Label("Own this spot? Contact us to claim it.", systemImage: "building.2.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Contact us to claim ownership of \(spot.name)")
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    /// Marks this imported spot as community-verified in Firestore,
    /// then offers a rating flow for the spot's first category.
    private func confirmVisit() {
        isConfirmingVisit = true
        Task {
            await spotService.markCommunityVerified(spotID: spot.id)

            // Auto-verify with a thumbs-up for each category on the spot
            if let userID = authService.userID, let firstCat = liveSpot.categories.first {
                await VerificationService.autoVerify(spotID: spot.id, userID: userID, category: firstCat)
            }

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
                .accessibilityHidden(true)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Add Offerings Sheet (generic for all categories)

struct AddOfferingsSheet: View {
    let spot: Spot
    let category: SpotCategory
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

                    // Existing offerings for this category
                    let existing = spot.offerings(for: category)
                    if !existing.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Already Listed")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            ForEach(existing, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                        }

                        Divider()
                    }

                    // New offerings
                    Text("Add \(category.offeringsLabel)")
                        .font(.headline)

                    Text(category.offeringsExamples)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let knownOfferings = CommunityOfferings.suggestions(for: category, from: spotService.spots)

                    ForEach(newOfferings.indices, id: \.self) { index in
                        HStack {
                            OfferingInputField(
                                text: $newOfferings[index],
                                placeholder: "One \(category.offeringSingular) per field",
                                knownOfferings: knownOfferings,
                                suggestionIcon: category.icon,
                                useVeladoraIcon: category == .mezcal
                            )

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
                        saveOfferings()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Label("Save \(category.offeringsLabel)", systemImage: "checkmark.circle.fill")
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
            .navigationTitle("Add \(category.offeringsLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("\(category.offeringsLabel) Added!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("The \(category.offeringsLabel.lowercased()) for \(spot.name) have been updated.")
            }
        }
    }

    private var filteredOfferings: [String] {
        newOfferings
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func saveOfferings() {
        isSaving = true
        Task {
            let success = await spotService.addOfferings(spotID: spot.id, category: category, newOfferings: filteredOfferings)
            isSaving = false
            if success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                showSuccess = true
            }
        }
    }
}

// MARK: - Add Flezcal Flow

/// Unified flow for adding a Flezcal to an existing spot.
/// Step 1: User picks a category from FlezcalPickerView.
/// Step 2: Category is saved, then rating prompt appears.
/// Step 3: Thank you → dismiss.
private struct AddFlezcalFlow: View {
    let spot: Spot

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var picksService: UserPicksService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFlezcal: FoodCategory? = nil
    @State private var isSaving = false
    @State private var savedCategory: SpotCategory? = nil
    /// Spot already had this category
    @State private var showAlreadyThere = false
    /// Category awaiting user confirmation before saving
    @State private var pendingCategory: FoodCategory? = nil
    @State private var showCategoryConfirmation = false
    /// Trending Flezcals from Firestore
    @StateObject private var customService = CustomCategoryService()
    @State private var showCreateTrending = false
    /// Shows the rating prompt after successfully adding a category.
    @State private var showRatingPrompt = false
    /// Loaded when rating prompt shows — used to submit the rating.
    @StateObject private var verificationService = VerificationService()

    /// Live version of the spot — reflects in-session mutations.
    private var liveSpot: Spot {
        spotService.spots.first { $0.id == spot.id } ?? spot
    }

    /// Category IDs already on this spot — re-computed from live data.
    private var disabledIDs: Set<String> {
        Set(liveSpot.categories.map(\.rawValue))
    }

    var body: some View {
        if showRatingPrompt, let spotCat = savedCategory {
            addFlezcalRatingPrompt(category: spotCat)
        } else {
            FlezcalPickerView(
                userPicks: picksService.picks,
                allCategories: FoodCategory.allCategories,
                disabledCategoryIDs: disabledIDs,
                onSelect: { category in
                    pendingCategory = category
                    showCategoryConfirmation = true
                },
                onCancel: { dismiss() },
                trendingCategories: customService.customCategories.map { $0.toFoodCategory() },
                onCreateTrending: { showCreateTrending = true }
            )
            .task { await customService.fetchAll() }
            .sheet(isPresented: $showCreateTrending) {
                CreateCustomCategoryView()
            }
            .alert("Already Added", isPresented: $showAlreadyThere) {
                Button("Done") { dismiss() }
            } message: {
                if let cat = savedCategory {
                    Text("\(spot.name) already has \(cat.displayName).")
                }
            }
            .alert("Add Flezcal", isPresented: $showCategoryConfirmation) {
                Button("Add") {
                    if let category = pendingCategory {
                        selectedFlezcal = category
                        saveCategory(category)
                    }
                    pendingCategory = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingCategory = nil
                }
            } message: {
                if let category = pendingCategory {
                    Text("Add \(category.emoji) \(category.displayName) to \(spot.name)?")
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("Adding Flezcal...")
                            .padding(24)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func addFlezcalRatingPrompt(category: SpotCategory) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text(spot.name)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("\(category.displayName) added")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                RatingFlowView(
                    categoryName: category.displayName,
                    existingRating: nil,
                    onSubmit: { rating in
                        guard let userID = authService.userID else {
                            dismiss()
                            return
                        }
                        Task {
                            await verificationService.fetchVerifications(for: spot.id)
                            let _ = await verificationService.submitRating(
                                spotID: spot.id, userID: userID,
                                category: category, rating: rating,
                                spotService: spotService
                            )
                            dismiss()
                        }
                    },
                    onSkip: { dismiss() },
                    onRemove: nil
                )
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Rate This Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }

    private func saveCategory(_ category: FoodCategory) {
        guard let userID = authService.userID else { return }
        isSaving = true

        Task {
            var success = false
            var alreadyHadCategory = false

            // Save curated category via addCategories
            let spotCat = SpotCategory(rawValue: category.id)
            savedCategory = spotCat

            // Check if category already exists on the live spot
            if liveSpot.categories.contains(spotCat) {
                alreadyHadCategory = true
                success = true
            } else {
                success = await spotService.addCategories(
                    spotID: spot.id,
                    newCategories: [spotCat],
                    addedBy: userID
                )
                if success {
                    // Auto-create verification (bug fix: old AddCategorySheet was missing this)
                    await VerificationService.autoVerify(spotID: spot.id, userID: userID, category: spotCat)
                }
            }

            await MainActor.run {
                isSaving = false
                if alreadyHadCategory {
                    showAlreadyThere = true
                } else if success {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    withAnimation { showRatingPrompt = true }
                }
            }
        }
    }

}

// MARK: - Owner Verified Badge

struct OwnerVerifiedBadge: View {
    private let goldColor = Color(red: 0.82, green: 0.66, blue: 0.24)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
            Text("Owner Verified")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(goldColor.opacity(0.15))
        .foregroundStyle(goldColor)
        .clipShape(Capsule())
        .accessibilityLabel("Owner verified spot")
    }
}

// MARK: - Owner Edit Sheet

struct OwnerEditSheet: View {
    let spot: Spot
    @EnvironmentObject var spotService: SpotService
    @Environment(\.dismiss) private var dismiss

    @State private var brands: [String]
    @State private var details: String
    @State private var reservationURL: String
    @State private var lockedCategories: Set<String>
    @State private var newBrand: String = ""
    @State private var isSaving = false
    @State private var showSuccess = false

    init(spot: Spot) {
        self.spot = spot
        _brands = State(initialValue: spot.ownerBrands ?? [])
        _details = State(initialValue: spot.ownerDetails ?? "")
        _reservationURL = State(initialValue: spot.reservationURL ?? "")
        _lockedCategories = State(initialValue: Set(spot.ownerLockedCategories ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Brands section
                Section {
                    ForEach(brands, id: \.self) { brand in
                        HStack {
                            Text(brand)
                            Spacer()
                            Button {
                                brands.removeAll { $0 == brand }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Add a brand or product", text: $newBrand)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addBrand() }

                        Button {
                            addBrand()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        .disabled(newBrand.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Brands & Products")
                } footer: {
                    Text("Highlight the brands, varieties, or products you want customers to know about.")
                }

                // Details section
                Section {
                    TextEditor(text: $details)
                        .frame(minHeight: 100)
                } header: {
                    Text("About Your Spot")
                } footer: {
                    Text("Share your story, hours, specialties, or anything you want customers to know.")
                }

                // Reservation URL
                Section {
                    TextField("https://yoursite.com/reserve", text: $reservationURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Reservation Link")
                } footer: {
                    Text("Add a link to your reservation system (OpenTable, Resy, your website, etc.)")
                }

                // Locked categories
                Section {
                    ForEach(spot.categories) { cat in
                        Toggle(isOn: Binding(
                            get: { lockedCategories.contains(cat.rawValue) },
                            set: { isOn in
                                if isOn {
                                    lockedCategories.insert(cat.rawValue)
                                } else {
                                    lockedCategories.remove(cat.rawValue)
                                }
                            }
                        )) {
                            HStack(spacing: 6) {
                                CategoryIcon(category: cat, size: 16)
                                Text(cat.displayName)
                            }
                        }
                        .tint(.orange)
                    }
                } header: {
                    Text("Lock Categories")
                } footer: {
                    Text("Locked categories prevent community members from editing the offerings you've set. You can still edit them yourself.")
                }
            }
            .navigationTitle("Edit Your Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .alert("Changes Saved", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your spot information has been updated.")
            }
        }
    }

    private func addBrand() {
        let trimmed = newBrand.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !brands.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            brands.append(trimmed)
        }
        newBrand = ""
    }

    private func save() {
        isSaving = true
        Task {
            let success = await spotService.updateOwnerFields(
                spotID: spot.id,
                ownerBrands: brands.isEmpty ? nil : brands,
                ownerDetails: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details.trimmingCharacters(in: .whitespacesAndNewlines),
                reservationURL: reservationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reservationURL.trimmingCharacters(in: .whitespacesAndNewlines),
                ownerLockedCategories: lockedCategories.isEmpty ? nil : Array(lockedCategories)
            )
            isSaving = false
            if success {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                showSuccess = true
            }
        }
    }
}

// MARK: - Flow Layout (for brand chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalSize: CGSize = .zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalSize.width = max(totalSize.width, currentX - spacing)
        }

        totalSize.height = currentY + lineHeight
        return LayoutResult(positions: positions, size: totalSize)
    }
}
