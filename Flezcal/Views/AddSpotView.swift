import SwiftUI
import AuthenticationServices
import MapKit

struct AddSpotView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var photoService: PhotoService
    @State private var showSearch = false
    @State private var showEmailAuth = false
    /// The pick the user has selected to add a spot for.
    /// Defaults to the first active pick on appear.
    @State private var selectedPick: FoodCategory? = nil

    /// The SpotCategory matching the selected pick. Always succeeds —
    /// SpotCategory now covers all 20 FoodCategory cases.
    private var selectedSpotCategory: SpotCategory {
        let pick = selectedPick ?? picksService.picks.first ?? .mezcal
        return SpotCategory(rawValue: pick.id) ?? .mezcal
    }

    var body: some View {
        NavigationStack {
            Group {
                if authService.isSignedIn {
                    addSpotContent
                } else {
                    signInPrompt
                }
            }
            .navigationTitle("Add Spot")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedPick == nil {
                    selectedPick = picksService.picks.first
                }
            }
            .onChange(of: picksService.picks) { _, newPicks in
                // If the selected pick was removed, fall back to the new first pick
                if let current = selectedPick, !newPicks.contains(current) {
                    selectedPick = newPicks.first
                }
            }
        }
    }

    // MARK: - Add Spot Content (authenticated)

    private var addSpotContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Choose what you want to add, then search for the venue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                // One card per active pick (up to 3)
                VStack(spacing: 12) {
                    ForEach(picksService.picks) { pick in
                        PickSelectionCard(
                            pick: pick,
                            isSelected: selectedPick == pick
                        ) {
                            selectedPick = pick
                        }
                    }
                }
                .padding(.horizontal)

                // Context prompt for the selected pick
                if let pick = selectedPick {
                    Text(pick.addSpotPrompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    showSearch = true
                } label: {
                    Label("Search for a Venue", systemImage: "magnifyingglass")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 40)
                .disabled(selectedPick == nil)

                Spacer(minLength: 32)
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showSearch) {
            BusinessSearchView(category: selectedSpotCategory)
        }
    }

    // MARK: - Sign In Prompt (unauthenticated)

    private var signInPrompt: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Sign in to Add Spots")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You need an account to add spots to Flezcal.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            SignInWithAppleButton(.signIn) { request in
                authService.handleSignInWithAppleRequest(request)
            } onCompletion: { result in
                authService.handleSignInWithAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)

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

            Spacer()
            Spacer()
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView()
        }
    }
}

// MARK: - Pick selection card

private struct PickSelectionCard: View {
    let pick: FoodCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                FoodCategoryIcon(category: pick, size: 34)
                    .frame(width: 56, height: 56)
                    .background(isSelected ? pick.color.opacity(0.2) : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? pick.color : Color.clear, lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(pick.displayName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? pick.color : .primary)
                    Text(pick.mapSearchTerms.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(pick.color)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? pick.color.opacity(0.07) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? pick.color.opacity(0.3) : Color(.systemGray4).opacity(0.5),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    AddSpotView()
        .environmentObject(AuthService())
        .environmentObject(SpotService())
        .environmentObject(UserPicksService())
        .environmentObject(PhotoService())
}
