import Foundation
import SwiftUI

/// A user-created food category that works alongside the hardcoded 20.
/// Stored in Firestore for community tracking and eventual promotion/relegation.
struct CustomCategory: Identifiable, Codable, Equatable, Hashable {
    /// Stable ID derived from the normalised name (e.g. "empanadas")
    var id: String { normalizedName }
    let displayName: String
    let emoji: String
    /// User-ID of the creator
    let createdBy: String
    let createdDate: Date

    /// How many users have selected this as a pick (across all users).
    /// Updated by the backend / cloud function; read-only in the app.
    var pickCount: Int = 0

    /// Auto-generated keywords for website scanning.
    var websiteKeywords: [String]

    /// Auto-generated search terms for MKLocalSearch.
    var mapSearchTerms: [String]

    // MARK: - Computed

    var normalizedName: String { displayName.lowercased().trimmingCharacters(in: .whitespaces) }
    var color: Color { .purple }

    // MARK: - Equatable / Hashable by normalizedName

    static func == (lhs: CustomCategory, rhs: CustomCategory) -> Bool {
        lhs.normalizedName == rhs.normalizedName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedName)
    }
}

// MARK: - Conversion to FoodCategory

extension CustomCategory {
    /// Converts to a FoodCategory so it can be used in the existing pick/search system.
    func toFoodCategory() -> FoodCategory {
        FoodCategory(
            id: "custom_\(normalizedName)",
            displayName: displayName,
            emoji: emoji,
            color: color,
            mapSearchTerms: mapSearchTerms,
            websiteKeywords: websiteKeywords,
            addSpotPrompt: "Search for a restaurant or shop that serves \(displayName.lowercased())."
        )
    }
}

// MARK: - Auto-generation helpers

extension CustomCategory {
    /// Creates a CustomCategory with auto-generated keywords from the display name.
    static func create(
        displayName: String,
        emoji: String,
        createdBy: String
    ) -> CustomCategory {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let lower = name.lowercased()

        // Auto-generate website keywords: the name itself + common menu suffixes
        var keywords = [lower]
        if !lower.hasSuffix("s") {
            keywords.append(lower + "s")  // plural
        }
        keywords.append("\(lower) menu")

        // Auto-generate map search terms: the name + "restaurant"
        let searchTerms = [lower, "\(lower) restaurant", "\(lower) near me"]

        return CustomCategory(
            displayName: name,
            emoji: emoji,
            createdBy: createdBy,
            createdDate: Date(),
            websiteKeywords: keywords,
            mapSearchTerms: searchTerms
        )
    }
}

// MARK: - Disambiguation

extension CustomCategory {
    /// Broad cuisine terms that are too generic to be useful as food categories.
    /// These would match nearly every restaurant and defeat the purpose.
    private static let tooGenericTerms: Set<String> = [
        "food", "restaurant", "dinner", "lunch", "breakfast", "brunch",
        "appetizer", "appetizers", "entree", "entrees", "dessert", "desserts",
        "american", "chinese", "italian", "mexican", "japanese", "indian",
        "thai", "korean", "french", "spanish", "mediterranean", "asian",
        "european", "latin", "african", "middle eastern", "fast food",
        "takeout", "delivery", "catering", "buffet", "seafood", "steak",
        "vegetarian", "vegan", "gluten free", "organic", "healthy",
        "comfort food", "street food", "snacks", "drinks", "beverages",
    ]

    /// Returns nil if valid, or an error message if the name is problematic.
    static func validate(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        if trimmed.count < 2 {
            return "Name must be at least 2 characters."
        }
        if trimmed.count > 30 {
            return "Name must be 30 characters or fewer."
        }
        if tooGenericTerms.contains(lower) {
            return "\"\(trimmed)\" is too broad. Try something more specific like a particular dish."
        }

        // Check fuzzy match against existing hardcoded categories
        let existingNames = FoodCategory.allKnownCategories.map { $0.displayName.lowercased() }
        let existingIDs = FoodCategory.allKnownCategories.map { $0.id }
        if existingNames.contains(lower) || existingIDs.contains(lower) {
            return "\"\(trimmed)\" already exists as a category."
        }

        // Check for very close matches (e.g. "taco" vs "tacos")
        for existing in existingNames {
            if lower.hasPrefix(existing) || existing.hasPrefix(lower) {
                let match = FoodCategory.allKnownCategories.first {
                    $0.displayName.lowercased() == existing
                }
                if let match {
                    return "Did you mean \"\(match.displayName)\"? It's already a category."
                }
            }
        }

        return nil  // valid
    }
}
