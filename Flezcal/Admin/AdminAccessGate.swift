import Foundation

enum AdminAccess {
    // Replace with your Firebase Auth UID
    static let adminUID = "FFrKO5dcaNNlTzM6msCXcLha1d33"

    static func isAdmin(uid: String?) -> Bool {
        guard let uid = uid else { return false }
        return uid == adminUID
    }
}
