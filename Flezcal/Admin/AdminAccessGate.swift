import Foundation

enum AdminAccess {
    // swiftlint:disable:next hardcoded_uid
    static let adminUID = "FFrKO5dcaNNlTzM6msCXcLha1d33"

    static func isAdmin(uid: String?) -> Bool {
        guard let uid = uid else { return false }
        return uid == adminUID
    }
}
