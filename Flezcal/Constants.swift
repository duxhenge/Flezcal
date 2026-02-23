import Foundation

/// API keys — injected at build time from Secrets.xcconfig via Info.plist.
/// Secrets.xcconfig is excluded from version control via .gitignore.
enum APIKeys {
    /// Brave Search API key. Sourced from BRAVE_SEARCH_API_KEY in Secrets.xcconfig →
    /// BraveSearchAPIKey in Info.plist → read here at runtime.
    /// Never hardcode this value directly in source.
    static let braveSearch: String = Bundle.main.infoDictionary?["BraveSearchAPIKey"] as? String ?? ""
}

enum AppConstants {
    /// Change this value to rename the app throughout the UI
    static let appName = "Flezcal"
    static let bundleID = "com.flezcal.app"

    /// Bump this when shipping a new build — shown in Profile → About
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    // ✏️ REQUIRED before App Store submission: replace these with your real hosted URLs.
    //    Both URLs must be publicly accessible or Apple will reject the app.
    //    privacyPolicyURL is shown in Profile → About and required by App Store guidelines.
    static let privacyPolicyURL: URL = URL(string: "https://flezcal.com/privacy")
        ?? URL(string: "https://example.com")!
    static let supportURL: URL = URL(string: "https://flezcal.com/support")
        ?? URL(string: "https://example.com")!

    // ✏️ Add, remove, or edit taglines here — one is picked at random each launch.
    static let taglines: [String] = [
        "Life is short. Eat flan.",
        "Mezcal: nature's apology for Mondays.",
        "Find your people. They're probably eating flan.",
        "Flan & mezcal — a lifestyle, not a hobby.",
        "Because someone has to document this.",
        "¿Hay flan? Sí hay flan.",
        "The worm at the bottom is not the goal. The flan is.",
    ]

    /// Returns the same tagline for the entire app session, different each launch.
    static let appTagline: String = taglines.randomElement() ?? taglines[0]
}

/// Firestore collection and document path constants.
/// Add new entries here when introducing new collections — never use raw strings elsewhere.
enum FirestoreCollections {
    static let spots   = "spots"
    static let reviews = "reviews"
    static let app     = "app"
    static let welcome = "welcome"    // document under "app" collection
}

/// Tab index constants — update if tab order changes in ContentView.
/// ✏️ If you add or reorder tabs, update these numbers.
enum AppTab {
    static let explore     = 0
    static let myPicks     = 1
    static let spots       = 2
    static let leaderboard = 3
    static let profile     = 4
}

extension Notification.Name {
    /// Post to switch to the Spots tab (Explore mode) from anywhere in the app.
    static let switchToSpots = Notification.Name("switchToSpots")
    /// Post with a `SuggestedSpot` as `object` to switch to the Map tab,
    /// center on the venue, and show the ghost pin sheet.
    static let showOnMap = Notification.Name("showOnMap")
}
