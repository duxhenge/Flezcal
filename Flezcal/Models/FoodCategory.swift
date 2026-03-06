import SwiftUI

// ============================================================
// FoodCategory — the curated list that powers "My Flezcals".
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

    /// Broad keywords that suggest the item might be present but need user verification.
    /// When found without a `websiteKeywords` match, the result is `.relatedFound`
    /// instead of `.confirmed`. E.g. "tortillas" for Handmade Tortillas, "custard" for Flan.
    let relatedKeywords: [String]

    /// Short prompt shown on the Add Spot screen (future use).
    let addSpotPrompt: String

    // MARK: - Codable for Color

    enum CodingKeys: String, CodingKey {
        case id, displayName, emoji, colorHex, mapSearchTerms, websiteKeywords, relatedKeywords, addSpotPrompt
    }

    init(id: String, displayName: String, emoji: String, color: Color,
         mapSearchTerms: [String], websiteKeywords: [String],
         relatedKeywords: [String] = [],
         addSpotPrompt: String) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.color = color
        self.mapSearchTerms = mapSearchTerms
        self.websiteKeywords = websiteKeywords
        self.relatedKeywords = relatedKeywords
        self.addSpotPrompt = addSpotPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self, forKey: .id)
        displayName    = try c.decode(String.self, forKey: .displayName)
        emoji          = try c.decode(String.self, forKey: .emoji)
        mapSearchTerms = try c.decode([String].self, forKey: .mapSearchTerms)
        websiteKeywords = try c.decode([String].self, forKey: .websiteKeywords)
        relatedKeywords = try c.decodeIfPresent([String].self, forKey: .relatedKeywords) ?? []
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
        if !relatedKeywords.isEmpty {
            try c.encode(relatedKeywords, forKey: .relatedKeywords)
        }
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

    // ── Launch Trio (permanent) ──────────────────────────────────────────────

    static let mezcal = FoodCategory(
        id: "mezcal",
        displayName: "Mezcal",
        emoji: "🥃",
        color: .green,
        mapSearchTerms: ["mezcal", "bar", "liquor store", "wine spirits", "restaurante", "restaurant"],
        websiteKeywords: ["mezcal", "mezcalería", "mezcales",
                          "mezcal list", "mezcal menu", "mezcal selection",
                          "agave spirits"],
        relatedKeywords: ["agave spirit", "agave cocktail"],
        addSpotPrompt: "Search for a bar, restaurant, or store to add it as a mezcal spot."
    )

    static let flan = FoodCategory(
        id: "flan",
        displayName: "Flan",
        emoji: "🍮",
        color: .orange,
        mapSearchTerms: ["flan", "bakery", "restaurant"],
        websiteKeywords: ["flan", "flan casero"],
        relatedKeywords: ["custard", "caramel custard", "postre"],
        addSpotPrompt: "Search for a restaurant or bakery to add it as a flan spot."
    )

    static let tortillas = FoodCategory(
        id: "tortillas",
        displayName: "Handmade Tortillas",
        emoji: "🫓",
        color: Color(red: 0.85, green: 0.65, blue: 0.2),
        mapSearchTerms: ["handmade tortillas", "tortilleria", "fresh tortillas", "tortillas"],
        websiteKeywords: ["handmade tortillas", "tortillas hechas a mano", "fresh tortillas",
                          "tortilleria", "house-made tortillas", "homemade tortillas"],
        relatedKeywords: ["tortillas", "corn tortillas", "flour tortillas"],
        addSpotPrompt: "Search for a restaurant or tortilleria that makes handmade tortillas."
    )

    // ── Drinks ───────────────────────────────────────────────────────────────

    static let bourbon = FoodCategory(
        id: "bourbon",
        displayName: "Bourbon",
        emoji: "🥃",
        color: Color(red: 0.72, green: 0.45, blue: 0.1),
        mapSearchTerms: ["bourbon", "whiskey bar", "bourbon bar", "liquor store"],
        websiteKeywords: ["bourbon", "kentucky bourbon", "small batch bourbon",
                          "single barrel bourbon", "bourbon selection"],
        relatedKeywords: ["whiskey", "rye whiskey"],
        addSpotPrompt: "Search for a bar or restaurant with a bourbon selection."
    )

    static let fernetBranca = FoodCategory(
        id: "fernet_branca",
        displayName: "Fernet Branca",
        emoji: "🌿",
        color: Color(red: 0.1, green: 0.35, blue: 0.15),
        mapSearchTerms: ["fernet", "cocktail bar", "bar", "liquor store"],
        websiteKeywords: ["fernet", "fernet branca", "fernet-branca",
                          "amaro", "digestif"],
        relatedKeywords: ["amaro", "digestivo", "bitter"],
        addSpotPrompt: "Search for a bar that serves Fernet Branca."
    )

    static let newEnglandIPA = FoodCategory(
        id: "new_england_ipa",
        displayName: "New England IPA",
        emoji: "🍺",
        color: Color(red: 0.85, green: 0.65, blue: 0.15),
        mapSearchTerms: ["IPA", "craft beer", "brewery", "taproom", "liquor store"],
        websiteKeywords: ["new england ipa", "neipa", "hazy ipa",
                          "juicy ipa", "hazy pale ale"],
        relatedKeywords: ["ipa", "craft beer", "hazy"],
        addSpotPrompt: "Search for a brewery or taproom with New England IPAs."
    )

    static let singleMaltScotch = FoodCategory(
        id: "single_malt_scotch",
        displayName: "Single Malt Scotch",
        emoji: "🥃",
        color: Color(red: 0.55, green: 0.3, blue: 0.05),
        mapSearchTerms: ["scotch", "whisky bar", "whiskey bar", "liquor store"],
        websiteKeywords: ["single malt", "scotch whisky", "single malt scotch",
                          "speyside", "islay", "highland scotch"],
        relatedKeywords: ["scotch", "whisky", "malt whisky"],
        addSpotPrompt: "Search for a bar with a single malt scotch selection."
    )

    // ── Savory ───────────────────────────────────────────────────────────────

    static let peamealBacon = FoodCategory(
        id: "peameal_bacon",
        displayName: "Peameal Bacon",
        emoji: "🥓",
        color: Color(red: 0.7, green: 0.4, blue: 0.2),
        mapSearchTerms: ["peameal bacon", "canadian bacon", "breakfast restaurant"],
        websiteKeywords: ["peameal bacon", "peameal", "canadian bacon",
                          "back bacon", "cornmeal bacon"],
        relatedKeywords: ["bacon sandwich", "breakfast sandwich"],
        addSpotPrompt: "Search for a restaurant or deli that serves peameal bacon."
    )

    static let woodFiredPizza = FoodCategory(
        id: "wood_fired_pizza",
        displayName: "Wood-Fired Pizza",
        emoji: "🍕",
        color: Color(red: 0.8, green: 0.2, blue: 0.1),
        mapSearchTerms: ["wood fired pizza", "pizzeria", "neapolitan pizza"],
        websiteKeywords: ["wood fired", "wood-fired", "wood oven", "brick oven",
                          "neapolitan", "napoletana", "pizza napoletana"],
        relatedKeywords: ["00 flour", "fior di latte", "pizzaiolo"],
        addSpotPrompt: "Search for a wood-fired pizzeria."
    )

    static let paella = FoodCategory(
        id: "paella",
        displayName: "Paella",
        emoji: "🥘",
        color: Color(red: 0.9, green: 0.7, blue: 0.1),
        mapSearchTerms: ["paella", "spanish restaurant", "tapas"],
        websiteKeywords: ["paella", "paella valenciana", "paella mixta",
                          "arroz", "bomba rice"],
        relatedKeywords: ["spanish rice", "arroz con mariscos"],
        addSpotPrompt: "Search for a restaurant that serves paella."
    )

    static let oysters = FoodCategory(
        id: "oysters",
        displayName: "Oysters",
        emoji: "🦪",
        color: Color(red: 0.2, green: 0.45, blue: 0.5),
        mapSearchTerms: ["oysters", "oyster bar", "seafood restaurant"],
        websiteKeywords: ["oysters", "oyster bar", "fresh oysters",
                          "oyster selection", "shucked"],
        relatedKeywords: ["raw bar"],
        addSpotPrompt: "Search for an oyster bar or raw bar restaurant."
    )

    static let pho = FoodCategory(
        id: "pho",
        displayName: "Pho",
        emoji: "🍲",
        color: Color(red: 0.6, green: 0.35, blue: 0.1),
        mapSearchTerms: ["pho", "vietnamese restaurant", "pho restaurant"],
        websiteKeywords: ["pho", "phở", "pho menu"],
        relatedKeywords: ["vietnamese noodle", "beef noodle soup"],
        addSpotPrompt: "Search for a pho or Vietnamese noodle restaurant."
    )

    static let pozole = FoodCategory(
        id: "pozole",
        displayName: "Pozole",
        emoji: "🍲",
        color: Color(red: 0.7, green: 0.2, blue: 0.15),
        mapSearchTerms: ["pozole", "mexican restaurant", "pozoleria"],
        websiteKeywords: ["pozole", "pozole rojo", "pozole verde",
                          "pozole blanco", "pozolería"],
        relatedKeywords: ["hominy", "mexican soup"],
        addSpotPrompt: "Search for a restaurant that serves pozole."
    )

    static let tartare = FoodCategory(
        id: "tartare",
        displayName: "Tartare",
        emoji: "🥩",
        color: Color(red: 0.6, green: 0.1, blue: 0.1),
        mapSearchTerms: ["tartare", "french restaurant", "steak tartare"],
        websiteKeywords: ["tartare", "steak tartare", "beef tartare",
                          "tuna tartare", "salmon tartare"],
        relatedKeywords: ["crudo", "carpaccio", "raw beef"],
        addSpotPrompt: "Search for a restaurant that serves tartare."
    )

    static let fugu = FoodCategory(
        id: "fugu",
        displayName: "Fugu",
        emoji: "🐡",
        color: Color(red: 0.15, green: 0.4, blue: 0.65),
        mapSearchTerms: ["fugu", "japanese restaurant", "pufferfish"],
        websiteKeywords: ["fugu", "pufferfish", "blowfish",
                          "fugu sashimi", "tessa"],
        relatedKeywords: ["puffer fish", "torafugu"],
        addSpotPrompt: "Search for a Japanese restaurant that serves fugu."
    )

    static let bibimbap = FoodCategory(
        id: "bibimbap",
        displayName: "Bibimbap",
        emoji: "🍚",
        color: Color(red: 0.8, green: 0.25, blue: 0.15),
        mapSearchTerms: ["bibimbap", "korean restaurant", "korean food"],
        websiteKeywords: ["bibimbap", "dolsot bibimbap", "stone pot bibimbap",
                          "mixed rice bowl"],
        relatedKeywords: ["korean rice", "gochujang"],
        addSpotPrompt: "Search for a Korean restaurant that serves bibimbap."
    )

    static let ibericoHam = FoodCategory(
        id: "iberico_ham",
        displayName: "Iberico Ham",
        emoji: "🍖",
        color: Color(red: 0.65, green: 0.15, blue: 0.25),
        mapSearchTerms: ["iberico", "jamon", "spanish restaurant", "tapas"],
        websiteKeywords: ["iberico", "ibérico", "jamón ibérico", "jamon iberico",
                          "pata negra", "bellota"],
        relatedKeywords: ["jamon", "jamón", "cured ham"],
        addSpotPrompt: "Search for a restaurant or shop that serves Iberico ham."
    )

    static let caviar = FoodCategory(
        id: "caviar",
        displayName: "Caviar",
        emoji: "🫧",
        color: Color(red: 0.15, green: 0.2, blue: 0.3),
        mapSearchTerms: ["caviar", "seafood restaurant", "fine dining"],
        websiteKeywords: ["caviar", "osetra", "beluga caviar",
                          "sturgeon caviar", "caviar service"],
        relatedKeywords: ["fish roe", "sturgeon"],
        addSpotPrompt: "Search for a restaurant with a caviar service."
    )

    static let pierogi = FoodCategory(
        id: "pierogi",
        displayName: "Pierogi",
        emoji: "🥟",
        color: Color(red: 0.8, green: 0.6, blue: 0.15),
        mapSearchTerms: ["pierogi", "polish restaurant", "polish food"],
        websiteKeywords: ["pierogi", "pierog", "pierogy", "pierogies",
                          "polish dumplings", "ruskie"],
        relatedKeywords: ["polish food", "dumplings"],
        addSpotPrompt: "Search for a restaurant that serves pierogi."
    )

    static let lobsterRolls = FoodCategory(
        id: "lobster_rolls",
        displayName: "Lobster Rolls",
        emoji: "🦞",
        color: Color(red: 0.85, green: 0.3, blue: 0.2),
        mapSearchTerms: ["lobster roll", "lobster shack", "seafood restaurant"],
        websiteKeywords: ["lobster roll", "lobster rolls", "lobster sandwich",
                          "maine lobster roll", "connecticut lobster roll"],
        relatedKeywords: ["lobster", "seafood shack"],
        addSpotPrompt: "Search for a seafood spot that serves lobster rolls."
    )

    static let smashburgers = FoodCategory(
        id: "smashburgers",
        displayName: "Smashburgers",
        emoji: "🍔",
        color: Color(red: 0.8, green: 0.15, blue: 0.1),
        mapSearchTerms: ["smashburger", "burger restaurant", "burgers"],
        websiteKeywords: ["smashburger", "smash burger", "smashed burger",
                          "smash patty", "crispy edges"],
        relatedKeywords: ["burger", "cheeseburger"],
        addSpotPrompt: "Search for a restaurant that serves smashburgers."
    )

    // ── Sweets & Specialty ───────────────────────────────────────────────────

    static let mapleSyrup = FoodCategory(
        id: "maple_syrup",
        displayName: "Maple Syrup",
        emoji: "🍁",
        color: Color(red: 0.72, green: 0.4, blue: 0.08),
        mapSearchTerms: ["maple syrup", "sugar shack", "maple farm"],
        websiteKeywords: ["maple syrup", "pure maple", "maple sugar",
                          "sugar shack", "cabane à sucre", "grade a maple"],
        relatedKeywords: ["maple", "sirop d'érable"],
        addSpotPrompt: "Search for a spot that serves or sells real maple syrup."
    )

    static let artisanChocolate = FoodCategory(
        id: "artisan_chocolate",
        displayName: "Artisan Chocolate",
        emoji: "🍫",
        color: Color(red: 0.35, green: 0.18, blue: 0.08),
        mapSearchTerms: ["artisan chocolate", "chocolatier", "chocolate shop"],
        websiteKeywords: ["artisan chocolate", "bean to bar", "craft chocolate",
                          "single origin chocolate", "chocolatier", "cacao"],
        relatedKeywords: ["chocolate", "truffles", "bonbon"],
        addSpotPrompt: "Search for a chocolatier or artisan chocolate shop."
    )

    // ── Legacy definitions (kept for backward compat with Firestore) ────────
    // These are NOT in allCategories (won't appear in picker grid)
    // but ARE in allKnownCategories so existing spots still decode.

    static let naturalWine = FoodCategory(
        id: "natural_wine", displayName: "Natural Wine", emoji: "🍷",
        color: Color(red: 0.6, green: 0.1, blue: 0.3),
        mapSearchTerms: ["natural wine", "wine shop", "liquor store"], websiteKeywords: ["natural wine"],
        addSpotPrompt: "Legacy category."
    )
    static let craftBeer = FoodCategory(
        id: "craft_beer", displayName: "Craft Beer", emoji: "🍺",
        color: Color(red: 0.8, green: 0.5, blue: 0.1),
        mapSearchTerms: ["craft beer", "brewery", "liquor store"], websiteKeywords: ["craft beer"],
        addSpotPrompt: "Legacy category."
    )
    static let sake = FoodCategory(
        id: "sake", displayName: "Sake", emoji: "🍶",
        color: Color(red: 0.2, green: 0.5, blue: 0.7),
        mapSearchTerms: ["sake", "japanese restaurant", "liquor store"], websiteKeywords: ["sake"],
        addSpotPrompt: "Legacy category."
    )
    static let specialtyCoffee = FoodCategory(
        id: "specialty_coffee", displayName: "Specialty Coffee", emoji: "☕",
        color: Color(red: 0.4, green: 0.25, blue: 0.1),
        mapSearchTerms: ["specialty coffee"], websiteKeywords: ["specialty coffee"],
        addSpotPrompt: "Legacy category."
    )
    static let boba = FoodCategory(
        id: "boba", displayName: "Boba", emoji: "🧋",
        color: Color(red: 0.7, green: 0.45, blue: 0.2),
        mapSearchTerms: ["boba"], websiteKeywords: ["boba"],
        addSpotPrompt: "Legacy category."
    )
    static let cocktails = FoodCategory(
        id: "cocktails", displayName: "Craft Cocktails", emoji: "🍸",
        color: Color(red: 0.2, green: 0.3, blue: 0.7),
        mapSearchTerms: ["cocktail bar", "bar", "liquor store"], websiteKeywords: ["craft cocktail"],
        addSpotPrompt: "Legacy category."
    )
    static let mochi = FoodCategory(
        id: "mochi", displayName: "Mochi", emoji: "🍡",
        color: Color(red: 0.9, green: 0.5, blue: 0.7),
        mapSearchTerms: ["mochi"], websiteKeywords: ["mochi"],
        addSpotPrompt: "Legacy category."
    )
    static let churros = FoodCategory(
        id: "churros", displayName: "Churros", emoji: "🍩",
        color: Color(red: 0.85, green: 0.55, blue: 0.1),
        mapSearchTerms: ["churros"], websiteKeywords: ["churros"],
        addSpotPrompt: "Legacy category."
    )
    static let gelato = FoodCategory(
        id: "gelato", displayName: "Gelato", emoji: "🍨",
        color: Color(red: 0.4, green: 0.7, blue: 0.9),
        mapSearchTerms: ["gelato"], websiteKeywords: ["gelato"],
        addSpotPrompt: "Legacy category."
    )
    static let crepes = FoodCategory(
        id: "crepes", displayName: "Crepes", emoji: "🥞",
        color: Color(red: 0.9, green: 0.75, blue: 0.4),
        mapSearchTerms: ["crepes"], websiteKeywords: ["crepes"],
        addSpotPrompt: "Legacy category."
    )
    static let sushi = FoodCategory(
        id: "sushi", displayName: "Sushi", emoji: "🍣",
        color: Color(red: 0.9, green: 0.3, blue: 0.3),
        mapSearchTerms: ["sushi"], websiteKeywords: ["sushi"],
        addSpotPrompt: "Legacy category."
    )
    static let ramen = FoodCategory(
        id: "ramen", displayName: "Ramen", emoji: "🍜",
        color: Color(red: 0.85, green: 0.2, blue: 0.1),
        mapSearchTerms: ["ramen"], websiteKeywords: ["ramen"],
        addSpotPrompt: "Legacy category."
    )
    static let tacos = FoodCategory(
        id: "tacos", displayName: "Tacos", emoji: "🌮",
        color: Color(red: 0.95, green: 0.6, blue: 0.0),
        mapSearchTerms: ["tacos"], websiteKeywords: ["tacos"],
        addSpotPrompt: "Legacy category."
    )
    static let dimSum = FoodCategory(
        id: "dim_sum", displayName: "Dim Sum", emoji: "🥟",
        color: Color(red: 0.8, green: 0.15, blue: 0.15),
        mapSearchTerms: ["dim sum"], websiteKeywords: ["dim sum"],
        addSpotPrompt: "Legacy category."
    )
    static let pizza = FoodCategory(
        id: "pizza", displayName: "Neapolitan Pizza", emoji: "🍕",
        color: Color(red: 0.8, green: 0.2, blue: 0.1),
        mapSearchTerms: ["pizza"], websiteKeywords: ["neapolitan"],
        addSpotPrompt: "Legacy category."
    )
    static let birria = FoodCategory(
        id: "birria", displayName: "Birria", emoji: "🫕",
        color: Color(red: 0.7, green: 0.1, blue: 0.0),
        mapSearchTerms: ["birria"], websiteKeywords: ["birria"],
        addSpotPrompt: "Legacy category."
    )
    static let baklava = FoodCategory(
        id: "baklava", displayName: "Baklava", emoji: "🍯",
        color: Color(red: 0.75, green: 0.55, blue: 0.1),
        mapSearchTerms: ["baklava"], websiteKeywords: ["baklava"],
        addSpotPrompt: "Legacy category."
    )

    // MARK: - Full catalogue (order = display order in the grid)
    //
    // Launch trio + 20 curated Flezcals.

    static let allCategories: [FoodCategory] = [
        // ── Launch trio (permanent) ──
        mezcal, flan, tortillas,
        // ── Curated Flezcals ──
        peamealBacon, bourbon, fernetBranca, woodFiredPizza,
        paella, mapleSyrup, newEnglandIPA, oysters,
        artisanChocolate, pho, pozole, tartare,
        fugu, bibimbap, ibericoHam, caviar,
        pierogi, singleMaltScotch, lobsterRolls, smashburgers,
    ]

    /// All categories including legacy ones that may still exist in Firestore.
    /// Use `allCategories` for the picker grid; use this for decoding/lookup.
    static let allKnownCategories: [FoodCategory] = allCategories + [
        naturalWine, craftBeer, sake, specialtyCoffee, boba, cocktails,
        mochi, churros, gelato, crepes, sushi, ramen, tacos, dimSum,
        pizza, birria, baklava,
    ]

    /// Common venue types offered as quick-add suggestions in EditSpotSearchView.
    static let commonVenueTypes: [String] = [
        "restaurant", "bar", "cafe", "bakery", "pizzeria", "diner", "bistro", "deli",
        "brewery", "winery", "taproom", "pub", "cocktail bar",
        "liquor store", "wine shop", "grocery store", "market", "butcher", "cheese shop",
        "taqueria", "trattoria", "brasserie", "izakaya", "cantina",
        "food hall", "food truck", "hotel", "fine dining", "steakhouse",
    ]

    /// SF Symbol icon for a venue type string. Used by EditSpotSearchView grid.
    static func venueTypeIcon(for type: String) -> String {
        switch type.lowercased() {
        case "restaurant":      return "fork.knife"
        case "bar":             return "wineglass"
        case "cafe":            return "cup.and.saucer"
        case "bakery":          return "birthday.cake"
        case "pizzeria":        return "flame"
        case "diner":           return "fork.knife"
        case "bistro":          return "fork.knife"
        case "deli":            return "basket"
        case "brewery":         return "mug"
        case "winery":          return "wineglass.fill"
        case "taproom":         return "mug.fill"
        case "pub":             return "mug"
        case "cocktail bar":    return "wineglass"
        case "liquor store":    return "bottle.nalgene"
        case "wine shop":       return "wineglass.fill"
        case "grocery store":   return "cart"
        case "market":          return "cart"
        case "butcher":         return "takeoutbag.and.cup.and.straw"
        case "cheese shop":     return "takeoutbag.and.cup.and.straw"
        case "taqueria":        return "fork.knife"
        case "trattoria":       return "fork.knife"
        case "brasserie":       return "fork.knife"
        case "izakaya":         return "wineglass"
        case "cantina":         return "wineglass"
        case "food hall":       return "building.2"
        case "food truck":      return "box.truck"
        case "hotel":           return "bed.double"
        case "fine dining":     return "star"
        case "steakhouse":      return "flame.fill"
        default:                return "mappin"
        }
    }

    // MARK: - User picks registration (for website scanning)

    /// Custom picks registered by the user — merged into scanning loops.
    /// Set by UserPicksService when picks change.
    @MainActor private(set) static var activeCustomPicks: [FoodCategory] = []

    /// Built-in picks whose websiteKeywords have been edited by the user.
    /// Keyed by category ID. These override the static defaults in allScannable.
    @MainActor private(set) static var modifiedBuiltInPicks: [String: FoodCategory] = [:]

    /// All scannable categories: the 20 built-in (with user overrides) + custom picks.
    /// Used by WebsiteCheckService.scanForCategories() to include user-edited
    /// keywords and user-created categories in HTML keyword matching.
    @MainActor static var allScannable: [FoodCategory] {
        let builtIn = allCategories.map { cat in
            modifiedBuiltInPicks[cat.id] ?? cat
        }
        return builtIn + activeCustomPicks
    }

    /// Registers the user's picks so modified keywords are included in website scanning.
    /// Custom picks (custom_ prefix) are added alongside the built-in categories.
    /// Modified built-in picks override their static counterparts during scanning.
    @MainActor static func registerUserPicks(_ picks: [FoodCategory]) {
        activeCustomPicks = picks.filter { $0.id.hasPrefix("custom_") }
        modifiedBuiltInPicks = [:]
        for pick in picks where !pick.id.hasPrefix("custom_") {
            if let original = allCategories.first(where: { $0.id == pick.id }),
               original.websiteKeywords != pick.websiteKeywords {
                modifiedBuiltInPicks[pick.id] = pick
            }
        }
    }

    // MARK: - Default picks (used when user hasn't chosen yet)

    static let defaultPicks: [FoodCategory] = [mezcal, flan, tortillas]

    // MARK: - Launch categories (locked, non-removable)

    /// The 3 categories locked for launch. Always active for every user.
    static let launchCategories: [FoodCategory] = [mezcal, flan, tortillas]

    /// Whether a category is one of the 3 locked launch defaults.
    static func isLaunchCategory(_ category: FoodCategory) -> Bool {
        FeatureFlags.defaultCategories.contains(category.id)
    }

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
