import SwiftUI

/// Full-screen grid where the user selects up to `UserPicksService.maxPicks` categories.
/// Presented as a sheet from MyPicksTabView.
///
/// When `FeatureFlags.broadSearchEnabled` is false (launch mode):
/// - The 3 launch categories (mezcal, flan, tortillas) show a lock icon — always active.
/// - The other 18 categories are greyed out with "Coming Soon".
/// - One custom pick slot is available via "Create Your Own".
///
/// When `FeatureFlags.broadSearchEnabled` is true (Phase 4):
/// - All 21 categories are freely selectable (up to 3).
/// - 3 custom pick slots are available.
///
/// NOTE: ForEach is intentionally avoided in some spots due to a SwiftUICore/SwiftUI
/// module ambiguity that causes "ambiguous use of init" errors in Xcode 16 whole-module
/// compilation. The category list is rendered via a helper wrapper instead.
struct FoodCategoryGridView: View {
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateCustom = false
    @State private var showSignInPrompt = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            scrollContent
                .navigationTitle("My Flezcals")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .sheet(isPresented: $showCreateCustom) {
                    CreateCustomCategoryView()
                        .environmentObject(picksService)
                        .environmentObject(authService)
                }
                .alert("Sign In Required", isPresented: $showSignInPrompt) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Sign in from the Profile tab to create custom Flezcals.")
                }
        }
    }

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: HorizontalAlignment.leading, spacing: 20) {
                subtitleText
                    .padding(.horizontal)

                counterBadge

                if FeatureFlags.broadSearchEnabled {
                    // Selected built-in picks shown as a row at the top
                    let selectedBuiltIn = picksService.picks.filter { !$0.id.hasPrefix("custom_") }
                    if !selectedBuiltIn.isEmpty {
                        selectedPicksGrid(selectedBuiltIn)
                            .padding(.horizontal)
                    }

                    // Custom picks section
                    let customPicks = picksService.customPicks
                    if !customPicks.isEmpty {
                        customPicksSection(customPicks)
                            .padding(.horizontal)
                    }

                    // Create custom button
                    if authService.isSignedIn && picksService.canCreateCustom {
                        createCustomButton
                            .padding(.horizontal)
                    }

                    // Unselected built-in categories to choose from
                    let unselected = FoodCategory.allCategories.filter { cat in
                        !picksService.isSelected(cat)
                    }
                    if !unselected.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("All Categories")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            UnselectedGridContent(
                                columns: columns,
                                categories: unselected,
                                picksService: picksService
                            )
                            .padding(.horizontal)
                        }
                    }
                } else {
                    // Launch mode layout
                    launchGrid
                        .padding(.horizontal)

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

                    comingSoonSection
                        .padding(.horizontal)

                    futureGrid
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private var subtitleText: some View {
        Group {
            if FeatureFlags.broadSearchEnabled {
                Text("Choose up to \(UserPicksService.maxPicks). These drive your map pins, ghost suggestions, and filters.")
            } else {
                Text("Select up to \(UserPicksService.maxPicks) categories, or create your own custom Flezcal!")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var counterBadge: some View {
        HStack {
            Spacer()
            if FeatureFlags.broadSearchEnabled {
                let atMax = picksService.picks.count == UserPicksService.maxPicks
                Text("\(picksService.picks.count) / \(UserPicksService.maxPicks) selected")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(atMax ? Color.orange.opacity(0.15) : Color(.systemGray5))
                    .foregroundStyle(atMax ? Color.orange : Color.secondary)
                    .clipShape(Capsule())
            } else {
                let atMax = picksService.picks.count >= UserPicksService.maxPicks
                Text("\(picksService.picks.count) / \(UserPicksService.maxPicks) selected")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(atMax ? Color.orange.opacity(0.15) : Color(.systemGray5))
                    .foregroundStyle(atMax ? Color.orange : Color.secondary)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    /// Top grid showing only launch categories (mezcal, flan, tortillas).
    private var launchGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(FoodCategory.launchCategories) { cat in
                FoodCategoryCell(category: cat, picksService: picksService)
            }
        }
    }

    /// "Coming soon" message between active and future categories.
    private var comingSoonSection: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.vertical, 4)
            Text("More categories coming soon based on user feedback!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// Grayed-out grid of non-launch categories (future items).
    private var futureGrid: some View {
        let futureCats = FoodCategory.allCategories.filter { !FoodCategory.isLaunchCategory($0) }
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(futureCats) { cat in
                FoodCategoryCell(category: cat, picksService: picksService)
            }
        }
        .opacity(0.4)
    }

    /// Selected built-in picks shown at the top with checkmarks (tappable to deselect).
    private func selectedPicksGrid(_ selected: [FoodCategory]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(selected) { cat in
                FoodCategoryCell(category: cat, picksService: picksService)
            }
        }
    }

    private func customPicksSection(_ customPicks: [FoodCategory]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Custom Picks")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(customPicks) { pick in
                HStack(spacing: 12) {
                    FoodCategoryIcon(category: pick, size: 26)
                    Text(pick.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()

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
                        .fill(Color.purple.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

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
                    .foregroundStyle(.purple)
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
                    .fill(Color.purple.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Grid of unselected built-in categories. Kept as a separate view to avoid
/// SwiftUICore/SwiftUI module ambiguity in the parent's body.
private struct UnselectedGridContent: View {
    let columns: [GridItem]
    let categories: [FoodCategory]
    @ObservedObject var picksService: UserPicksService

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(categories) { cat in
                FoodCategoryCell(category: cat, picksService: picksService)
            }
        }
    }
}

// MARK: - Individual category cell

private struct FoodCategoryCell: View {
    let category: FoodCategory
    @ObservedObject var picksService: UserPicksService

    private var isSelected: Bool { picksService.isSelected(category) }

    /// Non-launch categories are locked ("Coming Soon") until broadSearchEnabled.
    /// Launch categories are always freely selectable.
    private var isLocked: Bool {
        if FeatureFlags.broadSearchEnabled { return false }
        if FoodCategory.isLaunchCategory(category) { return false }
        // Non-launch, non-custom categories are "Coming Soon"
        return !category.id.hasPrefix("custom_")
    }

    private var isDisabled: Bool {
        if isLocked { return true }
        return !isSelected && !picksService.canAddMore
    }

    var body: some View {
        VStack(spacing: 6) {
            emojiBadge
            categoryLabel
        }
        .opacity(isDisabled ? 0.35 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onTapGesture {
            guard !isLocked else { return }
            withAnimation(.spring()) {
                _ = picksService.toggle(category)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName)\(isSelected ? ", selected" : "")\(isLocked ? ", coming soon" : "")")
        .accessibilityAddTraits(isLocked ? [] : .isButton)
        .accessibilityHint(isLocked ? "Not available yet" : (isSelected ? "Double tap to deselect" : "Double tap to select"))
    }

    private var emojiBadge: some View {
        ZStack(alignment: .topTrailing) {
            FoodCategoryIcon(category: category, size: 36)
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? category.color.opacity(0.2) : Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? category.color : Color.clear, lineWidth: 2)
                )

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(category.color)
                    .background(Circle().fill(Color(.systemBackground)))
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var categoryLabel: some View {
        VStack(spacing: 2) {
            Text(category.displayName)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? category.color : (isDisabled ? Color.secondary : Color.primary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            if isLocked {
                Text("Coming Soon")
                    .font(.system(size: 8))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
