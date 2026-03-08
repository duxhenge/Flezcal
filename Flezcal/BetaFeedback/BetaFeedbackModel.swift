import Foundation
import FirebaseFirestore

/// Categories for beta feedback submissions.
enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug = "bug"
    case suggestion = "suggestion"
    case content = "content"
    case design = "design"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .suggestion: return "Suggestion"
        case .content: return "Content"
        case .design: return "Design/UX"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .bug: return "ladybug"
        case .suggestion: return "lightbulb"
        case .content: return "map"
        case .design: return "paintbrush"
        case .other: return "ellipsis.circle"
        }
    }

    var tagColor: String {
        switch self {
        case .bug: return "red"
        case .suggestion: return "blue"
        case .content: return "green"
        case .design: return "purple"
        case .other: return "gray"
        }
    }
}

/// A single beta feedback submission stored in Firestore.
struct BetaFeedback: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let category: String
    let city: String
    let feedbackText: String
    let timestamp: Timestamp
    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let iOSVersion: String
    let selectedCategories: [String]

    /// Convenience accessor for the typed category enum.
    var feedbackCategory: FeedbackCategory {
        FeedbackCategory(rawValue: category) ?? .other
    }

    /// Formatted date string for display.
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp.dateValue())
    }
}
