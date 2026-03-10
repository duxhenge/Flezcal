import SwiftUI

/// "My Flezcals" tab — shows the user's current food/drink categories as large cards,
/// with a button to open the selection grid.
///
/// All picks (including the 3 launch defaults) are freely selectable and removable,
/// as long as at least 1 pick remains active. Custom picks also show an edit button.
struct MyPicksTabView: View {
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var authService: AuthService
    @State private var showGrid = false
    @State private var editingCategory: FoodCategory? = nil
    @State private var showMinPickAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Subtitle
                    subtitleText
                        .tutorialTarget("pickSubtitle")
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                    // Pick cards
                    VStack(spacing: 14) {
                        ForEach(picksService.picks) { category in
                            let isCustom = category.id.hasPrefix("custom_")
                            let canRemove = picksService.picks.count > 1
                            PickCard(
                                category: category,
                                isEditable: true,
                                canRemove: canRemove,
                                onEdit: { editingCategory = category },
                                onRemove: {
                                    if !canRemove {
                                        showMinPickAlert = true
                                        return
                                    }
                                    withAnimation(.spring()) {
                                        if isCustom {
                                            _ = picksService.removeCustomPick(category)
                                        } else {
                                            _ = picksService.toggle(category)
                                        }
                                    }
                                }
                            )
                            .tutorialTarget("pickCard_\(category.id)")
                        }

                        // Empty slots — tappable to open the selection grid
                        let remaining = UserPicksService.maxPicks - picksService.picks.count
                        if remaining > 0 {
                            ForEach(0..<remaining, id: \.self) { _ in
                                Button { showGrid = true } label: {
                                    EmptyPickSlot(label: "Add a Flezcal")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)



                    // Button
                    Button {
                        showGrid = true
                    } label: {
                        Label(
                            "Customize My Flezcals",
                            systemImage: "slider.horizontal.3"
                        )
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .tutorialTarget("customizeButton")
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("My Flezcals")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showGrid) {
                FoodCategoryGridView()
                    .environmentObject(picksService)
                    .environmentObject(authService)
                    .presentationDetents([.large])
            }
            .sheet(item: $editingCategory) { category in
                EditCustomCategoryView(category: category)
                    .environmentObject(picksService)
                    .presentationDetents([.large])
            }
            .alert("Minimum 1 Flezcal", isPresented: $showMinPickAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    private var subtitleText: some View {
        (Text("Your Flezcals are your cravings and the heart of this app. Tap ") +
         Text(Image(systemName: "slider.horizontal.3")) +
         Text(" on any Flezcal to customize its search terms."))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Pick card (filled slot)

private struct PickCard: View {
    let category: FoodCategory
    var isEditable: Bool = false
    let canRemove: Bool
    let onEdit: (() -> Void)?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Category icon circle
            FoodCategoryIcon(category: category, size: 44)
                .frame(width: 68, height: 68)
                .background(category.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(category.displayName)
                    .font(.title3)
                    .fontWeight(.bold)

                Text(category.websiteKeywords.prefix(3).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Right-side actions
            if isEditable, let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .foregroundStyle(category.color)
                }
                .buttonStyle(.plain)
                .tutorialTarget("editButton_\(category.id)")
                .accessibilityLabel("Edit search terms for \(category.displayName)")
            }

            // Remove button — always tappable; onRemove handles the minimum-pick guard
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canRemove ? .secondary : .quaternary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(category.displayName)")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(category.color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(category.color.opacity(0.25), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName), selected\(isEditable ? ", editable" : "")")
    }
}

// MARK: - Empty slot

private struct EmptyPickSlot: View {
    let label: String

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray5))
                .frame(width: 68, height: 68)
                .overlay(
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                )

            Text(label)
                .font(.body)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                        .opacity(0.5)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Search Radius Picker

/// Horizontal pill picker for the user's search distance preference.
/// Shows discrete options (10, 25, 35, 50, 75 mi) with the selected
/// option highlighted in orange. Matches the Capsule pill style used
/// by PicksFilterBar for visual consistency.
struct SearchRadiusPicker: View {
    @EnvironmentObject var picksService: UserPicksService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Distance")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(UserPicksService.radiusOptions, id: \.miles) { option in
                        let isSelected = abs(picksService.searchRadiusDegrees - option.degrees) < 0.01
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                picksService.setSearchRadius(option.degrees)
                            }
                        } label: {
                            Text("\(option.miles) mi / \(option.km) km")
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(isSelected ? Color.orange : Color(.systemBackground))
                                )
                                .foregroundStyle(isSelected ? .white : .primary)
                                .overlay(
                                    Capsule().stroke(Color.secondary.opacity(0.3),
                                                      lineWidth: isSelected ? 0 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("How far to search for spots from your location")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MyPicksTabView()
        .environmentObject(UserPicksService())
        .environmentObject(AuthService())
}
