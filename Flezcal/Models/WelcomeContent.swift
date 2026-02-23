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
    let items: [WelcomeItem]
    let pages: [WelcomePage]
    let footer: String
    /// Brief description of what changed in this version (shown at the bottom of the sheet).
    let changeNote: String
    /// Date string for the update, e.g. "February 2026".
    let changeDate: String

    // MARK: - Fallback content shown when Firestore is unreachable
    static let fallback = WelcomeContent(
        version: "0",
        title: "Welcome to Flezcal 🍮",
        subtitle: "A global guide to sentimental favorite food and drink establishments starting, obviously, with flan and mezcal.",
        items: [
            WelcomeItem(icon: "map",             text: "Discover spots on an interactive map"),
            WelcomeItem(icon: "plus.circle",      text: "Add new flan & mezcal spots for the community"),
            WelcomeItem(icon: "star.fill",        text: "Rate and review your favorite spots"),
            WelcomeItem(icon: "trophy",           text: "Climb the leaderboard as you contribute"),
            WelcomeItem(icon: "sparkles",         text: "Ghost pins show unconfirmed places — help verify them"),
            WelcomeItem(icon: "heart.fill",       text: "Share the joy and have fun"),
        ],
        pages: [
            WelcomePage(icon: "map.fill",             headline: "Explore the Map",      description: "Pan and zoom to discover ghost pins — places that might have what you're craving. Tap 'Search This Area' after moving the map to find more.", color: "orange"),
            WelcomePage(icon: "magnifyingglass",      headline: "Search by Name",       description: "Go to the Spots tab and use Explore to search any restaurant by name. Tap a result to check their menu, or tap the map icon to see it on the map.", color: "blue"),
            WelcomePage(icon: "heart.circle.fill",    headline: "Pick Your Cravings",   description: "Choose up to 3 categories — flan, mezcal, birria, ramen, and more. We'll find spots near you that serve them.", color: "pink"),
            WelcomePage(icon: "checkmark.seal.fill",  headline: "We Check for You",     description: "When you tap a spot, we scan their actual website to confirm they serve what you're looking for.", color: "green"),
            WelcomePage(icon: "plus.circle.fill",     headline: "Grow the Guide",       description: "Add spots, rate them, upload photos. Climb the leaderboard as you contribute to the community.", color: "purple"),
        ],
        footer: "",
        changeNote: "",
        changeDate: ""
    )
}
