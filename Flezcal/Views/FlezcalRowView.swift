import SwiftUI

/// Consolidated per-category row for SpotDetailView.
///
/// Layout (multi-row, breathing room):
/// ```
///              🫓 Tortillas                   ← Row 1: emoji + full name, centered
///   4.2🍮 (7 ratings)        3 confirmed      ← Row 2: aggregate rating | confirm count
///   ┌─────────────────────────────────────┐
///   │ ⭐ I've tried it — rate it          │   ← Row 3 (no engagement): three choices
///   │ 👀 Just browsing                    │
///   │ ✕  No longer available here         │
///   └─────────────────────────────────────┘
///       Your rating: Road Trip (4🍮) ✏️       ← Row 3 (if rated): tappable to edit
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
    /// User tapped "Just browsing" — hides the prompt for this session.
    @State private var dismissedPrompt = false

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

    /// Confirmation count from Spot tallies (verificationUpCount)
    private var confirmCount: Int {
        liveSpot.verificationUpCount?[category.rawValue] ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // ── Row 1: Category name, centered (with optional remove) ─
            HStack(spacing: 6) {
                CategoryIcon(category: category, size: 26)
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

            // ── Row 2: Aggregate rating | Confirmation count ────
            HStack {
                // Left: Aggregate rating — "4.2🍮 (7 ratings)"
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

                Spacer()

                // Right: Confirmation count (social proof)
                if confirmCount > 0 {
                    Text("\(confirmCount) confirmed")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // ── Row 3: Action buttons / user engagement state ────
            if authService.isSignedIn {
                if userVote == false {
                    // State D: User marked as unavailable
                    unavailableReportedRow
                } else if let rating = userRating, let level = RatingLevel.from(rating) {
                    // State B: User has rated — show editable rating
                    userRatingRow(rating: rating, level: level)
                } else if userVote == true {
                    // State C: User voted up (legacy) but hasn't rated
                    addYourRatingPrompt
                } else if dismissedPrompt {
                    // User tapped "Just browsing" — show compact prompt
                    compactRatePrompt
                } else {
                    // State A: No engagement yet — show three choices
                    actionButtonsRow
                }
            } else if dismissedPrompt {
                compactRatePrompt
            } else {
                // Not signed in — show three choices (will trigger sign-in)
                actionButtonsRow
            }

            // ── Inline rating picker (expandable) ───────────────────
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

    // MARK: - Row Subviews

    /// State A: Three choices — tried it (rate), just browsing (dismiss), no longer available
    private var actionButtonsRow: some View {
        VStack(spacing: 6) {
            // Primary: I've tried it — opens rating picker
            Button {
                openRatingPicker()
            } label: {
                Label("I've tried the \(category.displayName.lowercased()) here — rate it",
                      systemImage: "star.circle")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isSubmitting)
            .accessibilityHint("Double tap to rate the \(category.displayName) at this spot")

            // Secondary: Just browsing — collapses the prompt
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    dismissedPrompt = true
                }
            } label: {
                Label("Just browsing",
                      systemImage: "eye")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            // Tertiary: No longer available
            Button {
                if authService.isSignedIn {
                    markUnavailable()
                } else {
                    pendingAction = .markUnavailable
                    showSignIn = true
                }
            } label: {
                Label("\(category.displayName) is no longer available here",
                      systemImage: "xmark.circle")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(isSubmitting)
            .accessibilityHint("Double tap to report this spot no longer has \(category.displayName)")
        }
    }

    /// State B: User has a rating — show it with edit affordance
    private func userRatingRow(rating: Int, level: RatingLevel) -> some View {
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
    }

    /// Compact prompt shown after user tapped "Just browsing"
    private var compactRatePrompt: some View {
        Button {
            openRatingPicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.circle")
                    .font(.caption)
                Text("Tried it? Rate it")
                    .font(.caption)
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    /// State C: User voted up (legacy) but hasn't rated yet
    private var addYourRatingPrompt: some View {
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

    /// State D: User marked this as unavailable
    private var unavailableReportedRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("You reported this as unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                retractUnavailable()
            } label: {
                Text("Undo")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
