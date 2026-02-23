import Foundation

struct AppUser: Identifiable, Codable {
    var id: String  // Firebase UID
    let email: String
    var displayName: String
    let joinDate: Date
    var spotsAdded: Int = 0
    var reviewsWritten: Int = 0
}
