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
    case youDecide = 1
    case popIn = 2
    case bookIt = 3
    case roadTrip = 4
    case pilgrimage = 5

    var label: String {
        switch self {
        case .youDecide:  return "You Decide"
        case .popIn:      return "Pop In"
        case .bookIt:     return "Book It"
        case .roadTrip:   return "Road Trip"
        case .pilgrimage: return "Pilgrimage"
        }
    }

    /// Flan-count emoji scale: 1-5 flans (used in landscape / detail views)
    var emoji: String {
        switch self {
        case .youDecide:  return "🍮"
        case .popIn:      return "🍮🍮"
        case .bookIt:     return "🍮🍮🍮"
        case .roadTrip:   return "🍮🍮🍮🍮"
        case .pilgrimage: return "🍮🍮🍮🍮🍮"
        }
    }

    /// Compact format for tight layouts: "3🍮" instead of "🍮🍮🍮"
    var compactEmoji: String { "\(rawValue)🍮" }

    /// "How far would you go?" descriptions for each level
    var description: String {
        switch self {
        case .youDecide:  return "It's here, your call"
        case .popIn:      return "Glad it's on the menu"
        case .bookIt:     return "Satisfies the craving"
        case .roadTrip:   return "Worth going out of your way"
        case .pilgrimage: return "Worth booking a flight"
        }
    }

    /// Returns the RatingLevel for a 1-5 integer, or nil if out of range.
    static func from(_ rating: Int) -> RatingLevel? {
        RatingLevel(rawValue: rating)
    }
}
