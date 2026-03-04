import Foundation

struct AppUser: Identifiable, Codable {
    var id: String  // Firebase UID
    let email: String
    var displayName: String
    let joinDate: Date
    var spotsAdded: Int = 0
    var ratingsGiven: Int = 0

    // Maps the old Firestore field name "reviewsWritten" to the renamed Swift property
    enum CodingKeys: String, CodingKey {
        case id, email, displayName, joinDate, spotsAdded
        case ratingsGiven = "reviewsWritten"
    }
}
