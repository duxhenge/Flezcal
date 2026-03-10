import SwiftUI

// MARK: - Shared Grid Components
//
// Reusable grid cells and wrappers used by MyPicksTabView (multi-select)
// and FlezcalPickerView (single-select). Kept in a shared file to avoid
// SwiftUICore/SwiftUI module ambiguity that causes "ambiguous use of init"
// errors in Xcode 16 whole-module compilation.

/// Grid of unselected built-in categories. Kept as a separate view to avoid
/// SwiftUICore/SwiftUI module ambiguity in the parent's body.
struct UnselectedGridContent: View {
    let columns: [GridItem]
    let categories: [FoodCategory]
    @ObservedObject var picksService: UserPicksService
    var tier: RankedCategory.Tier = .top50

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(categories) { cat in
                FoodCategoryCell(category: cat, picksService: picksService, tier: tier)
            }
        }
    }
}

// MARK: - Individual category cell

struct FoodCategoryCell: View {
    let category: FoodCategory
    @ObservedObject var picksService: UserPicksService
    var tier: RankedCategory.Tier = .top50
    /// Optional callback for editing search terms on selected picks.
    var onEdit: (() -> Void)? = nil

    private var isSelected: Bool { picksService.isSelected(category) }
    /// Trending categories use cyan accent instead of the category's own color.
    private var accentColor: Color { tier == .trending ? .cyan : category.color }

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
                        .fill(isSelected
                              ? accentColor.opacity(0.2)
                              : (tier == .trending ? Color.cyan.opacity(0.08) : Color(.systemGray6)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? accentColor : (tier == .trending ? Color.cyan.opacity(0.2) : Color.clear), lineWidth: 2)
                )

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accentColor)
                    .background(Circle().fill(Color(.systemBackground)))
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
            }

            if isSelected, onEdit != nil {
                Button {
                    onEdit?()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundStyle(accentColor)
                        .padding(4)
                        .background(Circle().fill(Color(.systemBackground)))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: 50)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Edit \(category.displayName)")
            }
        }
    }

    private var categoryLabel: some View {
        VStack(spacing: 2) {
            Text(category.displayName)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? accentColor : (isDisabled ? Color.secondary : Color.primary))
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
