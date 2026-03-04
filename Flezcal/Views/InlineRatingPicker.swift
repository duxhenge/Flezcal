import SwiftUI

/// Compact inline rating widget shown after a user gives thumbs up or adds a Flezcal.
/// Displays one row of 5 tappable flan emojis with a meaning table below.
struct InlineRatingPicker: View {
    let categoryName: String
    let existingRating: Int?
    let onSubmit: (Int) -> Void
    let onSkip: () -> Void
    let onRemove: (() -> Void)?  // shown only if editing an existing rating

    @State private var selectedRating: Int = 0
    @State private var isSubmitting = false

    var body: some View {
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
                Button {
                    guard selectedRating > 0, !isSubmitting else { return }
                    isSubmitting = true
                    onSubmit(selectedRating)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                } label: {
                    Text(existingRating != nil ? "Update Rating" : "Submit Rating")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(selectedRating == 0 || isSubmitting)

                if existingRating == nil {
                    Button {
                        onSkip()
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .frame(height: 36)
                    }
                    .foregroundStyle(.secondary)
                }

                if let onRemove, existingRating != nil {
                    Button {
                        onRemove()
                    } label: {
                        Text("Remove")
                            .font(.subheadline)
                            .frame(height: 36)
                    }
                    .foregroundStyle(.red)
                }
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

    private func ratingColor(_ level: RatingLevel) -> Color {
        switch level {
        case .youDecide:  return .secondary
        case .popIn:      return .blue
        case .bookIt:     return .green
        case .roadTrip:   return .orange
        case .pilgrimage: return .red
        }
    }
}
