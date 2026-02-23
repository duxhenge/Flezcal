import SwiftUI

/// "My Picks" tab — shows the user's current 1–3 chosen food/drink categories
/// as large cards, with a button to open the selection grid.
struct MyPicksTabView: View {
    @EnvironmentObject var picksService: UserPicksService
    @State private var showGrid = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Subtitle
                    Text("Your picks shape everything — map pins, ghost suggestions, and search filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                    // Pick cards
                    VStack(spacing: 14) {
                        ForEach(picksService.picks) { category in
                            PickCard(category: category)
                        }

                        // Empty slots
                        let remaining = UserPicksService.maxPicks - picksService.picks.count
                        if remaining > 0 {
                            ForEach(0..<remaining, id: \.self) { _ in
                                EmptyPickSlot()
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Change button
                    Button {
                        showGrid = true
                    } label: {
                        Label("Change My Picks", systemImage: "slider.horizontal.3")
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
            .navigationTitle("My Picks")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showGrid) {
                FoodCategoryGridView()
                    .environmentObject(picksService)
                    .presentationDetents([.large])
            }
        }
    }
}

// MARK: - Pick card (filled slot)

private struct PickCard: View {
    let category: FoodCategory

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

                Text(category.mapSearchTerms.prefix(2).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(category.color)
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
    }
}

// MARK: - Empty slot

private struct EmptyPickSlot: View {
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

            Text("Add a pick")
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
    }
}

#Preview {
    MyPicksTabView()
        .environmentObject(UserPicksService())
}
