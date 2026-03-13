import SwiftUI

/// Sheet that lets users edit the website search terms for any food category
/// (both built-in and custom). Accessible by tapping the edit button on a
/// pick card in My Flezcals. For built-in picks, "Reset to defaults" restores the
/// original hardcoded keywords; for custom picks, it regenerates from the name.
struct EditCustomCategoryView: View {
    let category: FoodCategory
    @EnvironmentObject var picksService: UserPicksService
    @Environment(\.dismiss) private var dismiss

    @State private var searchTerms: [String] = []
    @State private var newTerm: String = ""
    @State private var showSavedConfirmation = false

    /// True when the user has made changes that differ from the original.
    private var hasChanges: Bool {
        searchTerms != category.websiteKeywords
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
                            Text("Edit search terms")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Explanation
                    Text("These terms are used to find \(category.displayName.lowercased()) on restaurant websites. If searches aren't finding the right results, try adding words that restaurants use on their menus.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Current terms as removable chips
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Terms")
                                .font(.headline)
                            Spacer()
                            Button {
                                // Single source of truth: Firestore override > hardcoded static > generated fallback.
                                let canonical = SearchTermOverrideService.shared.defaultCategory(for: category)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    searchTerms = canonical.websiteKeywords
                                }
                            } label: {
                                Text("Reset to defaults")
                                    .font(.caption)
                                    .foregroundStyle(category.color)
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
                                .background(category.color.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }

                        // Add new term
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
                                    .foregroundStyle(category.color)
                            }
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
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
                    .tint(category.color)
                    .disabled(!hasChanges || searchTerms.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Edit Search Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                searchTerms = category.websiteKeywords
            }
            .alert("Search Terms Updated", isPresented: $showSavedConfirmation) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your search terms for \(category.displayName) have been updated. Future searches will use these terms.")
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

    private func save() {
        // Rebuild the FoodCategory with updated websiteKeywords
        let updated = FoodCategory(
            id: category.id,
            displayName: category.displayName,
            emoji: category.emoji,
            color: category.color,
            mapSearchTerms: category.mapSearchTerms,
            websiteKeywords: searchTerms,
            addSpotPrompt: category.addSpotPrompt
        )
        picksService.updatePick(updated)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        showSavedConfirmation = true
    }
}
