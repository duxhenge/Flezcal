import Foundation

/// A report that a spot has permanently closed, submitted by a community member.
/// Stored in the flat `closure_reports` Firestore collection.
/// Admin reviews reports and either confirms closure or dismisses them.
struct ClosureReport: Identifiable, Codable {
    var id: String = UUID().uuidString
    let spotID: String
    let spotName: String           // Denormalized for admin display
    let spotCity: String           // Extracted from address for sorting
    let reporterUserID: String
    let date: Date

    // Admin action (nil = pending review)
    var adminAction: String?       // "confirmed" or "dismissed"
    var adminActionDate: Date?
}
