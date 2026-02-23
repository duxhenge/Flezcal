import SwiftUI

struct WriteReviewView: View {
    let spot: Spot
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @ObservedObject var reviewService: ReviewService
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int = 0
    @State private var comment: String = ""
    @State private var isSaving = false
    @State private var showError = false

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

                    // Flan emoji rating
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Rating")
                            .font(.headline)

                        FlanRatingView(rating: $rating)

                        if rating > 0 {
                            Text(ReviewTitleGenerator.title(for: rating))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: rating)
                        }
                    }

                    // Comment
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your Review")
                                .font(.headline)
                            Spacer()
                            Text("\(comment.count)/500")
                                .font(.caption2)
                                .foregroundStyle(comment.count > 500 ? .red : .secondary)
                        }

                        TextEditor(text: $comment)
                            .frame(minHeight: 120)
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if comment.isEmpty {
                                    Text("How was the wobble? Did the caramel pool properly?")
                                        .foregroundStyle(.secondary.opacity(0.5))
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onChange(of: comment) { _, newValue in
                                if newValue.count > 500 {
                                    comment = String(newValue.prefix(500))
                                }
                            }
                    }

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
                        submitReview()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text("Submit Review")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(rating == 0 || comment.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
                .padding()
            }
            .navigationTitle("Write Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submitReview() {
        guard let userID = authService.userID else {
            reviewService.errorMessage = "You must be signed in to submit a review."
            return
        }

        isSaving = true

        let review = Review(
            spotID: spot.id,
            userID: userID,
            userName: authService.displayName,
            rating: rating,
            comment: comment.trimmingCharacters(in: .whitespaces),
            date: Date()
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
