import SwiftUI

/// Reusable Flezcal selection sheet. Shows the user's picks at the top,
/// then all other curated categories below. Categories already on the
/// spot are grayed out and disabled.
///
/// Used by both the ghost-pin "Add to Flezcal" flow and the
/// SpotDetailView "Add a Flezcal" flow.
struct FlezcalPickerView: View {
    let userPicks: [FoodCategory]
    let allCategories: [FoodCategory]
    let disabledCategoryIDs: Set<String>
    let onSelect: (FoodCategory) -> Void
    let onCancel: () -> Void

    /// Categories in "All Flezcals" section — everything not already in userPicks.
    private var otherCategories: [FoodCategory] {
        let pickIDs = Set(userPicks.map(\.id))
        return allCategories.filter { !pickIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // User's picks section
                    if !userPicks.isEmpty {
                        Text("Your Flezcals")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 10) {
                            ForEach(userPicks) { category in
                                pickerCard(for: category)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // All other categories
                    if !otherCategories.isEmpty {
                        Text("All Flezcals")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top, userPicks.isEmpty ? 0 : 4)

                        VStack(spacing: 10) {
                            ForEach(otherCategories) { category in
                                pickerCard(for: category)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Add a Flezcal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    @ViewBuilder
    private func pickerCard(for category: FoodCategory) -> some View {
        let isDisabled = disabledCategoryIDs.contains(category.id)

        Button {
            onSelect(category)
        } label: {
            HStack(spacing: 16) {
                FoodCategoryIcon(category: category, size: 44)
                    .frame(width: 68, height: 68)
                    .background(category.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayName)
                        .font(.title3)
                        .fontWeight(.bold)

                    if isDisabled {
                        Text("Already added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(category.websiteKeywords.prefix(3).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isDisabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
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
            .opacity(isDisabled ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(isDisabled
            ? "\(category.displayName), already added"
            : category.displayName)
    }
}
