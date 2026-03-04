import Foundation
import FirebaseFirestore

/// Fetches the welcome / what's new screen content from Firestore.
///
/// Firestore document path: `app/welcome`
///
/// Example document structure:
/// {
///   "version": "1.0",
///   "title": "Welcome to Flezcal 🍮",
///   "subtitle": "Your community map for flan & mezcal in Mexico City.",
///   "items": [
///     { "icon": "map", "text": "Discover spots on an interactive map" },
///     { "icon": "sparkles", "text": "Ghost pins show unconfirmed places" }
///   ],
///   "footer": "Built with love in CDMX 🇲🇽"
/// }
///
/// To force the welcome screen to re-appear for all users, bump the "version" field.
@MainActor
class WelcomeService: ObservableObject {
    @Published var content: WelcomeContent?
    @Published var isLoading = false

    private let db = Firestore.firestore()

    func fetchWelcomeContent() async {
        isLoading = true
        do {
            let doc = try await db.collection(FirestoreCollections.app).document(FirestoreCollections.welcome).getDocument()
            guard let data = doc.data() else {
                content = .fallback
                isLoading = false
                return
            }
            content = try decode(data)
        } catch {
            // Network unavailable or decode error — show fallback silently
            content = .fallback
        }
        isLoading = false
    }

    // MARK: - Manual Firestore decode (avoids Codable dependency on DocumentSnapshot)

    private func decode(_ data: [String: Any]) throws -> WelcomeContent {
        guard
            let version  = data["version"]  as? String,
            let title    = data["title"]    as? String,
            let subtitle = data["subtitle"] as? String,
            let footer   = data["footer"]   as? String
        else {
            return .fallback
        }

        let rawItems = data["items"] as? [[String: String]] ?? []
        let items = rawItems.compactMap { dict -> WelcomeItem? in
            guard let icon = dict["icon"], let text = dict["text"] else { return nil }
            return WelcomeItem(icon: icon, text: text)
        }

        let rawPages = data["pages"] as? [[String: String]] ?? []
        let pages = rawPages.compactMap { dict -> WelcomePage? in
            guard let icon = dict["icon"],
                  let headline = dict["headline"],
                  let description = dict["description"],
                  let color = dict["color"] else { return nil }
            return WelcomePage(icon: icon, headline: headline, description: description, color: color)
        }

        let tagline = data["tagline"] as? String ?? ""
        let changeNote = data["changeNote"] as? String ?? ""
        let changeDate = data["changeDate"] as? String ?? ""

        return WelcomeContent(
            version: version,
            title: title,
            subtitle: subtitle,
            tagline: tagline.isEmpty ? WelcomeContent.fallback.tagline : tagline,
            items: items.isEmpty ? WelcomeContent.fallback.items : items,
            pages: pages.isEmpty ? WelcomeContent.fallback.pages : pages,
            footer: footer,
            changeNote: changeNote,
            changeDate: changeDate
        )
    }
}
