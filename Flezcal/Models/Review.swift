import Foundation

struct Review: Identifiable, Codable {
    var id: String = UUID().uuidString
    let spotID: String
    let userID: String
    var userName: String
    let rating: Int  // 1-5
    let comment: String
    let date: Date
    var isReported: Bool = false
    var reportCount: Int = 0
    var reportedByUserIDs: [String] = []
    var isHidden: Bool = false  // Auto-hidden after 3+ reports

    /// True if the review contains the magic word — awards the Transcendent badge to the spot
    var isTranscendent: Bool { comment.localizedCaseInsensitiveContains("transcendent") }
}
