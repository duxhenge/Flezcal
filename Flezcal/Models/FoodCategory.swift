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
    /// instead of `.confirmed`. E.g. "custard" for Flan, "polish food" for Pierogi.
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

    // MARK: - Derived Display Properties
    //
    // These are the single source of truth for category display metadata.
    // SpotCategory delegates to these via FoodCategory.by(id:).
    // When dynamic ranking ships, Firestore overrides will layer on top.

    /// Whether this is a legacy category no longer shown in the picker grid.
    var isLegacy: Bool {
        let legacyIDs: Set<String> = [
            "negroni", "bourbon", "single_malt_scotch", "fernet_branca",
            "peameal_bacon", "maple_syrup", "fugu", "smashburgers", "pizza"
        ]
        return legacyIDs.contains(id)
    }

    /// SF Symbol used where an emoji can't be rendered (e.g. Picker, map Marker).
    var icon: String {
        switch id {
        // Spirit drinks
        case "mezcal", "whiskey", "amaro", "cider":
            return "cup.and.saucer"
        // Beer
        case "new_england_ipa", "craft_beer":
            return "mug"
        // Wine / cocktails / sake
        case "natural_wine", "sake", "cocktails":
            return "wineglass"
        // Coffee / tea
        case "specialty_coffee", "tea", "matcha":
            return "cup.and.saucer.fill"
        // Boba / kombucha
        case "boba", "kombucha":
            return "takeoutbag.and.cup.and.straw"
        // Legacy spirits
        case "negroni", "bourbon", "single_malt_scotch", "fernet_branca":
            return "cup.and.saucer"
        // Everything else (food + sweets + custom)
        default:
            return "fork.knife"
        }
    }

    /// Label for the offerings section header (e.g. "Mezcal Brands", "Taco Types").
    var offeringsLabel: String {
        switch id {
        // ── Food ──
        case "mezcal":            return "Mezcal Brands"
        case "flan":              return "Flan Styles"
        case "tacos":             return "Taco Types"
        case "birria":            return "Birria Styles"
        case "pozole":            return "Pozole Styles"
        case "ceviche":           return "Ceviche Types"
        case "mole":              return "Mole Varieties"
        case "pupusas":           return "Pupusa Fillings"
        case "ramen":             return "Ramen Styles"
        case "sushi":             return "Sushi Highlights"
        case "omakase":           return "Omakase Style"
        case "dim_sum":           return "Dim Sum Dishes"
        case "pho":               return "Pho Types"
        case "bibimbap":          return "Bibimbap Types"
        case "korean_bbq":        return "BBQ Cuts"
        case "dumplings":         return "Dumpling Types"
        case "poke":              return "Poke Bowls"
        case "tapas":             return "Tapas Dishes"
        case "paella":            return "Paella Types"
        case "iberico_ham":       return "Ham Grades"
        case "wood_fired_pizza":  return "Pizza Styles"
        case "oysters":           return "Oyster Varieties"
        case "lobster_rolls":     return "Roll Styles"
        case "tartare":           return "Tartare Types"
        case "caviar":            return "Caviar Types"
        case "pierogi":           return "Pierogi Fillings"
        // ── Drinks ──
        case "whiskey":           return "Whiskey Brands"
        case "amaro":             return "Amaro Brands"
        case "new_england_ipa":   return "Beer Brands"
        case "craft_beer":        return "Beer Styles"
        case "natural_wine":      return "Wine Styles"
        case "sake":              return "Sake Types"
        case "cocktails":         return "Cocktail Styles"
        case "specialty_coffee":  return "Coffee Methods"
        case "boba":              return "Drink Flavors"
        case "tea":               return "Tea Varieties"
        case "matcha":            return "Matcha Types"
        case "kombucha":          return "Kombucha Flavors"
        case "cider":             return "Cider Styles"
        // ── Sweets & Specialty ──
        case "artisan_chocolate": return "Chocolate Types"
        case "khachapuri":        return "Khachapuri Styles"
        case "baklava":           return "Baklava Types"
        case "churros":           return "Churro Varieties"
        case "gelato":            return "Gelato Flavors"
        case "mochi":             return "Mochi Types"
        case "empanadas":         return "Empanada Fillings"
        case "crepes":            return "Crepe Varieties"
        case "creme_brulee":      return "Brûlée Flavors"
        case "croissants":        return "Croissant Types"
        case "tres_leches":       return "Tres Leches Styles"
        // ── Legacy ──
        case "negroni":           return "Negroni Variations"
        case "bourbon":           return "Bourbon Brands"
        case "single_malt_scotch": return "Scotch Brands"
        case "fernet_branca":     return "Serving Styles"
        case "peameal_bacon":     return "Serving Styles"
        case "maple_syrup":       return "Syrup Grades"
        case "fugu":              return "Fugu Preparations"
        case "smashburgers":      return "Burger Styles"
        case "pizza":             return "Pizza Styles"
        default:                  return "\(displayName) Varieties"
        }
    }

    /// Singular label for an offering entry (e.g. "brand", "style", "flavor").
    var offeringSingular: String {
        switch id {
        // ── Food ──
        case "mezcal":            return "brand"
        case "flan":              return "style"
        case "tacos":             return "type"
        case "birria":            return "style"
        case "pozole":            return "style"
        case "ceviche":           return "type"
        case "mole":              return "variety"
        case "pupusas":           return "filling"
        case "ramen":             return "style"
        case "sushi":             return "highlight"
        case "omakase":           return "style"
        case "dim_sum":           return "dish"
        case "pho":               return "type"
        case "bibimbap":          return "type"
        case "korean_bbq":        return "cut"
        case "dumplings":         return "type"
        case "poke":              return "bowl"
        case "tapas":             return "dish"
        case "paella":            return "type"
        case "iberico_ham":       return "grade"
        case "wood_fired_pizza":  return "style"
        case "oysters":           return "variety"
        case "lobster_rolls":     return "style"
        case "tartare":           return "type"
        case "caviar":            return "type"
        case "pierogi":           return "filling"
        // ── Drinks ──
        case "whiskey":           return "brand"
        case "amaro":             return "brand"
        case "new_england_ipa":   return "brand"
        case "craft_beer":        return "style"
        case "natural_wine":      return "style"
        case "sake":              return "type"
        case "cocktails":         return "style"
        case "specialty_coffee":  return "method"
        case "boba":              return "flavor"
        case "tea":               return "variety"
        case "matcha":            return "type"
        case "kombucha":          return "flavor"
        case "cider":             return "style"
        // ── Sweets & Specialty ──
        case "artisan_chocolate": return "type"
        case "khachapuri":        return "style"
        case "baklava":           return "type"
        case "churros":           return "variety"
        case "gelato":            return "flavor"
        case "mochi":             return "type"
        case "empanadas":         return "filling"
        case "crepes":            return "variety"
        case "creme_brulee":      return "flavor"
        case "croissants":        return "type"
        case "tres_leches":       return "style"
        // ── Legacy ──
        case "negroni":           return "variation"
        case "bourbon":           return "brand"
        case "single_malt_scotch": return "brand"
        case "fernet_branca":     return "style"
        case "peameal_bacon":     return "style"
        case "maple_syrup":       return "grade"
        case "fugu":              return "preparation"
        case "smashburgers":      return "style"
        case "pizza":             return "style"
        default:                  return "variety"
        }
    }

    /// Example offerings shown as placeholder hints.
    var offeringsExamples: String {
        switch id {
        // ── Food ──
        case "mezcal":            return "e.g. Del Maguey, Vago, Bozal"
        case "flan":              return "e.g. Classic, Coconut, Cheese Flan"
        case "tacos":             return "e.g. Al Pastor, Carnitas, Handmade Tortillas"
        case "birria":            return "e.g. Tacos, Consomme, Quesabirria"
        case "pozole":            return "e.g. Rojo, Verde, Blanco"
        case "ceviche":           return "e.g. Mixto, Pescado, Shrimp"
        case "mole":              return "e.g. Negro, Poblano, Rojo, Coloradito"
        case "pupusas":           return "e.g. Revueltas, Queso, Frijol, Loroco"
        case "ramen":             return "e.g. Tonkotsu, Shoyu, Miso, Tsukemen"
        case "sushi":             return "e.g. Omakase, Chirashi, Salmon Nigiri"
        case "omakase":           return "e.g. Edomae, Seasonal, Chef's Special"
        case "dim_sum":           return "e.g. Har Gow, Siu Mai, Char Siu Bao"
        case "pho":               return "e.g. Tai (Rare Beef), Dac Biet (Special)"
        case "bibimbap":          return "e.g. Dolsot (Stone Pot), Vegetable, Beef"
        case "korean_bbq":        return "e.g. Bulgogi, Galbi, Samgyeopsal"
        case "dumplings":         return "e.g. Xiaolongbao, Gyoza, Potstickers"
        case "poke":              return "e.g. Ahi Tuna, Salmon, Spicy Mayo"
        case "tapas":             return "e.g. Croquetas, Patatas Bravas, Gambas"
        case "paella":            return "e.g. Valenciana, Mixta, Mariscos"
        case "iberico_ham":       return "e.g. Bellota, Cebo, Reserva"
        case "wood_fired_pizza":  return "e.g. Margherita, Marinara, Diavola"
        case "oysters":           return "e.g. Wellfleet, Kumamoto, Blue Point"
        case "lobster_rolls":     return "e.g. Maine Style, Connecticut Style"
        case "tartare":           return "e.g. Steak, Tuna, Salmon"
        case "caviar":            return "e.g. Osetra, Beluga, Paddlefish"
        case "pierogi":           return "e.g. Potato & Cheese, Sauerkraut, Meat"
        // ── Drinks ──
        case "whiskey":           return "e.g. Maker's Mark, Lagavulin, Nikka"
        case "amaro":             return "e.g. Fernet, Averna, Montenegro, Cynar"
        case "new_england_ipa":   return "e.g. Trillium, Tree House, Other Half"
        case "craft_beer":        return "e.g. Hazy IPA, Stout, Sour, Pilsner"
        case "natural_wine":      return "e.g. Pet-Nat, Orange, Skin Contact"
        case "sake":              return "e.g. Junmai, Daiginjo, Nigori"
        case "cocktails":         return "e.g. Negroni, Old Fashioned, Mezcal Mule"
        case "specialty_coffee":  return "e.g. Pour Over, Espresso, Cold Brew"
        case "boba":              return "e.g. Taro, Brown Sugar, Matcha"
        case "tea":               return "e.g. Earl Grey, Oolong, Pu-erh, Chai"
        case "matcha":            return "e.g. Ceremonial, Latte, Iced, Koicha"
        case "kombucha":          return "e.g. Ginger, Lavender, Hibiscus"
        case "cider":             return "e.g. Dry, Semi-Sweet, Rosé, Perry"
        // ── Sweets & Specialty ──
        case "artisan_chocolate": return "e.g. Single Origin Bar, Truffles, Bonbons"
        case "khachapuri":        return "e.g. Adjaruli, Imeruli, Megruli"
        case "baklava":           return "e.g. Pistachio, Walnut, Bird's Nest"
        case "churros":           return "e.g. Classic, Filled, Chocolate Dipped"
        case "gelato":            return "e.g. Pistachio, Stracciatella, Hazelnut"
        case "mochi":             return "e.g. Daifuku, Ice Cream, Strawberry"
        case "empanadas":         return "e.g. Beef, Chicken, Cheese, Spinach"
        case "crepes":            return "e.g. Nutella, Savory Ham & Cheese"
        case "creme_brulee":      return "e.g. Classic Vanilla, Lavender, Espresso"
        case "croissants":        return "e.g. Butter, Almond, Pain au Chocolat"
        case "tres_leches":       return "e.g. Classic, Chocolate, Strawberry"
        // ── Legacy ──
        case "negroni":           return "e.g. Classic, Sbagliato, White, Mezcal"
        case "bourbon":           return "e.g. Maker's Mark, Woodford Reserve, Buffalo Trace"
        case "single_malt_scotch": return "e.g. Lagavulin, Macallan, Glenfiddich"
        case "fernet_branca":     return "e.g. Neat, with Cola, Cocktail"
        case "peameal_bacon":     return "e.g. Classic Sandwich, Eggs Benedict, Platter"
        case "maple_syrup":       return "e.g. Grade A Amber, Dark Robust, Maple Candy"
        case "fugu":              return "e.g. Sashimi (Tessa), Hot Pot (Tecchiri)"
        case "smashburgers":      return "e.g. Single, Double, Cheese, Special Sauce"
        case "pizza":             return "e.g. Margherita, Marinara, Diavola"
        default:                  return "e.g. Add specific varieties or styles"
        }
    }
}

