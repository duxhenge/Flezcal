import Foundation

/// A single bullet-point item displayed on the welcome / what's new screen.
struct WelcomeItem: Codable, Identifiable {
    var id: String { text }
    let icon: String   // SF Symbol name, e.g. "map", "sparkles", "star.fill"
    let text: String   // The description shown next to the icon
}

/// A feature walkthrough page shown below the bullet items on the welcome screen.
struct WelcomePage: Codable, Identifiable {
    var id: String { headline }
    let icon: String       // SF Symbol name
    let headline: String
    let description: String
    let color: String      // Color name: "orange", "pink", "blue", "green", "purple"
}

/// The full content for the welcome / what's new screen, fetched from Firestore.
struct WelcomeContent: Codable {
    /// Bump this string in Firestore to force the welcome screen to re-appear for all users.
    let version: String
    let title: String
    let subtitle: String
    /// "What is Flezcal?" explanation shown below the subtitle.
    let tagline: String
    let items: [WelcomeItem]
    let pages: [WelcomePage]
    let footer: String
    /// Brief description of what changed in this version (shown at the bottom of the sheet).
    let changeNote: String
    /// Date string for the update, e.g. "February 2026".
    let changeDate: String

    // MARK: - Fallback content shown when Firestore is unreachable
    static let fallback = WelcomeContent(
        version: "3.0",
        title: "Welcome to \(AppBranding.name)!",
        subtitle: "50 categories and growing, from mezcal and birria to natural wine and high-end tequila. "
            + "Pick the ones you care about and help build the guide.",
        tagline: "A \(AppBranding.name) is your favorite food or drink, the thing you'll drive across town for. "
            + "The name started as Flan + Mezcal, but a \(AppBranding.name) is now anything you're passionate about finding and sharing.",
        items: [
            WelcomeItem(
                icon: "fork.knife",
                text: "🍽️ Pick your \(AppBranding.namePlural). Choose up to 3 foods or drinks you're passionate about. "
                    + "These drive your map and search results."
            ),
            WelcomeItem(
                icon: "map",
                text: "🗺️ Find spots nearby. The map scans restaurant and bar menus "
                    + "to surface places that carry what you're looking for."
            ),
            WelcomeItem(
                icon: "plus.circle",
                text: "➕ Share what you know. Found a spot with incredible mole or a mezcal list worth the trip? "
                    + "Add it. The best finds come from people who actually care."
            ),
            WelcomeItem(
                icon: "star.fill",
                text: "⭐ Rate and verify. Who does it best? "
                    + "Rate \(AppBranding.namePlural) at your spots and verify what others have found."
            ),
            WelcomeItem(
                icon: "sparkles",
                text: "✨ Create your own. Don't see your \(AppBranding.name)? Create a trending one. "
                    + "Popular trending \(AppBranding.namePlural) may be promoted to the Top 50."
            ),
        ],
        pages: [
            WelcomePage(
                icon: "plus.circle.fill",
                headline: "Share What You Know",
                description: "The most valuable thing you can do is add a spot. Your knowledge of who serves the best version of something, that's what makes this useful. Share it.",
                color: "orange"
            ),
            WelcomePage(
                icon: "map.fill",
                headline: "The Map Works for You",
                description: "Pick your \(AppBranding.namePlural) and the map highlights matches nearby. Verified pins are community-confirmed. "
                    + "Likely pins (green ghost pins) are menu-scanned matches. Nearby pins (yellow) haven't been checked yet. "
                    + "Use the toggle pills to control which pins you see.",
                color: "blue"
            ),
            WelcomePage(
                icon: "list.bullet",
                headline: "Browse All Spots",
                description: "The Spots tab combines Verified community spots with live search results. Filter by Verified, Likely, and Nearby to find what you're looking for. The app searches automatically and highlights matches.",
                color: "orange"
            ),
            WelcomePage(
                icon: "heart.circle.fill",
                headline: "Categories Evolve",
                description: "The Top 50 \(AppBranding.namePlural) are just the start. Trending searches get tracked, and when a pattern emerges, it joins the Top 50. The community decides what matters.",
                color: "pink"
            ),
            WelcomePage(
                icon: "trophy.fill",
                headline: "Community Verified",
                description: "Anyone can add a spot. Anyone can verify it. Ratings and verifications build trust and help the best places rise to the top. Check the leaderboard to see who's leading the way.",
                color: "green"
            ),
            WelcomePage(
                icon: "person.circle.fill",
                headline: "Track Your Impact",
                description: "Every spot you add, every rating, every verification counts toward your rank. Check your profile to see your score, your progress, and your top \(AppBranding.namePlural).",
                color: "purple"
            ),
        ],
        footer: "",
        changeNote: "Unified Spots tab with Verified, Likely, and Nearby filters. Automatic search on page open. Search Wider Area on both Map and Spots tabs.",
        changeDate: "March 2026"
    )
}
