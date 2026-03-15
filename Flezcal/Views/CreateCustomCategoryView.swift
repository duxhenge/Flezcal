import SwiftUI

/// Sheet that lets signed-in users create a custom food category.
/// Validates the name, lets users review/edit search terms,
/// saves to Firestore, and adds it as a pick.
struct CreateCustomCategoryView: View {
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var authService: AuthService
    @StateObject private var customService = CustomCategoryService()
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var validationError: String?
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var saveError: String?

    // Similar category suggestions (non-blocking)
    @State private var similarCategories: [FoodCategory] = []
    @State private var similarCustom: [CustomCategory] = []

    // Inline autocomplete suggestions (shown under text field as user types)
    @State private var autocompleteSuggestions: [FoodCategory] = []

    // Search terms editing
    @State private var searchTerms: [String] = []
    @State private var newTerm: String = ""
    /// Tracks whether the user has manually edited terms. Once true, auto-generation
    /// stops updating the list so edits aren't overwritten.
    @State private var userEditedTerms = false

    /// All trending Flezcals use the worm emoji.
    private let customEmoji = CustomCategory.defaultEmoji

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create a Custom Category")
                            .font(.title3)
                            .fontWeight(.bold)

                        Text("Name a specific food or drink you're passionate about. Avoid broad cuisine names like \"Italian\" — think specific like \"Arancini\" or \"Pupusas\".")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Custom Flezcal info box
                    VStack(alignment: .leading, spacing: 6) {
                        Label("What to expect", systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.cyan)

                        Text("Trending \(AppBranding.namePlural) work just like Top 50 \(AppBranding.namePlural) — search for spots, add ratings, verify locations, and track offerings. "
                            + "Popular trending \(AppBranding.namePlural) may be promoted to the Top 50 with unique icons.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.cyan.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Name input with inline autocomplete
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category Name")
                            .font(.headline)

                        TextField("e.g. Pupusas, Empanadas, Kimchi", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                            .onChange(of: name) { _, newValue in
                                validationError = CustomCategory.validate(newValue, existingCustom: customService.customCategories)
                                saveError = nil
                                // Auto-update search terms unless the user has manually edited them
                                if !userEditedTerms {
                                    searchTerms = CustomCategory.suggestedKeywords(for: newValue)
                                }
                                updateSimilarSuggestions(for: newValue)
                                updateAutocompleteSuggestions(for: newValue)
                            }

                        // Inline autocomplete — shows matching categories as the user types
                        if !autocompleteSuggestions.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(autocompleteSuggestions) { cat in
                                    let alreadyPicked = picksService.isSelected(cat)
                                    Button {
                                        if !alreadyPicked {
                                            selectExistingCategory(cat)
                                        } else {
                                            dismiss()
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(cat.emoji)
                                                .font(.title3)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(cat.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundStyle(.primary)
                                                Text(matchReason(for: cat))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if alreadyPicked {
                                                Text("In your picks")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                            }
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)

                                    if cat.id != autocompleteSuggestions.last?.id {
                                        Divider().padding(.leading, 44)
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        }

                        if let error = validationError, !name.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Similar category suggestions
                    if !similarCategories.isEmpty || !similarCustom.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Similar categories already exist", systemImage: "lightbulb.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)

                            if !similarCategories.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(similarCategories) { cat in
                                        let alreadyPicked = picksService.isSelected(cat)
                                        Button {
                                            if !alreadyPicked {
                                                selectExistingCategory(cat)
                                            } else {
                                                // Already picked — just dismiss, nothing to add
                                                dismiss()
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(cat.emoji)
                                                Text(cat.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                if alreadyPicked {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.caption2)
                                                        .foregroundStyle(.green)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(cat.color.opacity(alreadyPicked ? 0.25 : 0.15))
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !similarCustom.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(similarCustom) { cat in
                                        Button {
                                            selectExistingCustom(cat)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(cat.emoji)
                                                Text(cat.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.cyan.opacity(0.15))
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Contextual help text
                            if similarCategories.contains(where: { picksService.isSelected($0) }) {
                                Text("You already have a \(AppBranding.name) that covers this. Tap it to continue, or keep typing to create your own.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Tap to use one of these instead, or keep typing to create your own.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Custom Flezcal icon notice
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.headline)

                        HStack(spacing: 10) {
                            Text(customEmoji)
                                .font(.system(size: 28))
                                .frame(width: 48, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.cyan.opacity(0.2))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.cyan, lineWidth: 2)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("All trending \(AppBranding.namePlural) use the worm icon")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("If your category becomes popular, it may be promoted to a Top 50 \(AppBranding.name) with its own unique icon.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Search terms editor
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty && validationError == nil {
                        searchTermsSection
                    }

                    // Preview
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty && validationError == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview")
                                .font(.headline)

                            HStack(spacing: 8) {
                                Text(customEmoji)
                                    .font(.title2)
                                Text(name.trimmingCharacters(in: .whitespaces))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.cyan.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Create button
                    Button {
                        createCategory()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Label("Create & Add to My \(AppBranding.namePlural)", systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || validationError != nil)

                    if let error = saveError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Trending \(AppBranding.name)")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Fetch popular custom categories so we can suggest similar ones
                await customService.fetchAll()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Category Created!", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("\(name.trimmingCharacters(in: .whitespaces)) has been added to your picks! Ghost pins will now search for it.")
            }
        }
    }

    // MARK: - Search Terms Section

    private var searchTermsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Search Terms")
                    .font(.headline)
                Spacer()
                if userEditedTerms {
                    Button {
                        searchTerms = CustomCategory.suggestedKeywords(for: name)
                        userEditedTerms = false
                    } label: {
                        Text("Reset")
                            .font(.caption)
                            .foregroundStyle(.cyan)
                    }
                }
            }

            Text("These words help find this item on restaurant websites. Add terms restaurants might use on their menus.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Existing terms as removable chips — wrapped in a flow layout
            FlowLayout(spacing: 6) {
                ForEach(searchTerms, id: \.self) { term in
                    HStack(spacing: 4) {
                        Text(term)
                            .font(.subheadline)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchTerms.removeAll { $0 == term }
                                userEditedTerms = true
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // Add new term input
            HStack(spacing: 8) {
                TextField("Add a search term", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .submitLabel(.done)
                    .onSubmit { addNewTerm() }

                Button {
                    addNewTerm()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                }
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func addNewTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty, !searchTerms.contains(term) else {
            newTerm = ""
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            searchTerms.append(term)
        }
        userEditedTerms = true
        newTerm = ""
    }

    // MARK: - Similar Category Suggestions

    /// Finds existing hardcoded and trending categories that are similar
    /// to the user's input. Matches against display names and websiteKeywords
    /// to catch related terms (e.g. "tonkotsu" → Ramen, "neipa" → New England IPA).
    ///
    /// Trending categories use prefix matching (same as `validate()`) so typing
    /// "bris" surfaces "Brisket" immediately. Exact matches are included so the
    /// user can tap to select the existing category instead of re-creating it.
    private func updateSimilarSuggestions(for input: String) {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.count >= 3 else {
            similarCategories = []
            similarCustom = []
            return
        }

        // Check hardcoded Top 50 categories — match on displayName or websiteKeywords.
        // Require at least 4 characters for keyword matching to avoid false positives
        // (e.g. "bri" matching "brick oven" → Wood-Fired Pizza).
        // Include categories already in user's picks — they should still surface
        // so the user knows the concept is already covered (e.g. "Chai" → Tea).
        var matches: [FoodCategory] = []
        for cat in FoodCategory.allCategories {
            let catName = cat.displayName.lowercased()
            let nameMatch = catName.contains(lower) || lower.contains(catName)
            let keywordMatch = lower.count >= 4 && cat.websiteKeywords.contains { kw in
                kw.lowercased().contains(lower) || lower.contains(kw.lowercased())
            }
            if nameMatch || keywordMatch {
                matches.append(cat)
            }
        }
        similarCategories = Array(matches.prefix(3))

        // Check existing trending categories — prefix matching (mirrors validate())
        // so "bris" finds "brisket". No pickCount threshold: even a category with
        // 1 pick should be offered rather than creating a duplicate.
        var customMatches: [CustomCategory] = []
        for cat in customService.customCategories {
            let catName = cat.normalizedName
            let nameMatch = catName.contains(lower)
                         || lower.contains(catName)
                         || lower.hasPrefix(catName)
                         || catName.hasPrefix(lower)
            if nameMatch {
                customMatches.append(cat)
            }
        }
        similarCustom = Array(customMatches.prefix(3))
    }

    // MARK: - Inline Autocomplete

    /// Finds built-in categories that match the user's typing, starting at just
    /// 2 characters. Matches against displayName and websiteKeywords so "CHA"
    /// surfaces Tea (because Tea includes "chai" in its keywords).
    /// Results appear in a dropdown directly under the text field.
    private func updateAutocompleteSuggestions(for input: String) {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.count >= 2 else {
            autocompleteSuggestions = []
            return
        }

        var matches: [FoodCategory] = []
        for cat in FoodCategory.allCategories {
            let catName = cat.displayName.lowercased()

            // Direct name match: "cha" in "chai" or "te" in "tea"
            let nameMatch = catName.hasPrefix(lower) || catName.contains(lower)

            // Keyword match: "cha" matches keyword "chai" in Tea category
            let keywordMatch = cat.websiteKeywords.contains { kw in
                let kwLower = kw.lowercased()
                return kwLower.hasPrefix(lower) || kwLower.contains(lower)
            }

            // Also check mapSearchTerms for broader coverage
            let searchTermMatch = cat.mapSearchTerms.contains { term in
                let termLower = term.lowercased()
                return termLower.hasPrefix(lower) || termLower.contains(lower)
            }

            if nameMatch || keywordMatch || searchTermMatch {
                matches.append(cat)
            }
        }

        // Sort: exact name prefix matches first, then keyword matches
        matches.sort { a, b in
            let aNamePrefix = a.displayName.lowercased().hasPrefix(lower)
            let bNamePrefix = b.displayName.lowercased().hasPrefix(lower)
            if aNamePrefix != bNamePrefix { return aNamePrefix }
            return a.displayName < b.displayName
        }

        autocompleteSuggestions = Array(matches.prefix(4))
    }

    /// Returns a human-readable reason why a category matched the user's input.
    /// Shown as a subtitle in the autocomplete dropdown (e.g. "Includes chai varieties").
    private func matchReason(for category: FoodCategory) -> String {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lower.isEmpty else { return category.displayName }

        let catName = category.displayName.lowercased()

        // If the name itself matches, no extra explanation needed
        if catName.hasPrefix(lower) || catName.contains(lower) {
            return "Top 50 \(AppBranding.name)"
        }

        // Find the matching keyword to explain the connection
        if let matchedKeyword = category.websiteKeywords.first(where: { kw in
            let kwLower = kw.lowercased()
            return kwLower.hasPrefix(lower) || kwLower.contains(lower)
        }) {
            return "Includes \(matchedKeyword.lowercased()) varieties"
        }

        // Check mapSearchTerms
        if let matchedTerm = category.mapSearchTerms.first(where: { term in
            let termLower = term.lowercased()
            return termLower.hasPrefix(lower) || termLower.contains(lower)
        }) {
            return "Searches for \"\(matchedTerm.lowercased())\""
        }

        return "Related category"
    }

    /// User tapped an existing hardcoded category — add it as a pick and dismiss.
    private func selectExistingCategory(_ category: FoodCategory) {
        let added = picksService.toggle(category)
        if added {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        dismiss()
    }

    /// User tapped an existing custom category — increment its pickCount and add as pick.
    private func selectExistingCustom(_ category: CustomCategory) {
        isSaving = true
        Task {
            if let foodCategory = await customService.createOrIncrement(category) {
                let added = picksService.addCustomPick(foodCategory)
                isSaving = false
                if added {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    dismiss()
                } else {
                    saveError = "You have too many \(AppBranding.namePlural) selected. Remove one first to make room."
                }
            } else {
                isSaving = false
                saveError = customService.errorMessage ?? "Something went wrong."
            }
        }
    }

    private func createCategory() {
        guard let userID = authService.userID else {
            saveError = "You must be signed in to create a custom category."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard CustomCategory.validate(trimmed, existingCustom: customService.customCategories) == nil else { return }

        isSaving = true

        let custom = CustomCategory.create(
            displayName: trimmed,
            emoji: customEmoji,
            createdBy: userID,
            websiteKeywords: searchTerms
        )

        Task {
            if let foodCategory = await customService.createOrIncrement(custom) {
                let added = picksService.addCustomPick(foodCategory)
                isSaving = false
                if added {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showSuccess = true
                } else {
                    saveError = "You have too many \(AppBranding.namePlural) selected. Remove one first to make room."
                }
            } else {
                isSaving = false
                saveError = customService.errorMessage ?? "Something went wrong. Please try again."
            }
        }
    }
}

// FlowLayout is defined in SpotDetailView.swift and available project-wide.
