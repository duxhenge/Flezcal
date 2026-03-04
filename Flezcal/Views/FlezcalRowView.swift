import SwiftUI

/// Consolidated per-category row for SpotDetailView.
///
/// Layout (multi-row, breathing room):
/// ```
///              🫓 Tortillas                   ← Row 1: emoji + full name, centered
///   👍 👎  3 confirmed      4.2🍮 (7 ratings) ← Row 2: thumbs + confirm count | score + one flan + count
///       Your rating: Road Trip (4🍮) ✏️       ← Row 3 (if rated): tappable to edit
///             + Add your rating               ← Row 3 (if thumbs-up but no rating): tappable prompt
/// ```
struct FlezcalRowView: View {
    let spot: Spot
    let category: SpotCategory
    @ObservedObject var verificationService: VerificationService
    /// Whether the current user can remove this category from the spot.
    var canRemove: Bool = false
    /// Called when the user taps the remove button; parent handles the alert.
    var onRemoveCategory: (() -> Void)? = nil
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService

    @State private var showRatingPicker = false
    @State private var isSubmitting = false
    @State private var showSignIn = false
    /// Brief inline error shown when a vote/rating action fails.
    @State private var actionError: String? = nil
    /// Tracks what the user tried to do before sign-in so we can auto-proceed.
    @State private var pendingAction: PendingAction? = nil

    private enum PendingAction {
        case thumbsUp, thumbsDown, rate
    }

    /// Live version from SpotService so tally updates are reflected immediately
    private var liveSpot: Spot {
        spotService.spots.first { $0.id == spot.id } ?? spot
    }

    private var userID: String { authService.userID ?? "" }

    private var userVote: Bool? {
        authService.isSignedIn
            ? verificationService.userVote(for: category, userID: userID)
            : nil
    }

    private var userRating: Int? {
        authService.isSignedIn
            ? verificationService.userRating(for: category, userID: userID)
            : nil
    }

    private var aggregateRating: CategoryRating? {
        // Prefer live data from verifications, fall back to stored Spot data
        verificationService.categoryAggregateRating(for: category)
            ?? liveSpot.rating(for: category)
    }

    private var confirmCount: Int {
        verificationService.confirmationCount(for: category)
    }

