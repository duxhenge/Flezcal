import SwiftUI

/// "My Flezcals" tab — shows the category selection grid directly,
/// with selected picks at the top (editable), then unselected Top 50 and
/// Trending categories below. Users can tap to select/deselect, edit
/// search terms, create trending Flezcals, and set search radius.
struct MyPicksTabView: View {
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var rankingService: RankingService
    @State private var showCreateCustom = false
    @State private var showSignInPrompt = false
    @State private var editingCategory: FoodCategory? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Subtitle
                    Text("Choose up to \(UserPicksService.maxPicks). These drive your map pins, ghost suggestions, and filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .tutorialTarget("pickSubtitle")

                    // Counter badge
                    counterBadge

                    if FeatureFlags.broadSearchEnabled {
                        broadSearchContent
                    } else {
                        launchModeContent
                    }

}
                .padding(.vertical)
            }
            .navigationTitle("My Flezcals")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCreateCustom) {
                CreateCustomCategoryView()
                    .environmentObject(picksService)
                    .environmentObject(authService)
            }
            .sheet(item: $editingCategory) { category in
                EditCustomCategoryView(category: category)
                    .environmentObject(picksService)
                    .presentationDetents([.large])
            }
            .alert("Sign In Required", isPresented: $showSignInPrompt) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Sign in from the Profile tab to create trending Flezcals.")
            }
        }
    }

    // MARK: - Broad Search (Phase 4) Content

    @ViewBuilder
    private var broadSearchContent: some View {
        // All selected picks together (built-in + trending) in one grid
        if !picksService.picks.isEmpty {
            selectedPicksGrid(picksService.picks)
                .padding(.horizontal)
        }

        // Create custom button
        if authService.isSignedIn && picksService.canCreateCustom {
            createCustomButton
                .padding(.horizontal)
        }

        // Unselected Top 50 categories (trending found via Create Your Own / text entry)
        let unselectedTop50 = FoodCategory.allCategories.filter { cat in
            !picksService.isSelected(cat) && rankingService.isTop50(cat.id)
        }

        if !unselectedTop50.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top 50")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                UnselectedGridContent(
                    columns: columns,
                    categories: unselectedTop50,
                    picksService: picksService,
                    tier: .top50
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Launch Mode Content

    @ViewBuilder
    private var launchModeContent: some View {
        // Launch categories grid
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(FoodCategory.launchCategories) { cat in
                FoodCategoryCell(category: cat, picksService: picksService)
            }
        }
        .padding(.horizontal)

        // Custom picks section
        let customPicks = picksService.customPicks
        if !customPicks.isEmpty {
            customPicksSection(customPicks)
                .padding(.horizontal)
        }

        // Always show create button — prompts sign-in if needed
        if picksService.canCreateCustom {
            createCustomButton
                .padding(.horizontal)
        }

        // Coming soon section
        VStack(spacing: 6) {
            Divider()
                .padding(.vertical, 4)
            Text("More categories coming soon based on user feedback!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)

        // Future categories (grayed out)
        let futureCats = FoodCategory.allCategories.filter { !FoodCategory.isLaunchCategory($0) }
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(futureCats) { cat in
                FoodCategoryCell(category: cat, picksService: picksService)
            }
        }
        .opacity(0.4)
        .padding(.horizontal)
    }

    // MARK: - Counter Badge

    private var counterBadge: some View {
        HStack {
            Spacer()
            let atMax = picksService.picks.count >= UserPicksService.maxPicks
            Text("\(picksService.picks.count) / \(UserPicksService.maxPicks) selected")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(atMax ? Color.orange.opacity(0.15) : Color(.systemGray5))
                .foregroundStyle(atMax ? Color.orange : Color.secondary)
                .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Selected Picks Grid (with edit buttons)

    private func selectedPicksGrid(_ selected: [FoodCategory]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(selected) { cat in
                FoodCategoryCell(category: cat, picksService: picksService,
                                 tier: rankingService.tier(for: cat.id),
                                 onEdit: { editingCategory = cat })
            }
        }
    }

    // MARK: - Custom Picks Section

    private func customPicksSection(_ customPicks: [FoodCategory]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Trending Picks")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(customPicks) { pick in
                let fillColor = Color.cyan.opacity(0.08)
                let strokeColor = Color.cyan.opacity(0.3)

                HStack(spacing: 12) {
                    FoodCategoryIcon(category: pick, size: 26)
                    Text(pick.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()

                    // Edit button
                    Button {
                        editingCategory = pick
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit search terms for \(pick.displayName)")

                    // Remove button
                    Button {
                        withAnimation(.spring()) {
                            _ = picksService.removeCustomPick(pick)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(picksService.picks.count <= 1)
                    .accessibilityLabel("Remove \(pick.displayName)")
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(fillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(strokeColor, lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Create Custom Button

    private var createCustomButton: some View {
        Button {
            if authService.isSignedIn {
                showCreateCustom = true
            } else {
                showSignInPrompt = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Your Own")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Can't find your category? Create a custom one.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(picksService.customPickCount)/\(CustomCategoryService.maxCustomPicks)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cyan.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .tutorialTarget("customizeButton")
    }
}

#Preview {
    MyPicksTabView()
        .environmentObject(UserPicksService())
        .environmentObject(AuthService())
        .environmentObject(RankingService())
}
