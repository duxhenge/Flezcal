import SwiftUI

// ============================================================
// FoodCategory — the curated list that powers "My Picks".
//
// To add a new item: add one entry to `allCategories` below.
// No other files need editing.
// ============================================================

struct FoodCategory: Identifiable, Codable, Equatable, Hashable {
    let id: String          // stable key stored in UserDefaults
    let displayName: String
    let emoji: String
    let color: Color        // accent color for cards and filter pills

    /// Terms used for MKLocalSearch natural-language queries.
    /// First entry is the primary (most specific) query.
    let mapSearchTerms: [String]

    /// Keywords scanned on a venue's homepage HTML (Pass 1 of website check).
    /// First entry is also used for Brave Search (Passes 2 & 3).
    let websiteKeywords: [String]

    /// Short prompt shown on the Add Spot screen (future use).
    let addSpotPrompt: String

    // MARK: - Codable for Color

    enum CodingKeys: String, CodingKey {
        case id, displayName, emoji, colorHex, mapSearchTerms, websiteKeywords, addSpotPrompt
    }

    init(id: String, displayName: String, emoji: String, color: Color,
         mapSearchTerms: [String], websiteKeywords: [String], addSpotPrompt: String) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.color = color
        self.mapSearchTerms = mapSearchTerms
        self.websiteKeywords = websiteKeywords
        self.addSpotPrompt = addSpotPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self, forKey: .id)
        displayName    = try c.decode(String.self, forKey: .displayName)
        emoji          = try c.decode(String.self, forKey: .emoji)
        mapSearchTerms = try c.decode([String].self, forKey: .mapSearchTerms)
        websiteKeywords = try c.decode([String].self, forKey: .websiteKeywords)
        addSpotPrompt  = try c.decode(String.self, forKey: .addSpotPrompt)
        let hex = try c.decode(String.self, forKey: .colorHex)
        color = Color(hex: hex)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(displayName,     forKey: .displayName)
        try c.encode(emoji,           forKey: .emoji)
        try c.encode(mapSearchTerms,  forKey: .mapSearchTerms)
        try c.encode(websiteKeywords, forKey: .websiteKeywords)
        try c.encode(addSpotPrompt,   forKey: .addSpotPrompt)
        try c.encode(color.hexString, forKey: .colorHex)
    }

    // MARK: - Equatable / Hashable by id

    static func == (lhs: FoodCategory, rhs: FoodCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Color hex helpers

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0xFF8000FF
        let r = Double((val >> 24) & 0xFF) / 255
        let g = Double((val >> 16) & 0xFF) / 255
        let b = Double((val >>  8) & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02XFF",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Curated catalogue

extension FoodCategory {

    // ── Drinks ────────────────────────────────────────────────────────────────

    static let mezcal = FoodCategory(
        id: "mezcal",
        displayName: "Mezcal",
        emoji: "🥃",
        color: .green,
        mapSearchTerms: ["mezcal", "bar", "restaurante", "restaurant"],
        websiteKeywords: ["mezcal", "mezcalería", "agave", "mezcales",
                          "mezcal list", "mezcal menu", "mezcal selection"],
        addSpotPrompt: "Search for a bar, restaurant, or store to add it as a mezcal spot."
    )

    static let naturalWine = FoodCategory(
        id: "natural_wine",
        displayName: "Natural Wine",
        emoji: "🍷",
        color: Color(red: 0.6, green: 0.1, blue: 0.3),
        mapSearchTerms: ["natural wine", "wine bar", "wine shop"],
        websiteKeywords: ["natural wine", "natty wine", "orange wine",
                          "biodynamic wine", "skin contact"],
        addSpotPrompt: "Search for a wine bar or shop that carries natural wines."
    )

    static let craftBeer = FoodCategory(
        id: "craft_beer",
        displayName: "Craft Beer",
        emoji: "🍺",
        color: Color(red: 0.8, green: 0.5, blue: 0.1),
        mapSearchTerms: ["craft beer", "brewery", "taproom"],
        websiteKeywords: ["craft beer", "microbrewery", "taproom",
                          "IPA", "craft ale", "local brew"],
        addSpotPrompt: "Search for a brewery, taproom, or craft beer bar."
    )

    static let sake = FoodCategory(
        id: "sake",
        displayName: "Sake",
        emoji: "🍶",
        color: Color(red: 0.2, green: 0.5, blue: 0.7),
        mapSearchTerms: ["sake bar", "sake", "japanese restaurant"],
        websiteKeywords: ["sake", "nihonshu", "junmai", "sake selection",
                          "sake list", "sake bar"],
        addSpotPrompt: "Search for a sake bar or Japanese restaurant with a sake program."
    )

    static let specialtyCoffee = FoodCategory(
        id: "specialty_coffee",
        displayName: "Specialty Coffee",
        emoji: "☕",
        color: Color(red: 0.4, green: 0.25, blue: 0.1),
        mapSearchTerms: ["specialty coffee", "coffee shop", "cafe"],
        websiteKeywords: ["specialty coffee", "single origin", "pour over",
                          "espresso", "third wave", "direct trade"],
        addSpotPrompt: "Search for a specialty coffee shop or roastery."
    )

    static let boba = FoodCategory(
        id: "boba",
        displayName: "Boba",
        emoji: "🧋",
        color: Color(red: 0.7, green: 0.45, blue: 0.2),
        mapSearchTerms: ["boba", "bubble tea", "boba tea"],
        websiteKeywords: ["boba", "bubble tea", "tapioca", "milk tea",
                          "taro", "boba shop"],
        addSpotPrompt: "Search for a boba or bubble tea shop."
    )

    static let cocktails = FoodCategory(
        id: "cocktails",
        displayName: "Craft Cocktails",
        emoji: "🍸",
        color: Color(red: 0.2, green: 0.3, blue: 0.7),
        mapSearchTerms: ["cocktail bar", "craft cocktails", "speakeasy"],
        websiteKeywords: ["craft cocktail", "mixology", "artisan cocktail",
                          "cocktail menu", "signature cocktail"],
        addSpotPrompt: "Search for a craft cocktail bar."
    )

    // ── Desserts & Sweets ─────────────────────────────────────────────────────

    static let flan = FoodCategory(
        id: "flan",
        displayName: "Flan",
        emoji: "🍮",
        color: .orange,
        mapSearchTerms: ["flan", "bakery", "restaurant"],
        websiteKeywords: ["flan", "flan casero", "postre", "custard",
                          "caramel custard"],
        addSpotPrompt: "Search for a restaurant or bakery to add it as a flan spot."
    )

    static let mochi = FoodCategory(
        id: "mochi",
        displayName: "Mochi",
        emoji: "🍡",
        color: Color(red: 0.9, green: 0.5, blue: 0.7),
        mapSearchTerms: ["mochi", "mochi ice cream", "japanese dessert"],
        websiteKeywords: ["mochi", "daifuku", "mochi ice cream",
                          "wagashi", "japanese sweets"],
        addSpotPrompt: "Search for a mochi shop or Japanese sweets cafe."
    )

    static let churros = FoodCategory(
        id: "churros",
        displayName: "Churros",
        emoji: "🍩",
        color: Color(red: 0.85, green: 0.55, blue: 0.1),
        mapSearchTerms: ["churros", "churro", "mexican bakery"],
        websiteKeywords: ["churros", "churro", "churrería", "churros con chocolate"],
        addSpotPrompt: "Search for a churro shop or Mexican bakery."
    )

    static let gelato = FoodCategory(
        id: "gelato",
        displayName: "Gelato",
        emoji: "🍨",
        color: Color(red: 0.4, green: 0.7, blue: 0.9),
        mapSearchTerms: ["gelato", "gelateria", "italian ice cream"],
        websiteKeywords: ["gelato", "gelateria", "artigianale",
                          "italian gelato", "artisan gelato"],
        addSpotPrompt: "Search for a gelateria or artisan ice cream shop."
    )

    static let crepes = FoodCategory(
        id: "crepes",
        displayName: "Crepes",
        emoji: "🥞",
        color: Color(red: 0.9, green: 0.75, blue: 0.4),
        mapSearchTerms: ["crepes", "creperie", "french crepes"],
        websiteKeywords: ["crepes", "crêpes", "creperie", "crêperie",
                          "sweet crepes", "savory crepes"],
        addSpotPrompt: "Search for a creperie or cafe that serves crepes."
    )

    // ── Savory ────────────────────────────────────────────────────────────────

    static let sushi = FoodCategory(
        id: "sushi",
        displayName: "Sushi",
        emoji: "🍣",
        color: Color(red: 0.9, green: 0.3, blue: 0.3),
        mapSearchTerms: ["sushi", "sushi bar", "japanese restaurant"],
        websiteKeywords: ["sushi", "omakase", "nigiri", "sashimi",
                          "sushi bar", "maki", "sushi roll"],
        addSpotPrompt: "Search for a sushi bar or Japanese restaurant."
    )

    static let ramen = FoodCategory(
        id: "ramen",
        displayName: "Ramen",
        emoji: "🍜",
        color: Color(red: 0.85, green: 0.2, blue: 0.1),
        mapSearchTerms: ["ramen", "ramen restaurant", "ramen shop"],
        websiteKeywords: ["ramen", "tonkotsu", "shoyu ramen", "miso ramen",
                          "ramen shop", "noodle soup"],
        addSpotPrompt: "Search for a ramen restaurant."
    )

    static let tacos = FoodCategory(
        id: "tacos",
        displayName: "Tacos",
        emoji: "🌮",
        color: Color(red: 0.95, green: 0.6, blue: 0.0),
        mapSearchTerms: ["tacos", "taqueria", "taco truck"],
        websiteKeywords: ["tacos", "taqueria", "al pastor", "birria tacos",
                          "taco", "mexican street food"],
        addSpotPrompt: "Search for a taqueria or taco spot."
    )

    static let dimSum = FoodCategory(
        id: "dim_sum",
        displayName: "Dim Sum",
        emoji: "🥟",
        color: Color(red: 0.8, green: 0.15, blue: 0.15),
        mapSearchTerms: ["dim sum", "dim sum restaurant", "yum cha"],
        websiteKeywords: ["dim sum", "yum cha", "har gow", "siu mai",
                          "dumplings", "dim sum menu"],
        addSpotPrompt: "Search for a dim sum restaurant."
    )

    static let pizza = FoodCategory(
        id: "pizza",
        displayName: "Neapolitan Pizza",
        emoji: "🍕",
        color: Color(red: 0.8, green: 0.2, blue: 0.1),
        mapSearchTerms: ["neapolitan pizza", "wood fired pizza", "pizzeria"],
        websiteKeywords: ["neapolitan", "wood fired", "napoletana",
                          "pizza napoletana", "00 flour", "fior di latte"],
        addSpotPrompt: "Search for a Neapolitan or wood-fired pizzeria."
    )

    static let birria = FoodCategory(
        id: "birria",
        displayName: "Birria",
        emoji: "🫕",
        color: Color(red: 0.7, green: 0.1, blue: 0.0),
        mapSearchTerms: ["birria", "birria tacos", "birrieria"],
        websiteKeywords: ["birria", "birrieria", "consomé",
                          "birria tacos", "quesabirria"],
        addSpotPrompt: "Search for a birria restaurant or truck."
    )

    static let oysters = FoodCategory(
        id: "oysters",
        displayName: "Oysters",
        emoji: "🦪",
        color: Color(red: 0.2, green: 0.45, blue: 0.5),
        mapSearchTerms: ["oysters", "oyster bar", "seafood restaurant"],
        websiteKeywords: ["oysters", "oyster bar", "fresh oysters",
                          "raw bar", "oyster selection", "shucked"],
        addSpotPrompt: "Search for an oyster bar or raw bar restaurant."
    )

    static let pho = FoodCategory(
        id: "pho",
        displayName: "Pho",
        emoji: "🍲",
        color: Color(red: 0.6, green: 0.35, blue: 0.1),
        mapSearchTerms: ["pho", "vietnamese restaurant", "pho restaurant"],
        websiteKeywords: ["pho", "phở", "vietnamese noodle",
                          "beef noodle soup", "pho menu"],
        addSpotPrompt: "Search for a pho or Vietnamese noodle restaurant."
    )

    static let baklava = FoodCategory(
        id: "baklava",
        displayName: "Baklava",
        emoji: "🍯",
        color: Color(red: 0.75, green: 0.55, blue: 0.1),
        mapSearchTerms: ["baklava", "turkish bakery", "middle eastern bakery"],
        websiteKeywords: ["baklava", "baklawa", "turkish sweets",
                          "pistachio baklava", "pastry", "middle eastern sweets"],
        addSpotPrompt: "Search for a bakery or shop that makes baklava."
    )

    // MARK: - Full catalogue (order = display order in the grid)
    //
    // 10 Common + 10 Trendy/Hip. Flan and Mezcal are permanent (origin story).
    // The split is conceptual — all 20 are equal in the app.

    static let allCategories: [FoodCategory] = [
        // ── Common (widely recognized food categories) ──
        tacos, pizza, ramen, sushi, pho,
        craftBeer, specialtyCoffee, gelato, oysters, dimSum,
        // ── Trendy / Hip (emerging, niche, or culturally specific) ──
        mezcal, flan,          // permanent — the origin story
        birria, naturalWine, boba, baklava,
        mochi, cocktails, sake, churros,
    ]

    /// All categories including legacy ones that may still exist in Firestore.
    /// Use `allCategories` for the picker grid; use this for decoding/lookup.
    static let allKnownCategories: [FoodCategory] = allCategories + [crepes]

    // MARK: - Default picks (used when user hasn't chosen yet)

    static let defaultPicks: [FoodCategory] = [mezcal, flan]

    // MARK: - Lookup helpers

    /// Returns the FoodCategory whose id matches the given string, or nil if not found.
    /// Checks allKnownCategories (including legacy ones) for backward compat.
    static func by(id: String) -> FoodCategory? {
        allKnownCategories.first { $0.id == id }
    }

    /// Convenience initializer from a SpotCategory.
    /// Since SpotCategory.rawValue == FoodCategory.id by design, this always succeeds
    /// for any SpotCategory case that was added alongside its FoodCategory counterpart.
    init?(spotCategory: SpotCategory) {
        guard let match = FoodCategory.allKnownCategories.first(where: { $0.id == spotCategory.rawValue }) else {
            return nil
        }
        self = match
    }
}
