import Foundation

/// A single bullet-point item displayed on the welcome / what's new screen.
struct WelcomeItem: Codable, Identifiable {
    var id: String { text }
    let icon: String   // SF Symbol name, e.g. "map", "sparkles", "star.fill"
    let text: String   // The description shown next to the icon
}

/// The full content for the welcome / what's new screen, fetched from Firestore.
struct WelcomeContent: Codable {
    /// Bump this string in Firestore to force the welcome screen to re-appear for all users.
    let version: String
    let title: String
    let subtitle: String
    let items: [WelcomeItem]
    let footer: String

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
        footer: ""
    )
}
