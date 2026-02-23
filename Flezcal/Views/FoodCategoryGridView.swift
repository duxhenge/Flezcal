import SwiftUI

/// Full-screen grid where the user selects up to `UserPicksService.maxPicks` categories.
/// Presented as a sheet from MyPicksTabView.
///
/// Includes all 20 hardcoded categories plus a "Create Your Own" button for custom picks.
///
/// NOTE: ForEach is intentionally avoided in some spots due to a SwiftUICore/SwiftUI
/// module ambiguity that causes "ambiguous use of init" errors in Xcode 16 whole-module
/// compilation. The category list is rendered via a helper wrapper instead.
struct FoodCategoryGridView: View {
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateCustom = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            scrollContent
                .navigationTitle("My Picks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .sheet(isPresented: $showCreateCustom) {
                    CreateCustomCategoryView()
                }
        }
    }

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: HorizontalAlignment.leading, spacing: 20) {
                Text("Choose up to \(UserPicksService.maxPicks). These drive your map pins, ghost suggestions, and filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                counterBadge

                categoryGrid
                    .padding(.horizontal)

                // Create custom button
                if authService.isSignedIn && picksService.canCreateCustom {
                    createCustomButton
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private var counterBadge: some View {
        let atMax = picksService.picks.count == UserPicksService.maxPicks
        return HStack {
            Spacer()
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

    private var categoryGrid: some View {
        CategoryGridContent(columns: columns, picksService: picksService)
    }

    private var createCustomButton: some View {
        Button {
            showCreateCustom = true
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

/// Isolated view that renders the 3-column grid of category cells.
/// Kept separate so its @ViewBuilder body compiles in its own type context,
/// away from the SwiftUICore/SwiftUI ambiguity that affects FoodCategoryGridView.
private struct CategoryGridContent: View {
    let columns: [GridItem]
    @ObservedObject var picksService: UserPicksService

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(FoodCategory.allCategories) { cat in
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
    private var isDisabled: Bool { !isSelected && !picksService.canAddMore }

    var body: some View {
        VStack(spacing: 6) {
            emojiBadge
            categoryLabel
        }
        .opacity(isDisabled ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onTapGesture {
            withAnimation(.spring()) {
                _ = picksService.toggle(category)
            }
        }
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
        Text(category.displayName)
            .font(.caption2)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundColor(isSelected ? category.color : (isDisabled ? Color.secondary : Color.primary))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
    }
}