// MARK: - Color hex helpers

extension Color {
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

// MARK: - Curated catalogue (50 Flezcals)

extension FoodCategory {

    // ══════════════════════════════════════════════════════════════
    // 🍽️  FOOD  (24 categories)
    // ══════════════════════════════════════════════════════════════

    // ── Launch Trio ──────────────────────────────────────────────

    static let mezcal = FoodCategory(
        id: "mezcal",
        displayName: "Mezcal",
        emoji: "🥃",
        color: .green,
        mapSearchTerms: ["mezcal", "mezcal bar", "tequila bar", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["mezcal", "mezcalería", "mezcales",
                          "mezcal list", "mezcal menu", "mezcal selection",
                          "agave spirits"],
        relatedKeywords: ["agave spirit", "agave cocktail"],
        addSpotPrompt: "Search for a bar, restaurant, or store to add it as a mezcal spot."
    )

    // ── Latin / Mexican ─────────────────────────────────────────

    static let tacos = FoodCategory(
        id: "tacos",
        displayName: "Tacos",
        emoji: "🌮",
        color: Color(red: 0.95, green: 0.6, blue: 0.0),
        mapSearchTerms: ["tacos", "taqueria", "taco restaurant", "mexican restaurant",
                         "tortilleria", "handmade tortillas", "fresh tortillas", "mexican bakery"],
        websiteKeywords: ["tacos", "taqueria", "al pastor", "carnitas",
                          "suadero", "taco menu",
                          "handmade tortillas", "tortillas hechas a mano", "fresh tortillas",
                          "tortilleria", "house-made tortillas", "homemade tortillas"],
        relatedKeywords: ["taco", "mexican street food", "carne asada",
                          "tortillas", "corn tortillas", "flour tortillas"],
        addSpotPrompt: "Search for a taqueria or taco spot."
    )

    static let birria = FoodCategory(
        id: "birria",
        displayName: "Birria",
        emoji: "🫕",
        color: Color(red: 0.7, green: 0.1, blue: 0.0),
        mapSearchTerms: ["birria", "birrieria", "birria tacos", "mexican restaurant", "taqueria"],
        websiteKeywords: ["birria", "birrieria", "consomé", "birria tacos",
                          "quesabirria", "birria de res"],
        relatedKeywords: ["consomme", "stewed meat"],
        addSpotPrompt: "Search for a birria restaurant or truck."
    )

    static let pozole = FoodCategory(
        id: "pozole",
        displayName: "Pozole",
        emoji: "🍲",
        color: Color(red: 0.7, green: 0.2, blue: 0.15),
        mapSearchTerms: ["pozole", "pozoleria", "mexican restaurant", "mexican food"],
        websiteKeywords: ["pozole", "pozole rojo", "pozole verde",
                          "pozole blanco", "pozolería"],
        relatedKeywords: ["hominy", "mexican soup"],
        addSpotPrompt: "Search for a restaurant that serves pozole."
    )

    static let ceviche = FoodCategory(
        id: "ceviche",
        displayName: "Ceviche",
        emoji: "🐟",
        color: Color(red: 0.0, green: 0.6, blue: 0.6),
        mapSearchTerms: ["ceviche", "mariscos"],
        websiteKeywords: ["ceviche", "cevichería", "leche de tigre",
                          "ceviche mixto", "ceviche de pescado"],
        relatedKeywords: ["mariscos", "aguachile", "tiradito"],
        addSpotPrompt: "Search for a restaurant that serves ceviche."
    )

    static let mole = FoodCategory(
        id: "mole",
        displayName: "Mole",
        emoji: "🫕",
        color: Color(red: 0.4, green: 0.15, blue: 0.1),
        mapSearchTerms: ["mole", "oaxacan restaurant", "mole poblano"],
        websiteKeywords: ["mole", "mole negro", "mole poblano", "mole rojo",
                          "mole oaxaqueño", "mole coloradito"],
        relatedKeywords: ["oaxacan", "salsa madre"],
        addSpotPrompt: "Search for a restaurant that serves mole."
    )

    static let pupusas = FoodCategory(
        id: "pupusas",
        displayName: "Pupusas",
        emoji: "🫓",
        color: Color(red: 0.75, green: 0.5, blue: 0.15),
        mapSearchTerms: ["pupusas", "pupuseria", "salvadoran restaurant", "salvadoran food"],
        websiteKeywords: ["pupusas", "pupusería", "curtido", "pupusa",
                          "pupusas revueltas"],
        relatedKeywords: ["salvadoran", "salvadoreño"],
        addSpotPrompt: "Search for a pupuseria or Salvadoran restaurant."
    )

    // ── Asian ───────────────────────────────────────────────────

    static let ramen = FoodCategory(
        id: "ramen",
        displayName: "Ramen",
        emoji: "🍜",
        color: Color(red: 0.85, green: 0.2, blue: 0.1),
        mapSearchTerms: ["ramen", "ramen shop", "ramen restaurant"],
        websiteKeywords: ["ramen", "tonkotsu", "shoyu ramen", "miso ramen",
                          "ramen shop", "tsukemen"],
        relatedKeywords: ["noodle soup", "japanese noodle"],
        addSpotPrompt: "Search for a ramen restaurant."
    )

    static let sushi = FoodCategory(
        id: "sushi",
        displayName: "Sushi",
        emoji: "🍣",
        color: Color(red: 0.9, green: 0.3, blue: 0.3),
        mapSearchTerms: ["sushi", "sushi restaurant", "sushi bar"],
        websiteKeywords: ["sushi", "nigiri", "sashimi", "sushi bar",
                          "maki", "sushi roll", "chirashi"],
        relatedKeywords: ["japanese", "raw fish"],
        addSpotPrompt: "Search for a sushi bar or Japanese restaurant."
    )

    static let omakase = FoodCategory(
        id: "omakase",
        displayName: "Omakase",
        emoji: "🍣",
        color: Color(red: 0.2, green: 0.2, blue: 0.4),
        mapSearchTerms: ["omakase", "sushi restaurant", "sushi bar"],
        websiteKeywords: ["omakase", "chef's choice", "tasting menu sushi",
                          "omakase menu", "kappo"],
        relatedKeywords: ["kaiseki", "edomae", "itamae"],
        addSpotPrompt: "Search for a restaurant offering omakase."
    )

    static let dimSum = FoodCategory(
        id: "dim_sum",
        displayName: "Dim Sum",
        emoji: "🥟",
        color: Color(red: 0.8, green: 0.15, blue: 0.15),
        mapSearchTerms: ["dim sum", "cantonese restaurant", "yum cha"],
        websiteKeywords: ["dim sum", "yum cha", "har gow", "siu mai",
                          "dim sum menu", "steamed dumplings"],
        relatedKeywords: ["dumplings", "cantonese", "char siu bao"],
        addSpotPrompt: "Search for a dim sum restaurant."
    )

    static let pho = FoodCategory(
        id: "pho",
        displayName: "Pho",
        emoji: "🍲",
        color: Color(red: 0.6, green: 0.35, blue: 0.1),
        mapSearchTerms: ["pho", "pho restaurant", "vietnamese restaurant"],
        websiteKeywords: ["pho", "phở", "pho menu"],
        relatedKeywords: ["vietnamese noodle", "beef noodle soup"],
        addSpotPrompt: "Search for a pho or Vietnamese noodle restaurant."
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

    static let koreanBBQ = FoodCategory(
        id: "korean_bbq",
        displayName: "Korean BBQ",
        emoji: "🥩",
        color: Color(red: 0.75, green: 0.15, blue: 0.1),
        mapSearchTerms: ["korean bbq", "korean barbecue", "korean restaurant", "kbbq"],
        websiteKeywords: ["korean bbq", "korean barbecue", "kbbq", "bulgogi",
                          "galbi", "samgyeopsal", "ssam"],
        relatedKeywords: ["korean grill", "tabletop grill", "banchan"],
        addSpotPrompt: "Search for a Korean BBQ restaurant."
    )

    static let dumplings = FoodCategory(
        id: "dumplings",
        displayName: "Dumplings",
        emoji: "🥟",
        color: Color(red: 0.85, green: 0.55, blue: 0.2),
        mapSearchTerms: ["dumplings", "dumpling restaurant", "dumpling house"],
        websiteKeywords: ["dumplings", "xiaolongbao", "gyoza", "jiaozi",
                          "soup dumplings", "potstickers", "mandu"],
        relatedKeywords: ["steamed dumplings", "pan fried dumplings", "wonton"],
        addSpotPrompt: "Search for a dumpling restaurant."
    )

    static let poke = FoodCategory(
        id: "poke",
        displayName: "Poke",
        emoji: "🐟",
        color: Color(red: 0.1, green: 0.55, blue: 0.7),
        mapSearchTerms: ["poke", "poke bowl", "poke restaurant"],
        websiteKeywords: ["poke", "poké", "poke bowl", "ahi poke",
                          "poke menu", "build your bowl"],
        relatedKeywords: ["hawaiian", "raw fish bowl"],
        addSpotPrompt: "Search for a poke restaurant."
    )

    // ── European / Mediterranean ────────────────────────────────

    static let tapas = FoodCategory(
        id: "tapas",
        displayName: "Tapas",
        emoji: "🍢",
        color: Color(red: 0.8, green: 0.4, blue: 0.1),
        mapSearchTerms: ["tapas", "tapas bar", "spanish bar"],
        websiteKeywords: ["tapas", "pintxos", "pinchos", "tapas bar",
                          "raciones", "croquetas", "patatas bravas"],
        relatedKeywords: ["spanish small plates", "spanish appetizers"],
        addSpotPrompt: "Search for a tapas bar or Spanish restaurant."
    )

    static let paella = FoodCategory(
        id: "paella",
        displayName: "Paella",
        emoji: "🥘",
        color: Color(red: 0.9, green: 0.7, blue: 0.1),
        mapSearchTerms: ["paella"],
        websiteKeywords: ["paella", "paella valenciana", "paella mixta",
                          "arroz", "bomba rice"],
        relatedKeywords: ["spanish rice", "arroz con mariscos"],
        addSpotPrompt: "Search for a restaurant that serves paella."
    )

    static let ibericoHam = FoodCategory(
        id: "iberico_ham",
        displayName: "Iberico Ham",
        emoji: "🍖",
        color: Color(red: 0.65, green: 0.15, blue: 0.25),
        mapSearchTerms: ["iberico", "jamon iberico", "tapas bar", "tapas"],
        websiteKeywords: ["iberico", "ibérico", "jamón ibérico", "jamon iberico",
                          "pata negra", "bellota"],
        relatedKeywords: ["jamon", "jamón", "cured ham"],
        addSpotPrompt: "Search for a restaurant or shop that serves Iberico ham."
    )

    static let woodFiredPizza = FoodCategory(
        id: "wood_fired_pizza",
        displayName: "Wood-Fired Pizza",
        emoji: "🍕",
        color: Color(red: 0.8, green: 0.2, blue: 0.1),
        mapSearchTerms: ["wood fired pizza", "neapolitan pizza", "pizzeria", "pizza restaurant"],
        websiteKeywords: ["wood fired", "wood-fired", "wood oven", "brick oven",
                          "neapolitan", "napoletana", "pizza napoletana"],
        relatedKeywords: ["00 flour", "fior di latte", "pizzaiolo"],
        addSpotPrompt: "Search for a wood-fired pizzeria."
    )

    // ── Seafood / Raw ───────────────────────────────────────────

    static let oysters = FoodCategory(
        id: "oysters",
        displayName: "Oysters",
        emoji: "🦪",
        color: Color(red: 0.2, green: 0.45, blue: 0.5),
        mapSearchTerms: ["oysters", "oyster bar", "raw bar", "seafood restaurant"],
        websiteKeywords: ["oysters", "oyster bar", "fresh oysters",
                          "oyster selection", "shucked"],
        relatedKeywords: ["raw bar"],
        addSpotPrompt: "Search for an oyster bar or raw bar restaurant."
    )

    static let lobsterRolls = FoodCategory(
        id: "lobster_rolls",
        displayName: "Lobster Rolls",
        emoji: "🦞",
        color: Color(red: 0.85, green: 0.3, blue: 0.2),
        mapSearchTerms: ["lobster roll", "lobster shack", "lobster restaurant", "seafood restaurant", "clam shack"],
        websiteKeywords: ["lobster roll", "lobster rolls", "lobster sandwich",
                          "maine lobster roll", "connecticut lobster roll"],
        relatedKeywords: ["lobster", "seafood shack"],
        addSpotPrompt: "Search for a seafood spot that serves lobster rolls."
    )

    static let tartare = FoodCategory(
        id: "tartare",
        displayName: "Tartare",
        emoji: "🥩",
        color: Color(red: 0.6, green: 0.1, blue: 0.1),
        mapSearchTerms: ["steak tartare", "tartare", "french restaurant", "bistro"],
        websiteKeywords: ["tartare", "steak tartare", "beef tartare",
                          "tuna tartare", "salmon tartare"],
        relatedKeywords: ["crudo", "carpaccio", "raw beef"],
        addSpotPrompt: "Search for a restaurant that serves tartare."
    )

    static let caviar = FoodCategory(
        id: "caviar",
        displayName: "Caviar",
        emoji: "🫧",
        color: Color(red: 0.15, green: 0.2, blue: 0.3),
        mapSearchTerms: ["caviar", "seafood restaurant", "oyster bar"],
        websiteKeywords: ["caviar", "osetra", "beluga caviar",
                          "sturgeon caviar", "caviar service"],
        relatedKeywords: ["fish roe", "sturgeon"],
        addSpotPrompt: "Search for a restaurant with a caviar service."
    )

    // ══════════════════════════════════════════════════════════════
    // 🍹  DRINKS  (14 categories)
    // ══════════════════════════════════════════════════════════════

    static let whiskey = FoodCategory(
        id: "whiskey",
        displayName: "Whiskey",
        emoji: "🥃",
        color: Color(red: 0.65, green: 0.38, blue: 0.08),
        mapSearchTerms: ["whiskey bar", "bourbon bar", "distillery", "whiskey", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["whiskey", "whisky", "bourbon", "scotch", "rye whiskey",
                          "single malt", "whiskey selection", "whiskey list"],
        relatedKeywords: ["spirits", "brown spirits", "dram"],
        addSpotPrompt: "Search for a bar or restaurant with a whiskey selection."
    )

    static let amaro = FoodCategory(
        id: "amaro",
        displayName: "Amaro",
        emoji: "🌿",
        color: Color(red: 0.1, green: 0.35, blue: 0.15),
        mapSearchTerms: ["amaro", "cocktail bar", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["amaro", "amari", "digestif", "digestivo",
                          "fernet", "averna", "montenegro"],
        relatedKeywords: ["bitter", "aperitif", "italian liqueur"],
        addSpotPrompt: "Search for a bar with an amaro selection."
    )

    static let newEnglandIPA = FoodCategory(
        id: "new_england_ipa",
        displayName: "New England IPA",
        emoji: "🍺",
        color: Color(red: 0.85, green: 0.65, blue: 0.15),
        mapSearchTerms: ["craft beer", "brewery", "taproom", "beer bar", "brewpub", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["new england ipa", "neipa", "hazy ipa",
                          "juicy ipa", "hazy pale ale"],
        relatedKeywords: ["ipa", "craft beer", "hazy"],
        addSpotPrompt: "Search for a brewery or taproom with New England IPAs."
    )

    static let craftBeer = FoodCategory(
        id: "craft_beer",
        displayName: "Craft Beer",
        emoji: "🍺",
        color: Color(red: 0.8, green: 0.5, blue: 0.1),
        mapSearchTerms: ["craft beer", "brewery", "taproom", "beer bar", "brewpub", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["craft beer", "microbrewery", "taproom", "craft ale",
                          "local brew", "on tap", "draft list"],
        relatedKeywords: ["brewery", "beer garden", "tap list"],
        addSpotPrompt: "Search for a brewery, taproom, or craft beer bar."
    )

    static let naturalWine = FoodCategory(
        id: "natural_wine",
        displayName: "Natural Wine",
        emoji: "🍷",
        color: Color(red: 0.6, green: 0.1, blue: 0.3),
        mapSearchTerms: ["natural wine", "wine bar", "wine shop", "wine store", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["natural wine", "natty wine", "orange wine",
                          "biodynamic wine", "skin contact", "low intervention"],
        relatedKeywords: ["organic wine", "pet-nat", "minimal intervention"],
        addSpotPrompt: "Search for a wine bar or shop that carries natural wines."
    )

    static let sake = FoodCategory(
        id: "sake",
        displayName: "Sake",
        emoji: "🍶",
        color: Color(red: 0.2, green: 0.5, blue: 0.7),
        mapSearchTerms: ["sake", "sake bar", "izakaya", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["sake", "nihonshu", "junmai", "sake selection",
                          "sake list", "sake bar", "daiginjo"],
        relatedKeywords: ["japanese rice wine", "sake pairing"],
        addSpotPrompt: "Search for a sake bar or Japanese restaurant with a sake program."
    )

    static let cocktails = FoodCategory(
        id: "cocktails",
        displayName: "Craft Cocktails",
        emoji: "🍸",
        color: Color(red: 0.2, green: 0.3, blue: 0.7),
        mapSearchTerms: ["cocktail bar", "craft cocktails", "speakeasy", "cocktail lounge", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["craft cocktail", "mixology", "artisan cocktail",
                          "cocktail menu", "signature cocktail", "house cocktail"],
        relatedKeywords: ["speakeasy", "cocktail lounge", "mixologist"],
        addSpotPrompt: "Search for a craft cocktail bar."
    )

    static let specialtyCoffee = FoodCategory(
        id: "specialty_coffee",
        displayName: "Specialty Coffee",
        emoji: "☕",
        color: Color(red: 0.4, green: 0.25, blue: 0.1),
        mapSearchTerms: ["specialty coffee", "coffee roaster", "coffee shop", "cafe", "espresso bar"],
        websiteKeywords: ["specialty coffee", "single origin", "pour over",
                          "third wave", "direct trade", "micro roast"],
        relatedKeywords: ["espresso", "coffee roastery", "latte art"],
        addSpotPrompt: "Search for a specialty coffee shop or roastery."
    )

    static let boba = FoodCategory(
        id: "boba",
        displayName: "Boba",
        emoji: "🧋",
        color: Color(red: 0.7, green: 0.45, blue: 0.2),
        mapSearchTerms: ["boba", "bubble tea", "boba tea", "milk tea", "tea shop"],
        websiteKeywords: ["boba", "bubble tea", "tapioca", "milk tea",
                          "taro", "boba shop"],
        relatedKeywords: ["pearl tea", "tea shop"],
        addSpotPrompt: "Search for a boba or bubble tea shop."
    )

    static let tea = FoodCategory(
        id: "tea",
        displayName: "Tea",
        emoji: "🍵",
        color: Color(red: 0.4, green: 0.55, blue: 0.3),
        mapSearchTerms: ["tea house", "tea room", "tea shop", "afternoon tea", "chai"],
        websiteKeywords: ["loose leaf tea", "tea service", "afternoon tea",
                          "high tea", "tea house", "tea room", "tea menu",
                          "chai", "oolong", "pu-erh"],
        relatedKeywords: ["tea", "herbal tea", "tea ceremony", "tea tasting"],
        addSpotPrompt: "Search for a tea house, tea room, or cafe with a tea program."
    )

    static let matcha = FoodCategory(
        id: "matcha",
        displayName: "Matcha",
        emoji: "🍵",
        color: Color(red: 0.3, green: 0.6, blue: 0.2),
        mapSearchTerms: ["matcha", "matcha cafe", "tea house", "japanese cafe"],
        websiteKeywords: ["matcha", "matcha latte", "ceremonial matcha",
                          "matcha menu", "koicha", "usucha"],
        relatedKeywords: ["green tea", "tea ceremony"],
        addSpotPrompt: "Search for a matcha cafe or tea house."
    )

    static let kombucha = FoodCategory(
        id: "kombucha",
        displayName: "Kombucha",
        emoji: "🫙",
        color: Color(red: 0.5, green: 0.7, blue: 0.3),
        mapSearchTerms: ["kombucha", "kombucha bar", "juice bar"],
        websiteKeywords: ["kombucha", "kombucha on tap", "fermented tea",
                          "probiotic", "jun kombucha"],
        relatedKeywords: ["fermented", "probiotic drink", "scoby"],
        addSpotPrompt: "Search for a kombucha bar or shop."
    )

    static let cider = FoodCategory(
        id: "cider",
        displayName: "Cider",
        emoji: "🍎",
        color: Color(red: 0.7, green: 0.3, blue: 0.15),
        mapSearchTerms: ["cider", "cidery", "cider house", "hard cider", "nightlife", "liquor store", "wine spirits"],
        websiteKeywords: ["cider", "hard cider", "craft cider", "cidery",
                          "cider house", "cider on tap"],
        relatedKeywords: ["apple cider", "perry", "cider tasting"],
        addSpotPrompt: "Search for a cidery or cider bar."
    )

    // ══════════════════════════════════════════════════════════════
    // 🍰  SWEETS & SPECIALTY  (12 categories)
    // ══════════════════════════════════════════════════════════════

    static let flan = FoodCategory(
        id: "flan",
        displayName: "Flan",
        emoji: "🍮",
        color: .orange,
        mapSearchTerms: ["flan", "mexican bakery", "cuban restaurant"],
        websiteKeywords: ["flan", "flan casero"],
        relatedKeywords: ["custard", "caramel custard", "postre"],
        addSpotPrompt: "Search for a restaurant or bakery to add it as a flan spot."
    )

    static let artisanChocolate = FoodCategory(
        id: "artisan_chocolate",
        displayName: "Artisan Chocolate",
        emoji: "🍫",
        color: Color(red: 0.35, green: 0.18, blue: 0.08),
        mapSearchTerms: ["artisan chocolate", "chocolatier", "chocolate shop", "chocolate factory", "candy store"],
        websiteKeywords: ["artisan chocolate", "bean to bar", "craft chocolate",
                          "single origin chocolate", "chocolatier", "cacao"],
        relatedKeywords: ["chocolate", "truffles", "bonbon"],
        addSpotPrompt: "Search for a chocolatier or artisan chocolate shop."
    )

    static let khachapuri = FoodCategory(
        id: "khachapuri",
        displayName: "Khachapuri",
        emoji: "🧀",
        color: Color(red: 0.85, green: 0.65, blue: 0.25),
        mapSearchTerms: ["khachapuri", "georgian restaurant", "georgian food"],
        websiteKeywords: ["khachapuri", "adjaruli", "adjarian",
                          "cheese bread", "georgian bread"],
        relatedKeywords: ["georgian", "cheese boat"],
        addSpotPrompt: "Search for a Georgian restaurant that serves khachapuri."
    )

    static let baklava = FoodCategory(
        id: "baklava",
        displayName: "Baklava",
        emoji: "🍯",
        color: Color(red: 0.75, green: 0.55, blue: 0.1),
        mapSearchTerms: ["baklava", "turkish bakery", "middle eastern bakery"],
        websiteKeywords: ["baklava", "baklawa", "pistachio baklava",
                          "turkish sweets", "middle eastern sweets"],
        relatedKeywords: ["phyllo", "filo pastry", "turkish delight"],
        addSpotPrompt: "Search for a bakery or shop that makes baklava."
    )

    static let churros = FoodCategory(
        id: "churros",
        displayName: "Churros",
        emoji: "🍩",
        color: Color(red: 0.85, green: 0.55, blue: 0.1),
        mapSearchTerms: ["churros", "churreria", "mexican bakery", "spanish bakery"],
        websiteKeywords: ["churros", "churro", "churrería",
                          "churros con chocolate", "churro shop"],
        relatedKeywords: ["spanish pastry", "mexican pastry"],
        addSpotPrompt: "Search for a churro shop or bakery."
    )

    static let gelato = FoodCategory(
        id: "gelato",
        displayName: "Gelato",
        emoji: "🍨",
        color: Color(red: 0.4, green: 0.7, blue: 0.9),
        mapSearchTerms: ["gelato", "gelateria", "gelato shop", "italian ice cream", "ice cream shop"],
        websiteKeywords: ["gelato", "gelateria", "artigianale",
                          "italian gelato", "artisan gelato"],
        relatedKeywords: ["italian ice cream", "sorbetto"],
        addSpotPrompt: "Search for a gelateria or artisan gelato shop."
    )

    static let mochi = FoodCategory(
        id: "mochi",
        displayName: "Mochi",
        emoji: "🍡",
        color: Color(red: 0.9, green: 0.5, blue: 0.7),
        mapSearchTerms: ["mochi", "mochi shop", "japanese sweets", "japanese bakery"],
        websiteKeywords: ["mochi", "daifuku", "mochi ice cream",
                          "wagashi", "japanese sweets"],
        relatedKeywords: ["rice cake", "japanese dessert"],
        addSpotPrompt: "Search for a mochi shop or Japanese sweets cafe."
    )

    static let empanadas = FoodCategory(
        id: "empanadas",
        displayName: "Empanadas",
        emoji: "🥟",
        color: Color(red: 0.8, green: 0.5, blue: 0.1),
        mapSearchTerms: ["empanadas", "empanada shop", "argentine restaurant", "colombian restaurant"],
        websiteKeywords: ["empanadas", "empanada", "empanadas argentinas",
                          "empanada de carne", "empanadas caseras"],
        relatedKeywords: ["pastelitos", "hand pie"],
        addSpotPrompt: "Search for an empanada shop or Latin American restaurant."
    )

    static let crepes = FoodCategory(
        id: "crepes",
        displayName: "Crepes",
        emoji: "🥞",
        color: Color(red: 0.9, green: 0.75, blue: 0.4),
        mapSearchTerms: ["crepes", "creperie", "french cafe", "french bakery"],
        websiteKeywords: ["crepes", "crêpes", "creperie", "crêperie",
                          "sweet crepes", "savory crepes", "galettes"],
        relatedKeywords: ["french pastry", "buckwheat crepe"],
        addSpotPrompt: "Search for a creperie or cafe that serves crepes."
    )

    static let cremeBrulee = FoodCategory(
        id: "creme_brulee",
        displayName: "Crème Brûlée",
        emoji: "🍮",
        color: Color(red: 0.9, green: 0.75, blue: 0.3),
        mapSearchTerms: ["creme brulee", "french restaurant", "bistro", "fine dining"],
        websiteKeywords: ["crème brûlée", "creme brulee", "crema catalana",
                          "burnt cream"],
        relatedKeywords: ["french custard", "dessert menu"],
        addSpotPrompt: "Search for a restaurant that serves crème brûlée."
    )

    static let croissants = FoodCategory(
        id: "croissants",
        displayName: "Croissants",
        emoji: "🥐",
        color: Color(red: 0.85, green: 0.7, blue: 0.3),
        mapSearchTerms: ["croissants", "french bakery", "bakery", "patisserie"],
        websiteKeywords: ["croissant", "croissants", "viennoiserie",
                          "pain au chocolat", "butter croissant", "laminated dough"],
        relatedKeywords: ["french bakery", "pâtisserie", "pastry"],
        addSpotPrompt: "Search for a bakery known for its croissants."
    )

    static let tresLeches = FoodCategory(
        id: "tres_leches",
        displayName: "Tres Leches",
        emoji: "🍰",
        color: Color(red: 0.95, green: 0.85, blue: 0.65),
        mapSearchTerms: ["tres leches", "panaderia", "mexican bakery", "latin bakery", "mexican restaurant"],
        websiteKeywords: ["tres leches", "three milk cake", "pastel tres leches",
                          "tres leches cake"],
        relatedKeywords: ["pastel", "mexican cake", "latin dessert"],
        addSpotPrompt: "Search for a bakery or restaurant that serves tres leches."
    )

    // ══════════════════════════════════════════════════════════════
    // Legacy definitions — demoted from active, kept for Firestore
    // ══════════════════════════════════════════════════════════════
    // These are NOT in allCategories but ARE in allKnownCategories
    // so existing spots tagged with these IDs still decode.

    static let negroni = FoodCategory(
        id: "negroni", displayName: "Negroni", emoji: "🍹",
        color: Color(red: 0.7, green: 0.15, blue: 0.1),
        mapSearchTerms: ["negroni", "cocktail bar", "italian bar", "bar"],
        websiteKeywords: ["negroni", "sbagliato", "boulevardier",
                          "negroni menu", "negroni variations"],
        relatedKeywords: ["campari", "aperol", "italian cocktail"],
        addSpotPrompt: "Search for a bar known for its negroni."
    )
    static let bourbon = FoodCategory(
        id: "bourbon", displayName: "Bourbon", emoji: "🥃",
        color: Color(red: 0.72, green: 0.45, blue: 0.1),
        mapSearchTerms: ["bourbon", "whiskey bar", "bourbon bar", "liquor store", "wine spirits"],
        websiteKeywords: ["bourbon", "kentucky bourbon", "small batch bourbon",
                          "single barrel bourbon", "bourbon selection"],
        relatedKeywords: ["whiskey", "rye whiskey"],
        addSpotPrompt: "Search for a bar or restaurant with a bourbon selection."
    )
    static let singleMaltScotch = FoodCategory(
        id: "single_malt_scotch", displayName: "Single Malt Scotch", emoji: "🥃",
        color: Color(red: 0.55, green: 0.3, blue: 0.05),
        mapSearchTerms: ["scotch", "whisky bar", "whiskey bar", "liquor store", "wine spirits"],
        websiteKeywords: ["single malt", "scotch whisky", "single malt scotch",
                          "speyside", "islay", "highland scotch"],
        relatedKeywords: ["scotch", "whisky", "malt whisky"],
        addSpotPrompt: "Search for a bar with a single malt scotch selection."
    )
    static let fernetBranca = FoodCategory(
        id: "fernet_branca", displayName: "Fernet Branca", emoji: "🌿",
        color: Color(red: 0.1, green: 0.35, blue: 0.15),
        mapSearchTerms: ["fernet", "cocktail bar", "bar", "liquor store", "wine spirits"],
        websiteKeywords: ["fernet", "fernet branca", "fernet-branca", "amaro", "digestif"],
        relatedKeywords: ["amaro", "digestivo", "bitter"],
        addSpotPrompt: "Search for a bar that serves Fernet Branca."
    )
    static let peamealBacon = FoodCategory(
        id: "peameal_bacon", displayName: "Peameal Bacon", emoji: "🥓",
        color: Color(red: 0.7, green: 0.4, blue: 0.2),
        mapSearchTerms: ["peameal bacon", "canadian bacon", "breakfast restaurant"],
        websiteKeywords: ["peameal bacon", "peameal", "canadian bacon", "back bacon", "cornmeal bacon"],
        relatedKeywords: ["bacon sandwich", "breakfast sandwich"],
        addSpotPrompt: "Search for a restaurant or deli that serves peameal bacon."
    )
    static let mapleSyrup = FoodCategory(
        id: "maple_syrup", displayName: "Maple Syrup", emoji: "🍁",
        color: Color(red: 0.72, green: 0.4, blue: 0.08),
        mapSearchTerms: ["maple syrup", "sugar shack", "maple farm"],
        websiteKeywords: ["maple syrup", "pure maple", "maple sugar", "sugar shack", "cabane à sucre", "grade a maple"],
        relatedKeywords: ["maple", "sirop d'érable"],
        addSpotPrompt: "Search for a spot that serves or sells real maple syrup."
    )
    static let fugu = FoodCategory(
        id: "fugu", displayName: "Fugu", emoji: "🐡",
        color: Color(red: 0.15, green: 0.4, blue: 0.65),
        mapSearchTerms: ["fugu", "japanese restaurant", "pufferfish"],
        websiteKeywords: ["fugu", "pufferfish", "blowfish", "fugu sashimi", "tessa"],
        relatedKeywords: ["puffer fish", "torafugu"],
        addSpotPrompt: "Search for a Japanese restaurant that serves fugu."
    )
    static let pierogi = FoodCategory(
        id: "pierogi", displayName: "Pierogi", emoji: "🥟",
        color: Color(red: 0.8, green: 0.6, blue: 0.15),
        mapSearchTerms: ["pierogi", "polish restaurant", "polish food",
                         "ukrainian restaurant", "eastern european restaurant"],
        websiteKeywords: ["pierogi", "pierog", "pierogy", "pierogies", "polish dumplings",
                          "ruskie", "varenyky", "vareniki"],
        relatedKeywords: ["polish food", "ukrainian food", "dumplings"],
        addSpotPrompt: "Search for a restaurant that serves pierogi."
    )
    static let smashburgers = FoodCategory(
        id: "smashburgers", displayName: "Smashburgers", emoji: "🍔",
        color: Color(red: 0.8, green: 0.15, blue: 0.1),
        mapSearchTerms: ["smashburger", "burger restaurant", "burgers"],
        websiteKeywords: ["smashburger", "smash burger", "smashed burger", "smash patty", "crispy edges"],
        relatedKeywords: ["burger", "cheeseburger"],
        addSpotPrompt: "Search for a restaurant that serves smashburgers."
    )
    static let pizza = FoodCategory(
        id: "pizza", displayName: "Neapolitan Pizza", emoji: "🍕",
        color: Color(red: 0.8, green: 0.2, blue: 0.1),
        mapSearchTerms: ["pizza"], websiteKeywords: ["neapolitan"],
        addSpotPrompt: "Legacy category."
    )

    // MARK: - Full catalogue (50 Flezcals)
    //
    // Display order is the default; popularity sorting overrides at runtime.

    static let allCategories: [FoodCategory] = [
        // ── 🍽️ Food (24) ──
        tacos, birria, pozole, ceviche, mole, pupusas,
        ramen, sushi, omakase, dimSum, pho, bibimbap, koreanBBQ, dumplings, poke,
        tapas, paella, ibericoHam, woodFiredPizza,
        oysters, lobsterRolls, tartare, caviar, pierogi,
        // ── 🍹 Drinks (14) ──
        mezcal, whiskey, amaro, newEnglandIPA, craftBeer, naturalWine,
        sake, cocktails, specialtyCoffee, boba, tea, matcha, kombucha, cider,
        // ── 🍰 Sweets & Specialty (12) ──
        flan, artisanChocolate, khachapuri, baklava, churros, gelato,
        mochi, empanadas, crepes, cremeBrulee, croissants, tresLeches,
    ]

    /// All categories including legacy/demoted ones that may still exist in Firestore.
    /// Use `allCategories` for the picker grid; use this for decoding/lookup.
    static let allKnownCategories: [FoodCategory] = allCategories + [
        negroni, bourbon, singleMaltScotch, fernetBranca,
        peamealBacon, mapleSyrup, fugu, smashburgers, pizza,
    ]

    /// Common venue types offered as quick-add suggestions in EditSpotSearchView.
    static let commonVenueTypes: [String] = [
        "restaurant", "bar", "cafe", "bakery", "pizzeria", "diner", "bistro", "deli",
        "brewery", "winery", "taproom", "pub", "cocktail bar",
        "liquor store", "wine shop", "grocery store", "market", "butcher", "cheese shop",
        "taqueria", "trattoria", "brasserie", "izakaya", "cantina",
        "food hall", "food truck", "hotel", "fine dining", "steakhouse",
        "tea house", "tea room", "roastery",
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
        case "tea house":       return "cup.and.saucer.fill"
        case "tea room":        return "cup.and.saucer.fill"
        case "roastery":        return "mug.fill"
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
        let overrideService = SearchTermOverrideService.shared
        let builtIn = allCategories.map { cat in
            // User modifications take priority over admin overrides
            modifiedBuiltInPicks[cat.id] ?? overrideService.applyOverride(to: cat)
        }
        return builtIn + activeCustomPicks.map { overrideService.applyOverride(to: $0) }
    }

    /// Registers the user's picks so modified keywords are included in website scanning.
    /// Custom picks (custom_ prefix) are added alongside the built-in categories.
    /// Modified built-in picks override their static counterparts during scanning.
    @MainActor static func registerUserPicks(_ picks: [FoodCategory]) {
        activeCustomPicks = picks.filter { $0.id.hasPrefix("custom_") }
        activeCustomPicksSnapshot = activeCustomPicks
        modifiedBuiltInPicks = [:]
        for pick in picks where !pick.id.hasPrefix("custom_") {
            if let original = allCategories.first(where: { $0.id == pick.id }),
               original.websiteKeywords != pick.websiteKeywords {
                modifiedBuiltInPicks[pick.id] = pick
            }
        }
    }

    // MARK: - Default picks (used when user hasn't chosen yet)

    static let defaultPicks: [FoodCategory] = [mezcal, flan, tacos]

    // MARK: - Launch categories (locked, non-removable)

    /// The 3 categories locked for launch. Always active for every user.
    static let launchCategories: [FoodCategory] = [mezcal, flan, tacos]

    /// Whether a category is one of the locked launch defaults (Firestore-driven).
    @MainActor static func isLaunchCategory(_ category: FoodCategory) -> Bool {
        FeatureFlagService.shared.defaultCategories.contains(category.id)
    }

    // MARK: - Lookup helpers

    /// Thread-safe snapshot of custom picks for use in non-MainActor contexts
    /// (e.g. Codable decoding, background property access).
    /// Updated alongside activeCustomPicks in setActiveCustomPicks().
    nonisolated(unsafe) private(set) static var activeCustomPicksSnapshot: [FoodCategory] = []

    /// Returns the FoodCategory whose id matches the given string, or nil if not found.
    /// Checks allKnownCategories (including legacy ones) for backward compat,
    /// then falls back to activeCustomPicks for user-created categories.
    static func by(id: String) -> FoodCategory? {
        allKnownCategories.first { $0.id == id }
            ?? activeCustomPicksSnapshot.first { $0.id == id }
    }

    /// Convenience initializer from a SpotCategory.
    /// Since SpotCategory.rawValue == FoodCategory.id by design, this always succeeds
    /// for any SpotCategory case that was added alongside its FoodCategory counterpart.
    /// Also checks activeCustomPicks for user-created categories.
    init?(spotCategory: SpotCategory) {
        guard let match = FoodCategory.by(id: spotCategory.rawValue) else {
            return nil
        }
        self = match
    }
}
