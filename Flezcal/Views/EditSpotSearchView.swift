import SwiftUI

/// Sheet that lets users edit the Apple Maps search terms (mapSearchTerms) for
/// a food category. Tapping common venue types toggles them; a custom text field
/// allows free-form additions. Closely mirrors EditCustomCategoryView (website
/// keywords) but uses orange accent and a venue-type picker grid.
struct EditSpotSearchView: View {
    let category: FoodCategory
    @EnvironmentObject var picksService: UserPicksService
    @Environment(\.dismiss) private var dismiss

    @State private var searchTerms: [String] = []
    @State private var newTerm: String = ""
    @State private var showSavedConfirmation = false
    /// True when the user tapped "Reset to defaults" — if they save in this
    /// state, the customized flag is cleared so future code updates propagate.
    @State private var wasResetToDefaults = false

    /// Callback to notify parent that terms were saved (triggers re-search).
    var onSave: (() -> Void)? = nil

    private var hasChanges: Bool {
        searchTerms != category.mapSearchTerms
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Category header
                    HStack(spacing: 12) {
                        FoodCategoryIcon(category: category, size: 36)
                            .frame(width: 56, height: 56)
                            .background(category.color.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Edit spot search terms")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Explanation
                    Text("These venue types are searched on Apple Maps to find places that might have \(category.displayName.lowercased()). Add types to broaden your search, or remove irrelevant ones to narrow it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Current terms as removable chips
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Active Search Terms")
                                .font(.headline)
                            Spacer()
                            Button {
                                resetToDefaults()
                            } label: {
                                Text("Reset to defaults")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        FlowLayout(spacing: 6) {
                            ForEach(searchTerms, id: \.self) { term in
                                HStack(spacing: 4) {
                                    Text(term)
                                        .font(.subheadline)
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            searchTerms.removeAll { $0 == term }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }

                        // Add custom term
                        HStack(spacing: 8) {
                            TextField("Add custom venue type", text: $newTerm)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .submitLabel(.done)
                                .onSubmit { addNewTerm() }

                            Button {
                                addNewTerm()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                            }
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    // Common venue types grid
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Common Venue Types")
                            .font(.headline)

                        FlowLayout(spacing: 6) {
                            ForEach(FoodCategory.commonVenueTypes, id: \.self) { type in
                                let isActive = searchTerms.contains(type)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if isActive {
                                            searchTerms.removeAll { $0 == type }
                                        } else {
                                            searchTerms.append(type)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isActive
                                              ? "checkmark"
                                              : FoodCategory.venueTypeIcon(for: type))
                                            .font(.caption2)
                                            .fontWeight(isActive ? .bold : .regular)
                                            .frame(width: 14)
                                        Text(type)
                                            .font(.subheadline)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isActive ? Color.orange.opacity(0.2) : Color(.systemGray5))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Save button
                    Button {
                        save()
                    } label: {
                        Label("Save Changes", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!hasChanges || searchTerms.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Spot Search Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                searchTerms = category.mapSearchTerms
            }
            .alert("Search Terms Updated", isPresented: $showSavedConfirmation) {
                Button("Done") { dismiss() }
            } message: {
                Text("Spot search terms updated for \(category.displayName). The search will refresh with your new terms.")
            }
        }
    }

    private func addNewTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty, !searchTerms.contains(term) else {
            newTerm = ""
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            searchTerms.append(term)
        }
        newTerm = ""
    }

    private func resetToDefaults() {
        wasResetToDefaults = true
        // For built-in picks, restore original hardcoded mapSearchTerms.
        // For custom picks, regenerate using the same logic as CustomCategory.create.
        if let original = FoodCategory.allCategories.first(where: { $0.id == category.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                searchTerms = original.mapSearchTerms
            }
        } else {
            let lower = category.displayName.lowercased()
            let terms: [String]
            if CustomCategory.isLikelyAlcoholic(lower) {
                var t = [lower, "bar", "liquor store", "restaurant"]
                if CustomCategory.isLikelyWine(lower) {
                    t.insert("wine shop", at: 2)
                } else if CustomCategory.isLikelyBeer(lower) {
                    t.insert("brewery", at: 2)
                }
                terms = t
            } else {
                terms = [lower, "\(lower) restaurant", "restaurant", "cafe"]
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                searchTerms = terms
            }
        }
    }

    private func save() {
        let updated = FoodCategory(
            id: category.id,
            displayName: category.displayName,
            emoji: category.emoji,
            color: category.color,
            mapSearchTerms: searchTerms,
            websiteKeywords: category.websiteKeywords,
            relatedKeywords: category.relatedKeywords,
            addSpotPrompt: category.addSpotPrompt
        )
        if wasResetToDefaults {
            // User reset to defaults then saved — clear the customized flag
            // so future code updates to this category's terms propagate.
            picksService.clearCustomizedFlag(for: category.id)
        }
        picksService.updatePick(updated)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        onSave?()
        showSavedConfirmation = true
    }
}

// MARK: - Spot Search Overview (All-picks mode)

/// Read-only overview showing mapSearchTerms grouped by category.
/// Presented when no single category filter is active. Each category
/// section has an "Edit" button that opens the per-category editor.
struct SpotSearchOverviewView: View {
    let picks: [FoodCategory]
    let onEditCategory: (FoodCategory) -> Void
    @EnvironmentObject var picksService: UserPicksService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("These venue types are searched on Apple Maps for each of your picks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    ForEach(picks) { pick in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                FoodCategoryIcon(category: pick, size: 20)
                                Text(pick.displayName)
                                    .font(.headline)
                                Spacer()
                                Button("Edit") {
                                    onEditCategory(pick)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            }

                            FlowLayout(spacing: 6) {
                                ForEach(pick.mapSearchTerms, id: \.self) { term in
                                    Text(term)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)

                        if pick.id != picks.last?.id {
                            Divider().padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Spot Search Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