    var body: some View {
        VStack(spacing: 8) {
            // ── Row 1: Category name, centered (with optional remove) ─
            HStack(spacing: 6) {
                Text(category.emoji)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if canRemove, let onRemove = onRemoveCategory {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(category.displayName)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // ── Row 2: Thumbs + confirmations | Aggregate rating ────
            HStack {
                // Left: Thumbs up/down + confirmation count
                HStack(spacing: 6) {
                    Button {
                        handleThumbsUp()
                    } label: {
                        Image(systemName: userVote == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.body)
                            .foregroundStyle(userVote == true ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .accessibilityLabel(userVote == true ? "\(category.displayName) verified" : "Verify \(category.displayName)")
                    .accessibilityHint(userVote == true
                        ? (userRating == nil ? "Double tap to add your rating" : "Already verified and rated")
                        : "Double tap to confirm this spot has \(category.displayName)")

                    Button {
                        handleThumbsDown()
                    } label: {
                        Image(systemName: userVote == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.body)
                            .foregroundStyle(userVote == false ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .accessibilityLabel(userVote == false ? "\(category.displayName) not here" : "Mark \(category.displayName) as not available")
                    .accessibilityHint("Double tap to vote that this spot does not have \(category.displayName)")

                    if confirmCount > 0 {
                        Text("\(confirmCount) confirmed")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                // Right: Aggregate rating — compact: "4.2🍮 (7 ratings)"
                if let catRating = aggregateRating, catRating.count > 0 {
                    HStack(spacing: 3) {
                        Text(String(format: "%.1f", catRating.average))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("🍮")
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text("(\(catRating.count) \(catRating.count == 1 ? "rating" : "ratings"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(String(format: "%.1f", catRating.average)) out of 5, \(catRating.count) \(catRating.count == 1 ? "rating" : "ratings")")
                }
            }

            // ── Row 3: User's own rating (tappable to edit) ─────────
            if authService.isSignedIn {
                if let rating = userRating, let level = RatingLevel.from(rating) {
                    // User has a rating — show it with edit affordance
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRatingPicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Your rating:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(level.label) (\(rating)🍮)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your rating: \(level.label), \(rating) out of 5")
                    .accessibilityHint("Double tap to change your rating")
                } else if userVote == true {
                    // User verified (thumbs-up) but hasn't rated yet
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRatingPicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text("Add your rating")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Not signed in — invite user to rate (triggers sign-in)
                Button {
                    pendingAction = .rate
                    showSignIn = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                        Text("Sign in to rate")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
            }

            // ── Inline rating picker (expandable) ───────────────────
            if showRatingPicker {
                InlineRatingPicker(
                    categoryName: category.displayName,
                    existingRating: userRating,
                    onSubmit: { rating in
                        submitRating(rating)
                    },
                    onSkip: {
                        withAnimation { showRatingPicker = false }
                    },
                    onRemove: userRating != nil ? {
                        removeRating()
                    } : nil
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Inline error message (auto-dismissing) ───────────────
            if let error = actionError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet()
                .environmentObject(authService)
                .presentationDetents([.medium])
        }
        .onChange(of: authService.isSignedIn) { _, signedIn in
            if signedIn, let action = pendingAction {
                pendingAction = nil
                // Small delay so the sign-in sheet finishes dismissing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    switch action {
                    case .thumbsUp:
                        handleThumbsUp()
                    case .thumbsDown:
                        handleThumbsDown()
                    case .rate:
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRatingPicker = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func showError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { actionError = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.2)) { actionError = nil }
        }
    }

    private func handleThumbsUp() {
        guard authService.isSignedIn else {
            pendingAction = .thumbsUp
            showSignIn = true
            return
        }
        let previousVote = userVote

        if previousVote == true {
            // Already verified — open rating picker if not yet rated,
            // or give feedback that the vote is already recorded.
            if userRating == nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRatingPicker = true
                }
            } else {
                // Already verified and rated — brief feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                showError("Already verified — tap your rating below to edit")
            }
            return
        }

        // New thumbs up or flipping from thumbs down
        isSubmitting = true
        Task {
            guard await RateLimiter.shared.allowAction("vote-\(spot.id)-\(category.rawValue)") else {
                isSubmitting = false
                showError("Too fast — wait a moment and try again")
                return
            }
            let success = await verificationService.submitVote(
                spotID: spot.id, userID: userID, category: category, vote: true
            )
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    spotService.updateVerificationTallies(
                        spotID: spot.id, category: category,
                        vote: true, previousVote: previousVote
                    )
                    // Show rating picker after successful thumbs up
                    showRatingPicker = true
                }
            } else {
                showError("Couldn't save — check your connection and try again")
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            isSubmitting = false
        }
    }

    private func handleThumbsDown() {
        guard authService.isSignedIn else {
            pendingAction = .thumbsDown
            showSignIn = true
            return
        }
        let previousVote = userVote

        isSubmitting = true
        Task {
            guard await RateLimiter.shared.allowAction("vote-\(spot.id)-\(category.rawValue)") else {
                isSubmitting = false
                showError("Too fast — wait a moment and try again")
                return
            }
            let success = await verificationService.submitVote(
                spotID: spot.id, userID: userID, category: category, vote: false
            )
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    spotService.updateVerificationTallies(
                        spotID: spot.id, category: category,
                        vote: false, previousVote: previousVote
                    )
                    showRatingPicker = false
                }

                // If they had a rating, recalculate aggregates (rating was cleared by submitVote)
                if userRating != nil {
                    if let aggregate = verificationService.categoryAggregateRating(for: category) {
                        await spotService.updateCategoryRating(
                            spotID: spot.id, category: category.rawValue,
                            newAverage: aggregate.average, newCount: aggregate.count
                        )
                    } else {
                        await spotService.updateCategoryRating(
                            spotID: spot.id, category: category.rawValue,
                            newAverage: 0, newCount: 0
                        )
                    }
                }
            } else {
                showError("Couldn't save — check your connection and try again")
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            isSubmitting = false
        }
    }

    private func submitRating(_ rating: Int) {
        Task {
            let success = await verificationService.submitRating(
                spotID: spot.id, userID: userID,
                category: category, rating: rating,
                spotService: spotService
            )
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRatingPicker = false
                }
            } else {
                showError("Couldn't save rating — try again")
            }
        }
    }

    private func removeRating() {
        Task {
            let success = await verificationService.removeRating(
                spotID: spot.id, userID: userID,
                category: category, spotService: spotService
            )
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRatingPicker = false
                }
            } else {
                showError("Couldn't remove rating — try again")
            }
        }
    }
}
