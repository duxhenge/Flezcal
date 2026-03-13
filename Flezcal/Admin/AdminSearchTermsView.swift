import SwiftUI
import FirebaseFirestore

/// Admin view for managing Firestore-based search term overrides.
struct AdminSearchTermsView: View {
    @ObservedObject private var overrideService = SearchTermOverrideService.shared
    @State private var selectedCategory: FoodCategory?
    @State private var searchText = ""

    private var categories: [FoodCategory] {
        let all = FoodCategory.allKnownCategories
        if searchText.isEmpty { return all }
        let query = searchText.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.id.lowercased().contains(query)
        }
    }

    var body: some View {
        categoryList
            .searchable(text: $searchText, prompt: "Filter categories")
            .navigationTitle("Search Terms")
            .sheet(item: $selectedCategory) { cat in
                AdminSearchTermEditView(category: cat)
            }
    }

    private var categoryList: some View {
        List {
            Section {
                let count = overrideService.overrides.count
                Text("\(count) active override(s). Changes apply to all users in real-time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Categories") {
                ForEach(categories) { cat in
                    AdminCategoryRow(
                        category: cat,
                        hasOverride: overrideService.overrides[cat.id] != nil,
                        onTap: { selectedCategory = cat }
                    )
                }
            }
        }
    }
}

// MARK: - Category Row

