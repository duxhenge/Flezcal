import SwiftUI

/// Consolidated per-category row for SpotDetailView.
///
/// Single-line layout:
/// ```
///   🌮 Tacos    4.2🍮 (7)         ⭐ Rate  ⊘    ×
///   🫓 Tortillas                   ⭐ Rate  ⊘    ×
///   🌮 Tacos    Your: 4🍮 ✏️                ⊘    ×
///   🌮 Tacos    ⚠️ Reported · Undo          ×
/// ```
/// Tapping the row or ⭐ expands the RatingFlowView below.
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
        case rate, markUnavailable
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

    var body: some View {
        VStack(spacing: 6) {
            // ── Single-line row ──────────────────────────────────────
            mainRow

            // ── Expandable rating picker ─────────────────────────────
            if showRatingPicker {
                RatingFlowView(
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

            // ── Inline error message (auto-dismissing) ──────────────
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    switch action {
                    case .rate:
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRatingPicker = true
                        }
                    case .markUnavailable:
                        markUnavailable()
                    }
                }
            }
        }
    }

    // MARK: - Main Row (single line)

    private var mainRow: some View {
        HStack(spacing: 8) {
            // ── Leading: emoji + name ──
            CategoryIcon(category: category, size: 22)
                .accessibilityHidden(true)
            Text(category.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            // ── Center: rating or engagement state ──
            centerContent
                .layoutPriority(-1)

            Spacer(minLength: 4)

            // ── Trailing: action buttons ──
            trailingActions
        }
    }

    // MARK: - Center Content (inline with the row)

    @ViewBuilder
    private var centerContent: some View {
        if userVote == false {
            // Reported unavailable — compact inline
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Reported")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    retractUnavailable()
                } label: {
                    Text("Undo")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
            .fixedSize()
        } else if let rating = userRating {
            // User has rated — show compact "Your: 4🍮 ✏️"
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRatingPicker.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Text("You: \(rating)🍮")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Your rating: \(rating) out of 5")
            .accessibilityHint("Double tap to change your rating")
        } else if let catRating = aggregateRating, catRating.count > 0 {
            // Has community ratings but user hasn't rated
            HStack(spacing: 3) {
                Text(String(format: "%.1f", catRating.average))
                    .font(.caption)
                    .fontWeight(.medium)
                Text("🍮")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text("(\(catRating.count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(String(format: "%.1f", catRating.average)) out of 5, \(catRating.count) \(catRating.count == 1 ? "rating" : "ratings")")
        }
        // else: no ratings yet — center stays empty, rate button is in trailing
    }

    // MARK: - Trailing Actions

    @ViewBuilder
    private var trailingActions: some View {
        HStack(spacing: 12) {
            // Rate button — shown unless user reported unavailable
            if userVote != false {
                if userRating != nil {
                    // Already rated — no extra button needed (edit is in center)
                    EmptyView()
                } else if userVote == true {
                    // Legacy confirmed, no rating yet
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRatingPicker.toggle()
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add your rating")
                } else {
                    // No engagement yet — primary rate CTA
                    Button {
                        openRatingPicker()
                    } label: {
                        Image(systemName: "star.circle")
                            .font(.body)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rate \(category.displayName)")
                }

                // "Not here" button
                Button {
                    if authService.isSignedIn {
                        markUnavailable()
                    } else {
                        pendingAction = .markUnavailable
                        showSignIn = true
                    }
                } label: {
                    Image(systemName: "nosign")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .accessibilityLabel("Report \(category.displayName) as not available here")
            }

            // Remove button (admin / original adder)
            if canRemove, let onRemove = onRemoveCategory {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(category.displayName)")
            }
        }
        .fixedSize()
    }

    // MARK: - Actions

    private func showError(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { actionError = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.2)) { actionError = nil }
        }
    }

    /// Opens the rating picker. If not signed in, triggers sign-in first.
    private func openRatingPicker() {
        guard authService.isSignedIn else {
            pendingAction = .rate
            showSignIn = true
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            showRatingPicker = true
        }
    }

    /// Marks this category as unavailable at this spot (vote: false).
    private func markUnavailable() {
        guard authService.isSignedIn else {
            pendingAction = .markUnavailable
            showSignIn = true
            return
        }

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
                        vote: false, previousVote: nil
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

    /// Retracts the user's "unavailable" vote (same vote = retract in VerificationService).
    private func retractUnavailable() {
        isSubmitting = true
        Task {
            guard await RateLimiter.shared.allowAction("vote-\(spot.id)-\(category.rawValue)") else {
                isSubmitting = false
                showError("Too fast — wait a moment and try again")
                return
            }
            // Submitting the same vote again triggers retract logic
            let success = await verificationService.submitVote(
                spotID: spot.id, userID: userID, category: category, vote: false
            )
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    spotService.updateVerificationTallies(
                        spotID: spot.id, category: category,
                        vote: false, previousVote: false
                    )
                }
            } else {
                showError("Couldn't undo — check your connection and try again")
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
