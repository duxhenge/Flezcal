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

/// Non-interactive display version
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

// MARK: - Flan Emoji Rating Picker (used in WriteReviewView)

struct FlanRatingView: View {
    @Binding var rating: Int
    let maxRating: Int = 5

    // ✏️ Change the emoji here to swap the rating icon app-wide
    static let ratingEmoji = "🍮"
    static let emptyEmoji  = "🍮"   // same icon, just dimmed

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

// MARK: - Cheeky Review Title

// ✏️ Edit these lines to change the auto-generated title shown above the review text box.
enum ReviewTitleGenerator {
    static func title(for rating: Int) -> String {
        switch rating {
        case 1: return "A Flan in Name Only 😬"
        case 2: return "The Wobble Was Off 😐"
        case 3: return "Respectable Flan Energy 👍"
        case 4: return "A Very Good Time Was Had 🙌"
        case 5: return "Transcendent. I Saw My Ancestors. 🍮✨"
        default: return ""
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRatingView(rating: .constant(3), interactive: true)
        FlanRatingView(rating: .constant(4))
        StarDisplayView(rating: 3.5)
        StarDisplayView(rating: 4.8)
    }
}
