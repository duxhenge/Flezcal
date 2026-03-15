import SwiftUI

/// Unified rating component with a two-step flow for new ratings:
/// 1. Pick a 1-5 rating (flan emojis + meaning table)
/// 2. Confirm the rating (philosophy header + confirmation question)
///
/// Editing an existing rating skips the confirmation step.
struct RatingFlowView: View {
    let categoryName: String
    let existingRating: Int?
    let onSubmit: (Int) -> Void
    let onSkip: () -> Void
    let onRemove: (() -> Void)?

    @State private var selectedRating: Int = 0
    @State private var isSubmitting = false
    @State private var step: Step = .pick

    private enum Step {
        case pick
        case confirm
    }

    private var isEditing: Bool { existingRating != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step {
            case .pick:
                pickView
            case .confirm:
                confirmView
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if let existingRating {
                selectedRating = existingRating
            }
        }
    }

    // MARK: - Step 1: Pick Rating

    private var pickView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("How far would you go for the \(categoryName.lowercased())?")
                .font(.subheadline)
                .fontWeight(.semibold)

            // 5 flan emojis in a row (tappable)
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { level in
                    Text("🍮")
                        .font(.system(size: 32))
                        .opacity(level <= selectedRating ? 1.0 : 0.25)
                        .scaleEffect(level == selectedRating ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: selectedRating)
                        .onTapGesture {
                            selectedRating = level
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                        .accessibilityLabel("Rate \(level) out of 5\(RatingLevel.from(level).map { ", \($0.label)" } ?? "")")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Rating meaning table
            VStack(alignment: .leading, spacing: 4) {
                ForEach(RatingLevel.allCases, id: \.rawValue) { level in
                    HStack(spacing: 6) {
                        Text("\(level.rawValue)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 14, alignment: .trailing)
                            .foregroundStyle(selectedRating == level.rawValue ? ratingColor(level) : .secondary)
                        Text(level.label)
                            .font(.caption)
                            .fontWeight(selectedRating == level.rawValue ? .bold : .regular)
                            .foregroundStyle(selectedRating == level.rawValue ? ratingColor(level) : .primary)
                        Text("— \(level.description)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(selectedRating == 0 || selectedRating == level.rawValue ? 1.0 : 0.5)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(level.rawValue): \(level.label), \(level.description)")
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                if isEditing {
                    // Editing: submit directly, no confirmation
                    Button {
                        guard selectedRating > 0, !isSubmitting else { return }
                        isSubmitting = true
                        onSubmit(selectedRating)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    } label: {
                        Text("Update Rating")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(selectedRating == 0 || isSubmitting)

                    if let onRemove {
                        Button {
                            onRemove()
                        } label: {
                            Text("Remove")
                                .font(.subheadline)
                                .frame(height: 36)
                        }
                        .foregroundStyle(.red)
                    }
                } else {
                    // New rating: advance to confirmation
                    Button {
                        guard selectedRating > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step = .confirm
                        }
                    } label: {
                        Text("Next")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(selectedRating == 0)

                    Button {
                        onSkip()
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .frame(height: 36)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Step 2: Confirm Rating

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Philosophy header
            Text("We hold our \(AppBranding.namePlural) to a high standard. Let's make sure this one earns it.")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // Show what they picked
            if let level = RatingLevel.from(selectedRating) {
                HStack(spacing: 8) {
                    Text(level.emoji)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.label)
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text(level.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ratingColor(level).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Confirmation question
                Text(level.confirmationQuestion(for: categoryName))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    guard !isSubmitting else { return }
                    isSubmitting = true
                    onSubmit(selectedRating)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                } label: {
                    Text("Yes, confirm")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isSubmitting)

                Button {
                    selectedRating = 0
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = .pick
                    }
                } label: {
                    Text("Change rating")
                        .font(.subheadline)
                        .frame(height: 36)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func ratingColor(_ level: RatingLevel) -> Color {
        switch level {
        case .confirmedSpot:      return .secondary
        case .neighborhoodOption: return .blue
        case .bestLocalChoice:    return .green
        case .bestInRegion:       return .orange
        case .worldClass:         return .red
        }
    }
}
