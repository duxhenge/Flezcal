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

            Text("Welcome to \(AppConstants.appName)")
                .font(.title2)
                .fontWeight(.semibold)

            Text(AppConstants.appTagline)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Sign in to add flan and mezcal spots, leave reviews, and discover new favorites.")
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
    var onShowWhatsNew: (() -> Void)? = nil
    @State private var showSignOutConfirmation = false
    @State private var showEditName = false
    @State private var editedName = ""
    @State private var isSavingName = false
    @State private var myStats: ContributorStats?
    @State private var myRank: Int?

    var body: some View {
        List {
            // User info section
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)

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

                    Label("Mezcal Brands Listed", systemImage: "list.bullet")
                        .badge("\(stats.mezcalBrandsAdded)")

                    Label("Reviews Written", systemImage: "star.bubble")
                        .badge("\(stats.reviewsWritten)")
                }
            } else {
                // Fallback while loading
                Section("Activity") {
                    Label("Spots Added", systemImage: "mappin.circle")
                        .badge("--")
                    Label("Reviews Written", systemImage: "star.bubble")
                        .badge("--")
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

                Link(destination: AppConstants.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
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
        .task {
            await loadStats()
        }
    }

    private func saveDisplayName() {
        let name = editedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let user = authService.user else { return }
        isSavingName = true
        Task { @MainActor in
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = name
            try? await changeRequest.commitChanges()
            try? await user.reload()
            // Reload from FirebaseAuth to pick up the new displayName
            authService.user = FirebaseAuth.Auth.auth().currentUser
            isSavingName = false
        }
    }

    private func loadStats() async {
        guard let userID = authService.userID else { return }
        await reviewService.fetchAllReviews()

        myStats = ContributorStatsBuilder.buildForUser(
            userID: userID,
            spots: spotService.spots,
            reviews: reviewService.allReviews,
            displayName: authService.displayName
        )

        let allStats = ContributorStatsBuilder.buildAll(
            spots: spotService.spots,
            reviews: reviewService.allReviews
        )
        myRank = ContributorStatsBuilder.rankPosition(userID: userID, allStats: allStats)
    }
}

#Preview("Signed Out") {
    ProfileView()
        .environmentObject(AuthService())
}
