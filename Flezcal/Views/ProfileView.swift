import SwiftUI
import AuthenticationServices
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    var onShowWhatsNew: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if authService.isLoading {
                    ProgressView("Loading...")
                } else if authService.isSignedIn {
                    SignedInProfileView(onShowWhatsNew: onShowWhatsNew)
                } else {
                    SignedOutProfileView(onShowWhatsNew: onShowWhatsNew)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Signed Out View

struct SignedOutProfileView: View {
    @EnvironmentObject var authService: AuthService
    var onShowWhatsNew: (() -> Void)? = nil
    @State private var showEmailAuth = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Welcome to \(AppConstants.appName)")
                .font(.title2)
                .fontWeight(.semibold)

            Text(AppConstants.appTagline)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Sign in to add spots, rate your favorite finds, and discover new favorites.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Sign in with Apple button
            SignInWithAppleButton(.signIn) { request in
                authService.handleSignInWithAppleRequest(request)
            } onCompletion: { result in
                authService.handleSignInWithAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)
            .padding(.top, 8)

            // Divider
            HStack {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.secondary.opacity(0.3))
                Text("or")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.secondary.opacity(0.3))
            }
            .padding(.horizontal, 40)

            // Email sign in button
            Button {
                showEmailAuth = true
            } label: {
                Label("Continue with Email", systemImage: "envelope")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .padding(.horizontal, 40)

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                onShowWhatsNew?()
            } label: {
                Label("What's New ✨", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Spacer()
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView()
        }
    }
}

// MARK: - Signed In View

