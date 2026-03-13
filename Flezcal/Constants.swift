import Foundation

/// API keys — injected at build time from Secrets.xcconfig via Info.plist.
/// Secrets.xcconfig is excluded from version control via .gitignore.
///
/// **Rotation plan:**
/// - Brave Search: Generate a new key at https://brave.com/search/api/ → Dashboard,
///   update `BRAVE_SEARCH_API_KEY` in `Secrets.xcconfig`, rebuild & ship.
///   Rotation cadence: annually or immediately if key is suspected compromised.
/// - Firebase/Google: Managed via Firebase Console → Project Settings → Service accounts.
///   The GoogleService-Info.plist API key is restricted to the app's bundle ID.
/// - No keys are stored in source control. All secrets live in Secrets.xcconfig (gitignored).
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

    // Both URLs must be publicly accessible or Apple will reject the app.
    // privacyPolicyURL is shown in Profile → About and required by App Store guidelines.
    // swiftlint:disable force_unwrapping
    static let privacyPolicyURL = URL(string: "https://flezcal.app/privacy")!
    static let termsURL = URL(string: "https://flezcal.app/terms")!
    static let supportURL = URL(string: "https://flezcal.app/support")!
    static let supportEmail = "support@flezcal.app"
    static let supportMailURL = URL(string: "mailto:support@flezcal.app")!
    // swiftlint:enable force_unwrapping

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
    static let spots             = "spots"
    static let reviews           = "reviews"
    static let customCategories  = "customCategories"
    static let app               = "app"
    static let welcome           = "welcome"    // document under "app" collection

    // Community verification & closure reports
    static let verifications     = "verifications"
    static let closureReports    = "closure_reports"

    // User profiles (display names for leaderboard)
    static let users             = "users"

    // Analytics subcollections (under spots/{id}) and top-level regional averages
    static let analyticsMonthly  = "analytics_monthly"   // spots/{id}/analytics_monthly/{YYYY-MM}
    static let viewerLog         = "viewer_log"           // spots/{id}/viewer_log/{userID}
    static let analyticsRegions  = "analytics_regions"    // top-level: regional averages

    // Admin-only collections (gated by AdminAccess.adminUID in Firestore rules)
    static let adminRevenue      = "admin_revenue"
    static let adminCosts        = "admin_costs"
    static let adminReminders    = "admin_reminders"
    static let adminNotes        = "admin_notes"

    // Feature flags, rankings, and beta feedback
    // app_config/feature_flags — read: any auth user, write: admin only
    // app_config/flezcal_rankings — read: any auth user, write: admin only
    // beta_feedback — create: any auth user, read/update/delete: admin only
    static let appConfig         = "app_config"
    static let featureFlags      = "feature_flags"      // document under app_config
    static let flezcalRankings   = "flezcal_rankings"    // document under app_config
    static let searchTermOverrides = "search_term_overrides" // document under app_config
    static let betaFeedback      = "beta_feedback"

    // Category pick tracking (per-category pick counts with per-user dedup)
    static let categoryPicks     = "categoryPicks"
}

/// Single source of truth for the app's display name.
/// Change these two values to rebrand all UI strings at once.
enum AppBranding {
    static let name = "Flezcal"
    static let namePlural = "Flezcals"
}

/// Feature flags for phased rollout.
enum FeatureFlags {
    /// When true, all 50 categories are selectable.
    /// When false, only the 3 launch defaults (mezcal, flan, tortillas) are active.
    static let broadSearchEnabled = true
    /// The IDs of the 3 locked launch categories.
    static let defaultCategories = ["mezcal", "flan", "tortillas"]
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
    /// Post with a CLLocationCoordinate2D (as ["latitude": Double, "longitude": Double])
    /// to switch to the Map tab, center on that area, and run a full search + pre-screen.
    static let showAreaOnMap = Notification.Name("showAreaOnMap")
    /// Post with latitude/longitude to switch to the Spots tab and set the
    /// custom search location to the given coordinates.
    static let showSpotsAtLocation = Notification.Name("showSpotsAtLocation")
}
