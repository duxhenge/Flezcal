import SwiftUI

/// Grid-based single-select Flezcal picker. Uses the same `FoodCategoryCell`
/// visual style as MyPicksTabView but selects ONE category and returns it via
/// `onSelect` instead of toggling user picks.
///
/// Includes a search bar to filter by name or keywords, displays user's
/// picks first, then all Top 50, and offers a "Create Trending Flezcal"
/// option when no match is found. Trending categories are discoverable
/// via the search bar (text entry / autofill).
///
/// Used by AddFlezcalFlow (SpotDetailView) and SuggestedSpotSheet.
struct FlezcalPickerView: View {
    let userPicks: [FoodCategory]
    let allCategories: [FoodCategory]
    let disabledCategoryIDs: Set<String>
    let onSelect: (FoodCategory) -> Void
    let onCancel: () -> Void

    /// Trending Flezcals from Firestore, converted to FoodCategory.
    var trendingCategories: [FoodCategory] = []
    /// Called when the user wants to create a new trending Flezcal.
    var onCreateTrending: (() -> Void)? = nil

    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    // MARK: - Search Helpers

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searchLower: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MARK: - Filtered Collections

    /// All unique categories combined (picks + trending + Top 50), deduped by ID.
    private var allCombined: [FoodCategory] {
        var seen = Set<String>()
        var result: [FoodCategory] = []
        for cat in userPicks + trendingCategories + allCategories {
            if seen.insert(cat.id).inserted {
                result.append(cat)
            }
        }
        return result
    }

    /// Categories matching the search text (name or keywords).
    private var searchResults: [FoodCategory] {
        guard isSearching else { return [] }
        let query = searchLower
        return allCombined.filter { cat in
            let nameMatch = cat.displayName.lowercased().contains(query)
                         || query.contains(cat.displayName.lowercased())
            let keywordMatch = cat.websiteKeywords.contains { kw in
                kw.lowercased().contains(query) || query.contains(kw.lowercased())
            }
            return nameMatch || keywordMatch
        }
    }

    /// Top 50 categories not in user picks.
    private var otherTop50: [FoodCategory] {
        let pickIDs = Set(userPicks.map(\.id))
        return allCategories.filter { !pickIDs.contains($0.id) }
    }

    /// Trending categories not already in user picks or Top 50.
    private var otherTrending: [FoodCategory] {
        let pickIDs = Set(userPicks.map(\.id))
        let topIDs = Set(allCategories.map(\.id))
        return trendingCategories.filter { !pickIDs.contains($0.id) && !topIDs.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if isSearching {
                        searchResultsSection
                    } else {
                        defaultSections
                    }
                }
                .padding(.vertical)
            }
            .searchable(text: $searchText, prompt: "Search categories...")
            .navigationTitle("Add a \(AppBranding.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    // MARK: - Default (No Search) Layout

    @ViewBuilder
    private var defaultSections: some View {
        // User's picks at the top
        if !userPicks.isEmpty {
            Text("Your \(AppBranding.namePlural)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(userPicks) { cat in
                    pickerCell(for: cat)
                }
            }
            .padding(.horizontal)
        }

        // Create trending — between user picks and Top 50 for easy access
        if onCreateTrending != nil {
            createTrendingButton
                .padding(.horizontal)
                .padding(.top, 4)
        }

        // Top 50
        if !otherTop50.isEmpty {
            Text("Top 50")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(otherTop50) { cat in
                    pickerCell(for: cat)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if searchResults.isEmpty {
            VStack(spacing: 12) {
                Text("No matching categories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if searchLower.count >= 3, onCreateTrending != nil {
                    createTrendingButton
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(searchResults) { cat in
                    pickerCell(for: cat)
                }
            }
            .padding(.horizontal)

            if searchLower.count >= 3, onCreateTrending != nil {
                createTrendingButton
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Create Trending Button

    private var createTrendingButton: some View {
        Button {
            onCreateTrending?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a Trending \(AppBranding.name)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Can't find what you're looking for? Create your own.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
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
    }

    // MARK: - Grid Cell

    @ViewBuilder
    private func pickerCell(for category: FoodCategory) -> some View {
        let isDisabled = disabledCategoryIDs.contains(category.id)
        let isTrending = category.id.hasPrefix("custom_")
        let accentColor: Color = isTrending ? .cyan : category.color

        Button {
            onSelect(category)
        } label: {
            VStack(spacing: 6) {
                // Emoji badge
                ZStack(alignment: .topTrailing) {
                    FoodCategoryIcon(category: category, size: 36)
                        .frame(width: 64, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isTrending ? Color.cyan.opacity(0.08) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isTrending ? Color.cyan.opacity(0.2) : Color.clear, lineWidth: 2)
                        )

                    if isDisabled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(accentColor)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(x: 6, y: -6)
                    }
                }

                // Label
                Text(category.displayName)
                    .font(.caption2)
                    .fontWeight(.regular)
                    .foregroundColor(isDisabled ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)

                if isDisabled {
                    Text("Added")
                        .font(.system(size: 8))
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(isDisabled ? 0.35 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(isDisabled
            ? "\(category.displayName), already added"
            : category.displayName)
    }
}
