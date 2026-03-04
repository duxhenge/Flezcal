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

                // Activity breakdown
                Section("Your Contributions") {
                    Label("Spots Added", systemImage: "mappin.circle")
                        .badge("\(stats.spotsAdded)")

                    HStack {
                        FlanIcon(size: 20)
                        Text("Flan Spots")
                        Spacer()
                        Text("\(stats.flanSpotsAdded)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        VeladoraIcon(size: 20)
                        Text("Mezcal Spots")
                        Spacer()
                        Text("\(stats.mezcalSpotsAdded)")
                            .foregroundStyle(.secondary)
                    }

                    Label("Brands Listed", systemImage: "list.bullet")
                        .badge("\(stats.brandsLogged)")

                    Label("Ratings Given", systemImage: "flame")
                        .badge("\(stats.ratingsGiven)")
                }
            } else {
                // Fallback while loading
                Section("Activity") {
                    Label("Spots Added", systemImage: "mappin.circle")
                        .badge("--")
                    Label("Ratings Given", systemImage: "flame")
                        .badge("--")
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

                                    // Thumbs icon
                                    Image(systemName: verification.vote ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                        .foregroundStyle(verification.vote ? .green : .red)
                                        .font(.caption)

                                    // Rating if present
                                    if let rating = verification.rating {
                                        HStack(spacing: 1) {
                                            Text("🍮")
                                                .font(.caption2)
                                            Text("\(rating)")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
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
                    .onLongPressGesture(minimumDuration: 2) {
                        if AdminAccess.isAdmin(uid: authService.userID) {
                            showAdmin = true
                        }
                    }

                Link(destination: AppConstants.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .foregroundStyle(.primary)

                Link(destination: AppConstants.termsURL) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                .foregroundStyle(.primary)
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
}

#Preview("Signed Out") {
    ProfileView()
        .environmentObject(AuthService())
}
