import SwiftUI

/// Sheet that lets signed-in users create a custom food category.
/// Validates the name, auto-generates keywords, saves to Firestore,
/// and adds it as a pick.
struct CreateCustomCategoryView: View {
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var authService: AuthService
    @StateObject private var customService = CustomCategoryService()
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedEmoji: String = "🍽️"
    @State private var validationError: String?
    @State private var isSaving = false
    @State private var showSuccess = false

    private let emojiChoices = [
        "🍽️", "🥘", "🍛", "🥙", "🫔", "🥗", "🍝",
        "🧆", "🥩", "🍗", "🦐", "🦑", "🫕", "🍖",
        "🥐", "🧁", "🍰", "🥧", "🍩", "🧇", "🍪",
    ]

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

                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category Name")
                            .font(.headline)

                        TextField("e.g. Pupusas, Empanadas, Kimchi", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                            .onChange(of: name) { _, newValue in
                                validationError = CustomCategory.validate(newValue)
                            }

                        if let error = validationError, !name.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Emoji picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pick an Emoji")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(emojiChoices, id: \.self) { emoji in
                                    Button {
                                        selectedEmoji = emoji
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 28))
                                            .frame(width: 48, height: 48)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(selectedEmoji == emoji
                                                          ? Color.purple.opacity(0.2)
                                                          : Color(.systemGray6))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(selectedEmoji == emoji
                                                            ? Color.purple
                                                            : Color.clear,
                                                            lineWidth: 2)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Preview
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty && validationError == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview")
                                .font(.headline)

                            HStack(spacing: 8) {
                                Text(selectedEmoji)
                                    .font(.title2)
                                Text(name.trimmingCharacters(in: .whitespaces))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Text("Will search for \"\(name.trimmingCharacters(in: .whitespaces).lowercased())\" on restaurant websites and Apple Maps.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                            Label("Create & Add to My Picks", systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || validationError != nil)
                }
                .padding()
            }
            .navigationTitle("Custom Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Category Created!", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("\(name.trimmingCharacters(in: .whitespaces)) has been added to your picks. Ghost pins will now search for it!")
            }
        }
    }

    private func createCategory() {
        guard let userID = authService.userID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard CustomCategory.validate(trimmed) == nil else { return }

        isSaving = true

        let custom = CustomCategory.create(
            displayName: trimmed,
            emoji: selectedEmoji,
            createdBy: userID
        )

        Task {
            if let foodCategory = await customService.createOrIncrement(custom) {
                let added = picksService.addCustomPick(foodCategory)
                isSaving = false
                if added {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showSuccess = true
                }
            } else {
                isSaving = false
            }
        }
    }
}
