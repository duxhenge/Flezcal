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

    // MARK: - Memberwise init (required because custom init(from:) suppresses it)

    init(
        displayName: String,
        emoji: String,
        createdBy: String,
        createdDate: Date,
        pickCount: Int = 0,
        websiteKeywords: [String],
        mapSearchTerms: [String]
    ) {
        self.displayName = displayName
        self.emoji = emoji
        self.createdBy = createdBy
        self.createdDate = createdDate
        self.pickCount = pickCount
        self.websiteKeywords = websiteKeywords
        self.mapSearchTerms = mapSearchTerms
    }

    // MARK: - Codable

    /// Custom CodingKeys so `normalizedName` (a computed property) is included
    /// in the Firestore document. Firestore rules require it to exist and
    /// match the document ID on create.
    enum CodingKeys: String, CodingKey {
        case displayName, emoji, createdBy, createdDate, pickCount
        case websiteKeywords, mapSearchTerms, normalizedName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(pickCount, forKey: .pickCount)
        try container.encode(websiteKeywords, forKey: .websiteKeywords)
        try container.encode(mapSearchTerms, forKey: .mapSearchTerms)
        try container.encode(normalizedName, forKey: .normalizedName)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        emoji = try container.decode(String.self, forKey: .emoji)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? Date()
        pickCount = try container.decodeIfPresent(Int.self, forKey: .pickCount) ?? 0
        websiteKeywords = try container.decodeIfPresent([String].self, forKey: .websiteKeywords) ?? []
        mapSearchTerms = try container.decodeIfPresent([String].self, forKey: .mapSearchTerms) ?? []
        // normalizedName is computed — ignore any stored value
    }

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
    /// Auto-generates suggested website keywords from a display name.
    /// Used by the creation UI to pre-populate the editable search terms list.
    /// The user can then add, remove, or reorder terms before saving.
    static func suggestedKeywords(for displayName: String) -> [String] {
        let lower = displayName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lower.isEmpty else { return [] }

        var keywords = [lower]
        if !lower.hasSuffix("s") {
            keywords.append(lower + "s")  // plural
        }
        // Add individual distinctive words from multi-word names.
        // Short words (<4 chars) are skipped because they're too generic
        // (e.g. "pad" from "pad thai" would match everything).
        let words = lower.components(separatedBy: " ").filter { $0.count >= 4 }
        if words.count > 1 {
            let tooGeneric: Set<String> = [
                // Cooking methods & style descriptors
                "style", "fried", "baked", "grilled", "fresh", "house",
                "special", "classic", "spicy", "sweet", "smoked", "roasted",
                "homemade", "traditional", "authentic", "organic",
                // Common food ingredients — appear on nearly every menu
                // and produce false positives as standalone keywords
                // (e.g. "bacon" from "peameal bacon" matches any brunch spot)
                "bacon", "chicken", "beef", "pork", "fish", "shrimp",
                "lobster", "crab", "lamb", "turkey", "steak", "salmon",
                "cheese", "cream", "butter", "bread", "rice", "pasta",
                "beans", "sauce", "salad", "soup", "eggs", "corn",
                "potato", "tomato", "avocado", "mushroom", "onion",
                "pepper", "garlic", "lemon", "lime", "sugar", "chocolate",
                "vanilla", "caramel", "ginger", "honey", "tofu",
            ]
            for word in words where !tooGeneric.contains(word) {
                if !keywords.contains(word) {
                    keywords.append(word)
                }
            }
        }
        return keywords
    }

    /// Creates a CustomCategory with auto-generated keywords from the display name.
    static func create(
        displayName: String,
        emoji: String,
        createdBy: String
    ) -> CustomCategory {
        let keywords = suggestedKeywords(for: displayName)
        return create(displayName: displayName, emoji: emoji, createdBy: createdBy,
                      websiteKeywords: keywords)
    }

    /// Creates a CustomCategory with user-edited website keywords.
    /// Called when the user reviews and customizes the search terms during creation.
    static func create(
        displayName: String,
        emoji: String,
        createdBy: String,
        websiteKeywords: [String]
    ) -> CustomCategory {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let lower = name.lowercased()

        // Ensure at least the name itself is included as a keyword
        var keywords = websiteKeywords
        if keywords.isEmpty {
            keywords = [lower]
        }

        // Auto-generate map search terms: the specific name first (for Apple Maps
        // relevance), then broad fallback terms that return many nearby venues.
        // The website pre-screen will re-rank the broad results by scanning
        // homepages for the custom keyword.  Without these fallbacks, niche terms
        // like "peameal bacon" return zero Apple Maps hits and the user sees an
        // empty list.
        //
        // Alcoholic beverages get "bar" and "liquor store" instead of "cafe"
        // so the search finds bars and shops that carry the spirit/drink.
        // Wine categories also get "wine shop"; beer categories get "brewery".
        let searchTerms: [String]
        if Self.isLikelyAlcoholic(lower) {
            var terms = [lower, "bar", "liquor store", "restaurant"]
            if Self.isLikelyWine(lower) {
                terms.insert("wine shop", at: 2)
            } else if Self.isLikelyBeer(lower) {
                terms.insert("brewery", at: 2)
            }
            searchTerms = terms
        } else {
            searchTerms = [lower, "\(lower) restaurant", "restaurant", "cafe"]
        }

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

// MARK: - Alcoholic Beverage Detection

extension CustomCategory {
    /// Detects if a custom category name is likely an alcoholic beverage.
    /// Used to auto-add "bar" and "liquor store" to mapSearchTerms.
    static func isLikelyAlcoholic(_ name: String) -> Bool {
        let lower = name.lowercased()

        // Exact matches — common spirit/drink types
        let alcoholicTerms: Set<String> = [
            "wine", "beer", "ale", "lager", "stout", "porter", "pilsner",
            "whiskey", "whisky", "bourbon", "scotch", "rye",
            "vodka", "gin", "rum", "tequila", "mezcal", "mescal",
            "brandy", "cognac", "armagnac", "grappa",
            "sake", "soju", "shochu", "baijiu", "cachaca", "cachaça",
            "absinthe", "amaro", "amaretto", "limoncello",
            "fernet", "chartreuse", "campari", "aperol",
            "vermouth", "port", "sherry", "madeira", "marsala",
            "cider", "mead", "sangria", "prosecco", "champagne", "cava",
            "cocktail", "cocktails", "craft cocktails",
            "ipa", "neipa", "sour beer", "lambic", "saison",
            "pisco", "raicilla", "sotol",
        ]
        if alcoholicTerms.contains(lower) { return true }

        // Substring matches — compound names like "japanese whisky", "aged rum"
        let alcoholicSubstrings = [
            "whiskey", "whisky", "bourbon", "scotch", "vodka", "gin ",
            "tequila", "mezcal", "mescal", "rum ", " rum", "brandy",
            "cognac", "wine", "beer", "ale ", " ale", "lager",
            "cocktail", "liqueur", "spirit", "amaro",
            "sake", "soju", "ipa", "stout", "porter",
            "cider", "mead", "champagne", "prosecco",
        ]
        for sub in alcoholicSubstrings {
            if lower.contains(sub) { return true }
        }

        return false
    }

    /// Sub-classifier: is this specifically a wine category?
    /// Used to add "wine shop" to mapSearchTerms.
    static func isLikelyWine(_ name: String) -> Bool {
        let lower = name.lowercased()
        let wineTerms = [
            "wine", "prosecco", "champagne", "cava", "sangria",
            "vermouth", "port", "sherry", "madeira", "marsala",
        ]
        for term in wineTerms {
            if lower.contains(term) { return true }
        }
        return false
    }

    /// Sub-classifier: is this specifically a beer category?
    /// Used to add "brewery" to mapSearchTerms.
    static func isLikelyBeer(_ name: String) -> Bool {
        let lower = name.lowercased()
        let beerTerms = [
            "beer", "ale", "lager", "stout", "porter", "pilsner",
            "ipa", "neipa", "lambic", "saison", "cider", "mead",
        ]
        for term in beerTerms {
            if lower == term || lower.contains(term) { return true }
        }
        return false
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

    /// Blocked terms — non-food items, offensive content, and socially unacceptable
    /// entries that should never appear in the app or trend rankings.
    /// Exact matches checked first, then substring scan for partial matches.
    private static let blockedExact: Set<String> = [
        // Non-food animals
        "cat", "cats", "dog", "dogs", "kitten", "kittens", "puppy", "puppies",
        "hamster", "hamsters", "guinea pig", "parrot", "parakeet", "goldfish",
        "horse", "horses", "pony", "donkey", "monkey", "monkeys",
        // Human
        "human", "humans", "people", "person", "baby", "babies",
        "man", "woman", "child", "children",
    ]

    /// Substrings that flag offensive/inappropriate content.
    /// Checked via word-boundary regex to avoid false positives on legitimate food terms.
    private static let blockedSubstrings: [String] = [
        // Cannibalistic
        "human meat", "human flesh", "long pig", "soylent green", "cannibal",
        // Sexual
        "penis", "vagina", "testicle", "scrotum", "dildo", "vibrator",
        "aphrodisiac", "orgasm", "erotic", "pornograph", "fetish",
        // Violent / disturbing
        "roadkill", "poison", "cyanide", "arsenic",
        // Animal cruelty
        "cat meat", "dog meat", "puppy meat", "kitten meat",
        // Drugs (non-culinary)
        "cocaine", "heroin", "meth", "crystal meth", "ecstasy", "lsd",
        "fentanyl", "crack",
        // Slurs and hate (broad patterns)
        "nazi", "supremac",
    ]

    /// Returns true if the input contains blocked content.
    /// Used by CustomCategoryService to silently skip Firestore writes
    /// without showing an error — the user sees normal UI behavior but
    /// the term is never persisted or tracked.
    static func isBlocked(_ input: String) -> Bool {
        let lower = input.lowercased()
        if blockedExact.contains(lower) { return true }
        for sub in blockedSubstrings {
            if lower.contains(sub) { return true }
        }
        return false
    }

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

        // Check against visible categories only — legacy/hidden categories
        // shouldn't block custom creation since the user can't see them.
        let existingNames = FoodCategory.allCategories.map { $0.displayName.lowercased() }
        let existingIDs = FoodCategory.allCategories.map { $0.id }
        if existingNames.contains(lower) || existingIDs.contains(lower) {
            return "\"\(trimmed)\" already exists as a category."
        }

        // Check for very close matches (e.g. "taco" vs "tacos")
        for existing in existingNames {
            if lower.hasPrefix(existing) || existing.hasPrefix(lower) {
                let match = FoodCategory.allCategories.first {
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
