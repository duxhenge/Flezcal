import SwiftUI

/// Full-screen grid where the user selects up to `UserPicksService.maxPicks` categories.
/// Presented as a sheet from MyPicksTabView.
///
/// NOTE: ForEach is intentionally avoided in this file due to a SwiftUICore/SwiftUI
/// module ambiguity that causes "ambiguous use of init" errors in Xcode 16 whole-module
/// compilation. The category list is rendered via a helper wrapper instead.
struct FoodCategoryGridView: View {
    @EnvironmentObject var picksService: UserPicksService
    @Environment(\.dismiss) private var dismiss

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
        // Wrap in a helper view to avoid ForEach module ambiguity at this call site.
        CategoryGridContent(columns: columns, picksService: picksService)
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
