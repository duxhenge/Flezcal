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

    // Search terms editing
    @State private var searchTerms: [String] = []
    @State private var newTerm: String = ""
    /// Tracks whether the user has manually edited terms. Once true, auto-generation
    /// stops updating the list so edits aren't overwritten.
    @State private var userEditedTerms = false

    /// All custom Flezcals use the worm emoji until promoted to a built-in category.
    private let customEmoji = "🐛"

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
                            .foregroundStyle(.purple)

                        Text("Custom Flezcals work just like built-in categories — search for spots, add ratings, verify locations, and track offerings. "
                            + "Popular custom Flezcals are tracked across the community and may be promoted to built-in categories with unique icons.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category Name")
                            .font(.headline)

                        TextField("e.g. Pupusas, Empanadas, Kimchi", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                            .onChange(of: name) { _, newValue in
                                validationError = CustomCategory.validate(newValue)
                                saveError = nil
                                // Auto-update search terms unless the user has manually edited them
                                if !userEditedTerms {
                                    searchTerms = CustomCategory.suggestedKeywords(for: newValue)
                                }
                                updateSimilarSuggestions(for: newValue)
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
                                        Button {
                                            selectExistingCategory(cat)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(cat.emoji)
                                                Text(cat.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(cat.color.opacity(0.15))
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
                                            .background(Color.purple.opacity(0.15))
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Text("Tap to use one of these instead, or keep typing to create your own.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                                        .fill(Color.purple.opacity(0.2))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.purple, lineWidth: 2)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("All custom Flezcals use the worm icon")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("If your category becomes popular, it may be promoted to a built-in Flezcal with its own unique icon.")
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
                            .background(Color.purple.opacity(0.1))
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
                            Label("Create & Add to My Flezcals", systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || validationError != nil)

                    if let error = saveError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Custom Category")
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
                Text("\(name.trimmingCharacters(in: .whitespaces)) has been added to your picks! Ghost pins will now search for it. Popular custom Flezcals are tracked across the community and may be promoted to full categories with all features.")
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
                            .foregroundStyle(.purple)
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
                    .background(Color.purple.opacity(0.1))
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
                        .foregroundStyle(.purple)
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

    /// Finds existing hardcoded and popular custom categories that are similar
    /// to the user's input. Matches against websiteKeywords and display names
    /// to catch related terms (e.g. "tonkotsu" → Ramen, "neipa" → New England IPA).
    private func updateSimilarSuggestions(for input: String) {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.count >= 3 else {
            similarCategories = []
            similarCustom = []
            return
        }

        // Check hardcoded categories — match on websiteKeywords or partial displayName
        var matches: [FoodCategory] = []
        for cat in FoodCategory.allCategories where !picksService.isSelected(cat) {
            let nameMatch = cat.displayName.lowercased().contains(lower)
                         || lower.contains(cat.displayName.lowercased())
            let keywordMatch = cat.websiteKeywords.contains { kw in
                kw.lowercased().contains(lower) || lower.contains(kw.lowercased())
            }
            if nameMatch || keywordMatch {
                matches.append(cat)
            }
        }
        similarCategories = Array(matches.prefix(3))

        // Check popular custom categories other users created
        var customMatches: [CustomCategory] = []
        for cat in customService.customCategories where cat.pickCount >= 2 {
            let nameMatch = cat.normalizedName.contains(lower)
                         || lower.contains(cat.normalizedName)
            if nameMatch && cat.normalizedName != lower {
                customMatches.append(cat)
            }
        }
        similarCustom = Array(customMatches.prefix(3))
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
                    saveError = "You've reached the maximum number of custom picks."
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
        guard CustomCategory.validate(trimmed) == nil else { return }

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
                    saveError = "You've reached the maximum number of custom picks."
                }
            } else {
                isSaving = false
                saveError = customService.errorMessage ?? "Something went wrong. Please try again."
            }
        }
    }
}

// FlowLayout is defined in SpotDetailView.swift and available project-wide.