private struct AdminCategoryRow: View {
    let category: FoodCategory
    let hasOverride: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Text(category.emoji)
                .font(.title3)
            categoryInfo
            Spacer()
            overrideIcon
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var categoryInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                legacyBadge
            }
            let terms: String = category.mapSearchTerms.prefix(4).joined(separator: ", ")
            Text(terms)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var legacyBadge: some View {
        if SpotCategory(rawValue: category.id).isLegacy {
            Text("Legacy")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var overrideIcon: some View {
        if hasOverride {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
                .font(.body)
        }
    }
}

// MARK: - Per-Category Editor

struct AdminSearchTermEditView: View {
    let category: FoodCategory
    @ObservedObject private var overrideService = SearchTermOverrideService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var mapTerms: [String] = []
    @State private var webKeywords: [String] = []
    @State private var relatedKeywords: [String] = []
    @State private var emojiOverride: String = ""
    @State private var newMapTerm = ""
    @State private var newWebKeyword = ""
    @State private var newRelatedKeyword = ""
    @State private var showSaved = false
    @State private var showRemoveConfirm = false
    @State private var errorMessage: String?

    private var hardcodedCategory: FoodCategory? {
        FoodCategory.allKnownCategories.first { $0.id == category.id }
    }

    private var hasOverride: Bool {
        overrideService.overrides[category.id] != nil
    }

    private var hasChanges: Bool {
        let existing = overrideService.overrides[category.id]
        let defaults = hardcodedCategory ?? category
        let effectiveMap = existing?.mapSearchTerms ?? defaults.mapSearchTerms
        let effectiveWeb = existing?.websiteKeywords ?? defaults.websiteKeywords
        let effectiveRel = existing?.relatedKeywords ?? defaults.relatedKeywords
        let effectiveEmoji = existing?.emoji ?? ""
        return mapTerms != effectiveMap || webKeywords != effectiveWeb
            || relatedKeywords != effectiveRel || emojiOverride != effectiveEmoji
    }

    var body: some View {
        NavigationStack {
            editorContent
                .navigationTitle("Edit Override")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onAppear { loadCurrentTerms() }
                .alert("Override Saved", isPresented: $showSaved) {
                    Button("Done") { dismiss() }
                } message: {
                    Text("Search term override for \(category.displayName) is now active for all users.")
                }
                .alert("Remove Override?", isPresented: $showRemoveConfirm) {
                    Button("Remove", role: .destructive) { removeOverride() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This reverts \(category.displayName) to its hardcoded default terms for all users.")
                }
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                editorHeader
                emojiSection
                termSections
                errorView
                saveButton
                removeButton
            }
            .padding()
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 12) {
            Text(emojiOverride.isEmpty ? category.emoji : emojiOverride)
                .font(.largeTitle)
                .frame(width: 56, height: 56)
                .background(category.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(hasOverride ? "Override active" : "Using defaults")
                    .font(.subheadline)
                    .foregroundStyle(hasOverride ? .orange : .secondary)
            }
        }
    }

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Emoji Override").font(.headline)
                    Text("Leave empty to use the hardcoded default (\(category.emoji))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !emojiOverride.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            emojiOverride = ""
                        }
                    } label: {
                        Text("Reset")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            TextField("Enter emoji", text: $emojiOverride)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }

    private var termSections: some View {
        VStack(alignment: .leading, spacing: 24) {
            AdminTermSection(
                title: "Map Search Terms",
                subtitle: "Queries sent to Apple Maps",
                terms: $mapTerms,
                newTerm: $newMapTerm,
                defaults: hardcodedCategory?.mapSearchTerms ?? []
            )
            AdminTermSection(
                title: "Website Keywords",
                subtitle: "Scanned on venue homepages",
                terms: $webKeywords,
                newTerm: $newWebKeyword,
                defaults: hardcodedCategory?.websiteKeywords ?? []
            )
            AdminTermSection(
                title: "Related Keywords",
                subtitle: "Broad matches (lower confidence)",
                terms: $relatedKeywords,
                newTerm: $newRelatedKeyword,
                defaults: hardcodedCategory?.relatedKeywords ?? []
            )
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Label("Save Override", systemImage: "arrow.up.circle.fill")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!hasChanges)
    }

    @ViewBuilder
    private var removeButton: some View {
        if hasOverride {
            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                Label("Remove Override", systemImage: "arrow.uturn.backward")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func loadCurrentTerms() {
        let defaults = hardcodedCategory ?? category
        let existing = overrideService.overrides[category.id]
        mapTerms = existing?.mapSearchTerms ?? defaults.mapSearchTerms
        webKeywords = existing?.websiteKeywords ?? defaults.websiteKeywords
        relatedKeywords = existing?.relatedKeywords ?? defaults.relatedKeywords
        emojiOverride = existing?.emoji ?? ""
    }

    private func save() {
        let defaults = hardcodedCategory ?? category
        let trimmedEmoji = emojiOverride.trimmingCharacters(in: .whitespaces)
        let emojiValue: String? = trimmedEmoji.isEmpty ? nil : trimmedEmoji
        let override = CategoryTermOverride(
            mapSearchTerms: mapTerms != defaults.mapSearchTerms ? mapTerms : nil,
            websiteKeywords: webKeywords != defaults.websiteKeywords ? webKeywords : nil,
            relatedKeywords: relatedKeywords != defaults.relatedKeywords ? relatedKeywords : nil,
            displayName: nil,
            emoji: emojiValue,
            colorHex: nil,
            addSpotPrompt: nil
        )
        if override.mapSearchTerms == nil && override.websiteKeywords == nil
            && override.relatedKeywords == nil && override.emoji == nil {
            removeOverride()
            return
        }
        Task {
            do {
                try await overrideService.saveOverride(categoryID: category.id, override: override)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSaved = true
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }

    private func removeOverride() {
        Task {
            do {
                try await overrideService.removeOverride(categoryID: category.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = "Failed to remove: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Term Section (extracted to its own struct)

private struct AdminTermSection: View {
    let title: String
    let subtitle: String
    @Binding var terms: [String]
    @Binding var newTerm: String
    let defaults: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader
            chipGrid
            addTermRow
        }
    }

    private var sectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    terms = defaults
                }
            } label: {
                Text("Reset")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var chipGrid: some View {
        FlowLayout(spacing: 6) {
            ForEach(terms, id: \.self) { term in
                AdminTermChip(
                    term: term,
                    isDefault: defaults.contains(term),
                    onRemove: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            terms.removeAll { $0 == term }
                        }
                    }
                )
            }
        }
    }

    private var addTermRow: some View {
        HStack(spacing: 8) {
            TextField("Add term", text: $newTerm)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .submitLabel(.done)
                .onSubmit { addTerm() }

            Button { addTerm() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty, !terms.contains(term) else {
            newTerm = ""
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            terms.append(term)
        }
        newTerm = ""
    }
}

// MARK: - Term Chip

private struct AdminTermChip: View {
    let term: String
    let isDefault: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(term)
                .font(.subheadline)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isDefault ? Color.orange.opacity(0.1) : Color.blue.opacity(0.15))
        .clipShape(Capsule())
    }
}
