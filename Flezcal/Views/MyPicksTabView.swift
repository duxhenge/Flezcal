import SwiftUI

/// "My Flezcals" tab — shows the user's current food/drink categories as large cards,
/// with a button to open the selection grid.
///
/// All picks (including the 3 launch defaults) are freely selectable and removable,
/// as long as at least 1 pick remains active. Custom picks also show an edit button.
struct MyPicksTabView: View {
    @EnvironmentObject var picksService: UserPicksService
    @EnvironmentObject var authService: AuthService
    @State private var showGrid = false
    @State private var editingCategory: FoodCategory? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Subtitle
                    subtitleText
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                    // Pick cards
                    VStack(spacing: 14) {
                        ForEach(picksService.picks) { category in
                            let isCustom = category.id.hasPrefix("custom_")
                            let canRemove = picksService.picks.count > 1
                            PickCard(
                                category: category,
                                isEditable: true,
                                canRemove: canRemove,
                                onEdit: { editingCategory = category },
                                onRemove: {
                                    withAnimation(.spring()) {
                                        if isCustom {
                                            _ = picksService.removeCustomPick(category)
                                        } else {
                                            _ = picksService.toggle(category)
                                        }
                                    }
                                }
                            )
                        }

                        // Empty slots — tappable to open the selection grid
                        let remaining = UserPicksService.maxPicks - picksService.picks.count
                        if remaining > 0 {
                            ForEach(0..<remaining, id: \.self) { _ in
                                Button { showGrid = true } label: {
                                    EmptyPickSlot(label: "Add a Flezcal")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Button
                    Button {
                        showGrid = true
                    } label: {
                        Label(
                            "Customize My Flezcals",
                            systemImage: "slider.horizontal.3"
                        )
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("My Flezcals")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showGrid) {
                FoodCategoryGridView()
                    .environmentObject(picksService)
                    .environmentObject(authService)
                    .presentationDetents([.large])
            }
            .sheet(item: $editingCategory) { category in
                EditCustomCategoryView(category: category)
                    .environmentObject(picksService)
                    .presentationDetents([.large])
            }
        }
    }

    private var subtitleText: some View {
        (Text("Your Flezcals are your cravings and the heart of this app. Tap ") +
         Text(Image(systemName: "slider.horizontal.3")) +
         Text(" on any Flezcal to customize its search terms."))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Pick card (filled slot)

private struct PickCard: View {
    let category: FoodCategory
    var isEditable: Bool = false
    let canRemove: Bool
    let onEdit: (() -> Void)?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Category icon circle
            FoodCategoryIcon(category: category, size: 44)
                .frame(width: 68, height: 68)
                .background(category.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(category.displayName)
                    .font(.title3)
                    .fontWeight(.bold)

                // Show websiteKeywords — the terms used for website scanning
                Text(category.websiteKeywords.prefix(3).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Right-side actions
            if isEditable, let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .foregroundStyle(category.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit search terms for \(category.displayName)")
            }

            // Remove button — available for all picks when more than 1 remains
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canRemove ? .secondary : .quaternary)
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .accessibilityLabel("Remove \(category.displayName)")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName), selected\(isEditable ? ", editable" : "")")
    }
}

// MARK: - Empty slot

private struct EmptyPickSlot: View {
    let label: String

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray5))
                .frame(width: 68, height: 68)
                .overlay(
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                )

            Text(label)
                .font(.body)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                        .opacity(0.5)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

#Preview {
    MyPicksTabView()
        .environmentObject(UserPicksService())
        .environmentObject(AuthService())
}
