import SwiftUI

struct StarRatingView: View {
    @Binding var rating: Int
    let maxRating: Int = 5
    let interactive: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .orange : .secondary.opacity(0.4))
                    .font(.title2)
                    .scaleEffect(star <= rating ? 1.1 : 1.0)
                    .onTapGesture {
                        if interactive {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                rating = star
                            }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                    }
                    .accessibilityLabel(interactive ? "Rate \(star) star\(star == 1 ? "" : "s")" : "\(star) star\(star == 1 ? "" : "s")")
                    .accessibilityAddTraits(interactive ? .isButton : [])
            }
        }
        .accessibilityElement(children: interactive ? .contain : .combine)
        .accessibilityLabel(interactive ? "Star rating" : "Rated \(rating) of \(maxRating) stars")
        .animation(.easeInOut(duration: 0.15), value: rating)
    }
}

/// Non-interactive display version — shows stars for legacy reviews
struct StarDisplayView: View {
    let rating: Double
    let maxRating: Int = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: starImage(for: star))
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", rating)) of \(maxRating) stars")
    }

    private func starImage(for star: Int) -> String {
        let value = Double(star)
        if value <= rating {
            return "star.fill"
        } else if value - 0.5 <= rating {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

// MARK: - Flan Bar (fractional emoji rating display)

/// Non-interactive display of 1–5 flan emojis with fractional fill support.
/// Full flans are opaque, the partial flan is horizontally clipped to the
/// fractional amount, and empty flans are faded.
///
/// Examples:
///   FlanBarView(rating: 3.0)   → 🍮🍮🍮 (faded)(faded)
///   FlanBarView(rating: 2.3)   → 🍮🍮 (30% clip 🍮)(faded)(faded)
///   FlanBarView(rating: 4.7)   → 🍮🍮🍮🍮 (70% clip 🍮)
struct FlanBarView: View {
    let rating: Double
    var size: CGFloat = 16
    var spacing: CGFloat = 2

    private let maxRating = 5
    private let flanEmoji = "🍮"
    private let fadedOpacity: Double = 0.25

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...maxRating, id: \.self) { position in
                flanSlot(for: position)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", rating)) out of 5 flans")
    }

    @ViewBuilder
    private func flanSlot(for position: Int) -> some View {
        let positionD = Double(position)

        if positionD <= rating {
            // Fully filled flan
            Text(flanEmoji)
                .font(.system(size: size))
        } else if positionD - 1.0 < rating {
            // Partial flan — clip horizontally to the fractional amount
            let fraction = rating - (positionD - 1.0)
            partialFlan(fraction: fraction)
        } else {
            // Empty flan
            Text(flanEmoji)
                .font(.system(size: size))
                .opacity(fadedOpacity)
        }
    }

    /// Renders a partially-filled flan by overlaying a clipped full flan
    /// on top of a faded flan.
    private func partialFlan(fraction: Double) -> some View {
        Text(flanEmoji)
            .font(.system(size: size))
            .opacity(fadedOpacity)
            .overlay(alignment: .leading) {
                Text(flanEmoji)
                    .font(.system(size: size))
                    .clipShape(
                        HorizontalFillShape(fraction: fraction)
                    )
            }
    }
}

/// A shape that fills from the leading edge to `fraction` of the width.
/// Used to clip a flan emoji to show a partial rating (e.g. 30% of a flan).
private struct HorizontalFillShape: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width * fraction,
            height: rect.height
        ))
        return path
    }
}

// MARK: - Compact Passionate Rating Display

/// Inline display for review cards and spot detail (non-interactive).
/// Shows a flan bar inside a coloured capsule badge.
struct RatingLevelBadge: View {
    let rating: Int

    var body: some View {
        if let level = RatingLevel.from(rating) {
            FlanBarView(rating: Double(rating), size: 14, spacing: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ratingColor(level).opacity(0.12))
                .clipShape(Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rating: \(level.label)")
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

// MARK: - Per-Category Rating Row

/// Compact row showing a single category's rating: icon + name + flan bar + number + count.
/// Used in SpotDetailView to show rating breakdown per food/drink category.
struct CategoryRatingRow: View {
    let category: SpotCategory
    let rating: CategoryRating

    var body: some View {
        HStack(spacing: 8) {
            CategoryIcon(category: category, size: 16)
            Text(category.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            FlanBarView(rating: rating.average, size: 14, spacing: 1)
            Text(String(format: "%.1f", rating.average))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("(\(rating.count))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName): rated \(String(format: "%.1f", rating.average)) out of 5, \(rating.count) rating\(rating.count == 1 ? "" : "s")")
    }
}

// MARK: - Average Rating Display

/// Shows the average rating as a flan bar + label (non-interactive).
struct AverageRatingView: View {
    let averageRating: Double
    let reviewCount: Int

    var body: some View {
        if reviewCount > 0 {
            let rounded = Int(averageRating.rounded())
            let level = RatingLevel.from(max(1, min(5, rounded)))

            HStack(spacing: 6) {
                FlanBarView(rating: averageRating, size: 18, spacing: 2)

                if let level {
                    Text(level.label)
                        .fontWeight(.semibold)
                }
                Text(String(format: "%.1f", averageRating))
                    .foregroundStyle(.secondary)
                Text("(\(reviewCount) rating\(reviewCount == 1 ? "" : "s"))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(level?.label ?? "Rated") \(String(format: "%.1f", averageRating)) out of 5, \(reviewCount) rating\(reviewCount == 1 ? "" : "s")")
        } else {
            Text("No ratings yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Review Title ("How far would you go?" scale)

enum ReviewTitleGenerator {
    static func title(for rating: Int) -> String {
        switch rating {
        case 1: return "You Decide — It's here, your call 🍮"
        case 2: return "Pop In — Glad it's on the menu 🍮🍮"
        case 3: return "Book It — Satisfies the craving 🍮🍮🍮"
        case 4: return "Road Trip — Worth going out of your way 🍮🍮🍮🍮"
        case 5: return "Pilgrimage — Worth booking a flight 🍮🍮🍮🍮🍮"
        default: return ""
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            StarRatingView(rating: .constant(3), interactive: true)
            StarDisplayView(rating: 3.5)

            // Flan bar examples
            VStack(alignment: .leading, spacing: 8) {
                Text("FlanBarView examples").font(.headline)
                FlanBarView(rating: 1.0, size: 20)
                FlanBarView(rating: 2.3, size: 20)
                FlanBarView(rating: 3.0, size: 20)
                FlanBarView(rating: 3.7, size: 20)
                FlanBarView(rating: 4.5, size: 20)
                FlanBarView(rating: 5.0, size: 20)
            }

            RatingLevelBadge(rating: 5)
            RatingLevelBadge(rating: 3)
            AverageRatingView(averageRating: 4.2, reviewCount: 7)
            AverageRatingView(averageRating: 2.3, reviewCount: 3)
        }
        .padding()
    }
}
