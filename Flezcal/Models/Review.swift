import Foundation

struct Review: Identifiable, Codable {
    var id: String = UUID().uuidString
    let spotID: String
    let userID: String
    var userName: String
    let rating: Int  // 1-5
    let comment: String  // kept for backward compat with existing Firestore docs
    let date: Date

    /// The category being rated (e.g. "flan", "mezcal").
    /// nil on legacy reviews written before per-category ratings existed.
    var category: String?

    var isReported: Bool = false
    var reportCount: Int = 0
    var reportedByUserIDs: [String] = []
    var isHidden: Bool = false  // Auto-hidden after 3+ reports
}

// MARK: - Rating Scale ("How far would you go?")

/// The five rating levels based on "how far would you go" for this food/drink.
/// Rates the specific food/drink item at the venue, not the venue itself.
/// Uses flan icons (🍮) as the visual scale.
enum RatingLevel: Int, CaseIterable {
    case confirmedSpot = 1
    case neighborhoodOption = 2
    case bestLocalChoice = 3
    case bestInRegion = 4
    case worldClass = 5

    var label: String {
        switch self {
        case .confirmedSpot:      return "Confirmed Spot"
        case .neighborhoodOption: return "Neighborhood Option"
        case .bestLocalChoice:    return "Best Local Choice"
        case .bestInRegion:       return "Best in Region"
        case .worldClass:         return "World Class"
        }
    }

    /// Flan-count emoji scale: 1-5 flans (used in landscape / detail views)
    var emoji: String {
        switch self {
        case .confirmedSpot:      return "🍮"
        case .neighborhoodOption: return "🍮🍮"
        case .bestLocalChoice:    return "🍮🍮🍮"
        case .bestInRegion:       return "🍮🍮🍮🍮"
        case .worldClass:         return "🍮🍮🍮🍮🍮"
        }
    }

    /// Compact format for tight layouts: "3🍮" instead of "🍮🍮🍮"
    var compactEmoji: String { "\(rawValue)🍮" }

    /// Descriptions for each level
    var description: String {
        switch self {
        case .confirmedSpot:      return "They have it"
        case .neighborhoodOption: return "Satisfies the craving"
        case .bestLocalChoice:    return "Best of the nearby choices"
        case .bestInRegion:       return "Worthy of a road trip"
        case .worldClass:         return "Worthy of a pilgrimage"
        }
    }

    /// Confirmation question shown before submitting a new rating.
    /// The category name is interpolated in lowercase.
    func confirmationQuestion(for category: String) -> String {
        let name = category.lowercased()
        switch self {
        case .worldClass:         return "Is the \(name) here worth booking a flight?"
        case .bestInRegion:       return "Is the \(name) here worth going out of your way?"
        case .bestLocalChoice:    return "Is this the go-to place in this area for \(name)?"
        case .neighborhoodOption: return "Does the \(name) here satisfy your craving?"
        case .confirmedSpot:      return "Your choice to try the \(name) here"
        }
    }

    /// Returns the RatingLevel for a 1-5 integer, or nil if out of range.
    static func from(_ rating: Int) -> RatingLevel? {
        RatingLevel(rawValue: rating)
    }
}
