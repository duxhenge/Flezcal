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

    /// True if the review contains the magic word — awards the Transcendent badge to the spot
    var isTranscendent: Bool { comment.localizedCaseInsensitiveContains("transcendent") }
}

// MARK: - Passionate Rating Scale

/// The five passionate rating levels used across all food categories.
/// Replaces the old star-based system with food-specific vibes.
enum RatingLevel: Int, CaseIterable {
    case pass = 1
    case decent = 2
    case legit = 3
    case fire = 4
    case obsessed = 5

    var label: String {
        switch self {
        case .pass:     return "Pass"
        case .decent:   return "Decent"
        case .legit:    return "Legit"
        case .fire:     return "Fire"
        case .obsessed: return "Obsessed"
        }
    }

    var emoji: String {
        switch self {
        case .pass:     return "👋"
        case .decent:   return "👍"
        case .legit:    return "🔥"
        case .fire:     return "🔥🔥"
        case .obsessed: return "🤯"
        }
    }

    var description: String {
        switch self {
        case .pass:     return "Not for me"
        case .decent:   return "It's alright"
        case .legit:    return "The real deal"
        case .fire:     return "Exceptional"
        case .obsessed: return "Life-changing"
        }
    }

    /// Returns the RatingLevel for a 1-5 integer, or nil if out of range.
    static func from(_ rating: Int) -> RatingLevel? {
        RatingLevel(rawValue: rating)
    }
}
