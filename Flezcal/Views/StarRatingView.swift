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
            }
        }
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
            }
        }
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

// MARK: - Flan Emoji Rating Picker (legacy — kept for reference)

struct FlanRatingView: View {
    @Binding var rating: Int
    let maxRating: Int = 5

    static let ratingEmoji = "🍮"
    static let emptyEmoji  = "🍮"

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...maxRating, id: \.self) { flan in
                Text(flan <= rating ? Self.ratingEmoji : Self.emptyEmoji)
                    .opacity(flan <= rating ? 1.0 : 0.25)
                    .font(.system(size: 32))
                    .scaleEffect(flan == rating ? 1.25 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: rating)
                    .onTapGesture {
                        withAnimation {
                            rating = flan
                        }
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    }
            }
        }
    }
}

// MARK: - Passionate Rating Picker

/// The primary rating input: 5 passionate levels from Pass to Obsessed.
/// Rates the specific food at the venue, not the venue itself.
struct PassionateRatingView: View {
    @Binding var rating: Int
    /// Optional category name to contextualise the prompt (e.g. "flan", "mezcal")
    var categoryName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name = categoryName {
                Text("How was the \(name)?")
                    .font(.headline)
            }

            VStack(spacing: 8) {
                ForEach(RatingLevel.allCases, id: \.rawValue) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            rating = level.rawValue
                        }
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    } label: {
                        HStack(spacing: 12) {
                            Text(level.emoji)
                                .font(.title3)
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.label)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if rating == level.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.title3)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(rating == level.rawValue
                                      ? Color.orange.opacity(0.1)
                                      : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(rating == level.rawValue
                                        ? Color.orange.opacity(0.4)
                                        : Color.clear,
                                        lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Compact Passionate Rating Display

/// Inline display for review cards and spot detail (non-interactive).
struct RatingLevelBadge: View {
    let rating: Int

    var body: some View {
        if let level = RatingLevel.from(rating) {
            HStack(spacing: 4) {
                Text(level.emoji)
                    .font(.caption)
                Text(level.label)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ratingColor(level).opacity(0.12))
            .foregroundStyle(ratingColor(level))
            .clipShape(Capsule())
        }
    }

    private func ratingColor(_ level: RatingLevel) -> Color {
        switch level {
        case .pass:     return .secondary
        case .decent:   return .blue
        case .legit:    return .green
        case .fire:     return .orange
        case .obsessed: return .red
        }
    }
}

// MARK: - Average Rating Display

/// Shows the average rating as a passionate label (non-interactive).
struct AverageRatingView: View {
    let averageRating: Double
    let reviewCount: Int

    var body: some View {
        if reviewCount > 0 {
            let rounded = Int(averageRating.rounded())
            let level = RatingLevel.from(max(1, min(5, rounded)))

            HStack(spacing: 6) {
                if let level {
                    Text(level.emoji)
                        .font(.subheadline)
                    Text(level.label)
                        .fontWeight(.semibold)
                }
                Text(String(format: "%.1f", averageRating))
                    .foregroundStyle(.secondary)
                Text("(\(reviewCount) rating\(reviewCount == 1 ? "" : "s"))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } else {
            Text("No ratings yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Cheeky Review Title (updated for passionate scale)

enum ReviewTitleGenerator {
    static func title(for rating: Int) -> String {
        switch rating {
        case 1: return "Not today 👋"
        case 2: return "It's alright, nothing special 👍"
        case 3: return "The real deal — legit 🔥"
        case 4: return "Exceptional — seriously fire 🔥🔥"
        case 5: return "Obsessed. Life-changing. 🤯"
        default: return ""
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            StarRatingView(rating: .constant(3), interactive: true)
            FlanRatingView(rating: .constant(4))
            StarDisplayView(rating: 3.5)
            PassionateRatingView(rating: .constant(4), categoryName: "flan")
            RatingLevelBadge(rating: 5)
            AverageRatingView(averageRating: 4.2, reviewCount: 7)
        }
        .padding()
    }
}
