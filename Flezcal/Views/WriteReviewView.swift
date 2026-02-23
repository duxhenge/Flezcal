import SwiftUI

struct WriteReviewView: View {
    let spot: Spot
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @ObservedObject var reviewService: ReviewService
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int = 0
    @State private var selectedCategory: SpotCategory
    @State private var isSaving = false

    init(spot: Spot, reviewService: ReviewService) {
        self.spot = spot
        self._reviewService = ObservedObject(wrappedValue: reviewService)
        // Default to primary category
        self._selectedCategory = State(initialValue: spot.primaryCategory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Spot info
                    HStack {
                        ForEach(spot.categories) { cat in
                            HStack(spacing: 4) {
                                CategoryIcon(category: cat, size: 14)
                                Text(cat.displayName)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(cat.color.opacity(0.15))
                            .foregroundStyle(cat.color)
                            .clipShape(Capsule())
                        }

                        Spacer()
                    }

                    Text(spot.name)
                        .font(.title3)
                        .fontWeight(.bold)

                    // Category picker (if spot has multiple categories)
                    if spot.categories.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What are you rating?")
                                .font(.headline)

                            HStack(spacing: 8) {
                                ForEach(spot.categories) { cat in
                                    Button {
                                        withAnimation {
                                            selectedCategory = cat
                                            rating = 0
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(cat.emoji)
                                            Text(cat.displayName)
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedCategory == cat
                                                ? cat.color.opacity(0.15)
                                                : Color(.systemGray6)
                                        )
                                        .foregroundStyle(
                                            selectedCategory == cat
                                                ? cat.color
                                                : .primary
                                        )
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(selectedCategory == cat
                                                        ? cat.color.opacity(0.3)
                                                        : Color.clear,
                                                        lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Passionate rating picker
                    PassionateRatingView(
                        rating: $rating,
                        categoryName: selectedCategory.displayName.lowercased()
                    )

                    // Error message
                    if let error = reviewService.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Submit button
                    Button {
                        submitRating()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text("Submit Rating")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(rating == 0 || isSaving)
                }
                .padding()
            }
            .navigationTitle("Rate \(selectedCategory.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submitRating() {
        guard let userID = authService.userID else {
            reviewService.errorMessage = "You must be signed in to submit a rating."
            return
        }

        isSaving = true

        let review = Review(
            spotID: spot.id,
            userID: userID,
            userName: authService.displayName,
            rating: rating,
            comment: "",  // no written reviews in the new system
            date: Date(),
            category: selectedCategory.rawValue
        )

        Task {
            let success = await reviewService.addReview(review)
            if success {
                // Update the spot's average rating
                let newCount = spot.reviewCount + 1
                let newAverage = ((spot.averageRating * Double(spot.reviewCount)) + Double(rating)) / Double(newCount)
                await spotService.updateSpotRating(spotID: spot.id, newAverage: newAverage, newCount: newCount)

                // Haptic feedback on success
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
            isSaving = false
            if success {
                dismiss()
            }
        }
    }
}