struct SignedInProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @StateObject private var reviewService = ReviewService()
    @StateObject private var verificationService = VerificationService()
    var onShowWhatsNew: (() -> Void)? = nil
    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var showReauthAlert = false
    @State private var showEditName = false
    @State private var editedName = ""
    @State private var isSavingName = false
    @State private var myStats: ContributorStats?
    @State private var myRank: Int?
    @State private var showAdmin = false
    @State private var userVerifications: [Verification] = []

    var body: some View {
        List {
            // User info section
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(authService.displayName)
                            .font(.headline)

                        if let email = authService.user?.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)

                Button {
                    editedName = authService.user?.displayName ?? ""
                    showEditName = true
                } label: {
                    Label("Change Display Name", systemImage: "pencil")
                        .font(.subheadline)
                }
            }

            // Contributor rank section
            if let stats = myStats {
                Section("Contributor Rank") {
                    HStack {
                        Image(systemName: stats.rankIcon)
                            .font(.title2)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stats.rankTitle)
                                .font(.headline)
                            if let rank = myRank {
                                Text("Rank #\(rank) \u{2022} \(stats.score) points")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("\(stats.score) pts")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                }

                // Your Impact — redesigned contributions section
                Section("Your Impact") {
                    // Group 1: Next Rank Progress
                    rankProgressRow(stats: stats)

                    // Group 2: Score Breakdown Grid
                    scoreBreakdownRow(stats: stats)

                    // Group 3: Top Flezcals Pills
                    topCategoriesRow(stats: stats)

                    // Group 4: Brands & Offerings Collector badge
                    if stats.brandsLogged > 0 {
                        brandCollectorRow(stats: stats)
                    }
                }
            } else {
                // Zero-state while loading or no activity
                Section("Your Impact") {
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle")
                            .font(.title)
                            .foregroundStyle(.orange.opacity(0.5))

                        Text("Start Your Journey")
                            .font(.headline)

                        Text("Add your first spot, rate a find, or verify a listing to begin climbing the ranks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }

            // Verification & Rating history
            if !userVerifications.isEmpty {
                Section("Your Verifications & Ratings") {
                    ForEach(userVerifications.prefix(20)) { verification in
                        if let cat = SpotCategory(rawValue: verification.category) {
                            let spotName = spotService.spots.first(where: { $0.id == verification.spotID })?.name ?? "Unknown Spot"
                            NavigationLink {
                                if let spot = spotService.spots.first(where: { $0.id == verification.spotID }) {
                                    SpotDetailView(spot: spot)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(cat.emoji)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Text(spotName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if verification.vote {
                                        // Rated or confirmed (legacy)
                                        if let rating = verification.rating {
                                            HStack(spacing: 1) {
                                                Text("🍮")
                                                    .font(.caption2)
                                                    .accessibilityHidden(true)
                                                Text("\(rating)")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel("Rated \(rating) out of 5")
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.caption)
                                                .accessibilityLabel("Confirmed")
                                        }
                                    } else {
                                        // Marked as unavailable
                                        HStack(spacing: 2) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.orange)
                                                .font(.caption)
                                            Text("Unavailable")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("Reported as unavailable")
                                    }

                                    // Date
                                    Text(verification.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }

            // About section
            Section("About") {
                Button {
                    onShowWhatsNew?()
                } label: {
                    Label("What's New ✨", systemImage: "sparkles")
                }
                .foregroundStyle(.primary)

                Label("Version", systemImage: "info.circle")
                    .badge(AppConstants.appVersion)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 2) {
                        if AdminAccess.isAdmin(uid: authService.userID) {
                            showAdmin = true
                        }
                    }

                Link(destination: AppConstants.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .foregroundStyle(.primary)
                .accessibilityHint("Opens privacy policy in browser")

                Link(destination: AppConstants.termsURL) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                .foregroundStyle(.primary)
                .accessibilityHint("Opens terms of service in browser")
            }

            // Sign out
            Section {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            // Delete account
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if isDeletingAccount {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Deleting account...")
                        }
                    } else {
                        Label("Delete Account", systemImage: "trash")
                    }
                }
                .disabled(isDeletingAccount)
            }
        }
        .fullScreenCover(isPresented: $showAdmin) {
            AdminDashboardView()
                .environmentObject(spotService)
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                authService.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out of \(AppConstants.appName)?")
        }
        .alert("Display Name", isPresented: $showEditName) {
            TextField("Your name", text: $editedName)
                .autocorrectionDisabled()
            Button("Save") {
                saveDisplayName()
            }
            .disabled(editedName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This name appears on the leaderboard.")
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Delete Everything", role: .destructive) {
                performAccountDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all associated data (ratings, spots, verifications). This cannot be undone.")
        }
        .alert("Sign In Again", isPresented: $showReauthAlert) {
            Button("OK", role: .cancel) {
                authService.signOut()
            }
        } message: {
            Text("For security, please sign in again and then retry deleting your account.")
        }
        .task {
            await loadStats()
        }
    }

    private func performAccountDeletion() {
        isDeletingAccount = true
        Task {
            do {
                try await authService.deleteAccount()
            } catch {
                isDeletingAccount = false
                let code = (error as NSError).code
                if code == AuthErrorCode.requiresRecentLogin.rawValue {
                    showReauthAlert = true
                } else {
                    authService.errorMessage = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveDisplayName() {
        let name = editedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSavingName = true
        Task { @MainActor in
            await authService.saveDisplayNameToFirestore(name)
            isSavingName = false
        }
    }

    private func loadStats() async {
        guard let userID = authService.userID else { return }
        await reviewService.fetchAllReviews()

        // Fetch user's verification history for the profile section
        let fetchedVerifications = await verificationService.fetchUserVerifications(userID: userID)
        userVerifications = fetchedVerifications

        myStats = ContributorStatsBuilder.buildForUser(
            userID: userID,
            spots: spotService.spots,
            reviews: reviewService.allReviews,
            verifications: fetchedVerifications,
            displayName: authService.displayName
        )

        // Fetch all verifications for leaderboard ranking
        await verificationService.fetchAllVerifications()

        let allStats = ContributorStatsBuilder.buildAll(
            spots: spotService.spots,
            reviews: reviewService.allReviews,
            verifications: verificationService.allVerifications
        )
        myRank = ContributorStatsBuilder.rankPosition(userID: userID, allStats: allStats)
    }

    // MARK: - Your Impact Groups

    /// Group 1: Progress bar toward the next rank
    @ViewBuilder
    private func rankProgressRow(stats: ContributorStats) -> some View {
        let current = RankConfig.currentLevel(for: stats.score)

        if let next = RankConfig.nextLevel(for: stats.score) {
            // Show progress toward next rank
            let progressValue = Double(stats.score - current.minScore)
            let progressTotal = Double(next.minScore - current.minScore)
            let remaining = next.minScore - stats.score

            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: current.icon)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(current.title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text(next.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Image(systemName: next.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: progressValue, total: progressTotal)
                    .tint(.orange)

                if stats.score == 0 {
                    Text("Add a spot or rate a find to get started!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(stats.score) / \(next.minScore) pts \u{2022} \(remaining) pts to \(next.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } else {
            // Max rank achieved
            HStack {
                Image(systemName: current.icon)
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title)
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Maximum rank achieved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(stats.score) pts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 4)
        }
    }

    /// Group 2: 5-column score breakdown showing all scoring activities
    @ViewBuilder
    private func scoreBreakdownRow(stats: ContributorStats) -> some View {
        HStack(spacing: 0) {
            ImpactStat(
                icon: "mappin.circle.fill",
                value: stats.spotsAdded,
                label: "Spots",
                points: "+10 ea",
                isHighValue: true
            )
            Spacer()
            ImpactStat(
                icon: "tag.fill",
                value: stats.categoriesIdentified,
                label: "Finds",
                points: "+3 ea",
                isHighValue: true
            )
            Spacer()
            ImpactStat(
                icon: "flame.fill",
                value: stats.ratingsGiven,
                label: "Ratings",
                points: "+5 ea",
                isHighValue: true
            )
            Spacer()
            ImpactStat(
                icon: "list.bullet",
                value: stats.brandsLogged,
                label: "Brands",
                points: "+1 ea",
                isHighValue: false
            )
            Spacer()
            ImpactStat(
                icon: "checkmark.circle.fill",
                value: stats.verificationsGiven,
                label: "Confirms",
                points: "+1 ea",
                isHighValue: false
            )
        }
        .padding(.vertical, 4)
    }

    /// Group 3: Top categories as colored capsule pills
    @ViewBuilder
    private func topCategoriesRow(stats: ContributorStats) -> some View {
        let topCats = stats.topCategories(3)

        VStack(alignment: .leading, spacing: 8) {
            Text("Your Top Finds")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if topCats.isEmpty {
                Text("Add a spot to see your top categories here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(topCats, id: \.id) { entry in
                        if let cat = SpotCategory(rawValue: entry.id) {
                            HStack(spacing: 4) {
                                Text(cat.emoji)
                                    .font(.callout)
                                Text(cat.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("\u{00D7}\(entry.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(cat.color.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Group 4: Brands & Offerings Collector badge with progress
    @ViewBuilder
    private func brandCollectorRow(stats: ContributorStats) -> some View {
        let threshold = RankConfig.brandCollectorThreshold

        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(stats.isBrandCollector ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Brands & Offerings Collector")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if stats.isBrandCollector {
                    Text("\(stats.brandsLogged) unique brands logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Log \(threshold - stats.brandsLogged) more to earn!")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ProgressView(value: Double(stats.brandsLogged), total: Double(threshold))
                        .tint(.orange)
                }
            }

            Spacer()

            if stats.isBrandCollector {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            } else {
                Text("\(stats.brandsLogged)/\(threshold)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(stats.isBrandCollector ? Color.green.opacity(0.08) : Color.orange.opacity(0.06))
        )
        .padding(.vertical, 4)
    }
}

// MARK: - Impact Stat

/// Compact vertical stat column used in the score breakdown grid.
private struct ImpactStat: View {
    let icon: String
    let value: Int
    let label: String
    let points: String
    let isHighValue: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isHighValue ? .orange : .secondary)
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(points)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label), \(points)")
    }
}

#Preview("Signed Out") {
    ProfileView()
        .environmentObject(AuthService())
}
