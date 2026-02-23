import Foundation
import SwiftUI

// ============================================================
// SpotCategory — the full set of confirmable food/drink types.
//
// Each case rawValue matches the corresponding FoodCategory.id
// so SpotCategory(rawValue: foodCategory.id) always succeeds.
//
// Backward-compatible: existing "flan" and "mezcal" Firestore
// documents decode without any migration.
// ============================================================

enum SpotCategory: String, Codable, CaseIterable, Identifiable {

    // Drinks
    case mezcal
    case naturalWine  = "natural_wine"
    case craftBeer    = "craft_beer"
    case sake
    case specialtyCoffee = "specialty_coffee"
    case boba
    case cocktails

    // Desserts & Sweets
    case flan
    case mochi
    case churros
    case gelato
    case crepes
    case baklava

    // Savory
    case sushi
    case ramen
    case tacos
    case dimSum       = "dim_sum"
    case pizza
    case birria
    case oysters
    case pho

    var id: String { rawValue }

    /// Name shown in the UI
    var displayName: String {
        switch self {
        case .mezcal:          return "Mezcal"
        case .naturalWine:     return "Natural Wine"
        case .craftBeer:       return "Craft Beer"
        case .sake:            return "Sake"
        case .specialtyCoffee: return "Specialty Coffee"
        case .boba:            return "Boba"
        case .cocktails:       return "Craft Cocktails"
        case .flan:            return "Flan"
        case .mochi:           return "Mochi"
        case .churros:         return "Churros"
        case .gelato:          return "Gelato"
        case .crepes:          return "Crepes"
        case .baklava:         return "Baklava"
        case .sushi:           return "Sushi"
        case .ramen:           return "Ramen"
        case .tacos:           return "Tacos"
        case .dimSum:          return "Dim Sum"
        case .pizza:           return "Neapolitan Pizza"
        case .birria:          return "Birria"
        case .oysters:         return "Oysters"
        case .pho:             return "Pho"
        }
    }

    /// Emoji shown on map pins, badges, and filter chips
    var emoji: String {
        switch self {
        case .mezcal:          return "🥃"
        case .naturalWine:     return "🍷"
        case .craftBeer:       return "🍺"
        case .sake:            return "🍶"
        case .specialtyCoffee: return "☕"
        case .boba:            return "🧋"
        case .cocktails:       return "🍸"
        case .flan:            return "🍮"
        case .mochi:           return "🍡"
        case .churros:         return "🍩"
        case .gelato:          return "🍨"
        case .crepes:          return "🥞"
        case .baklava:         return "🍯"
        case .sushi:           return "🍣"
        case .ramen:           return "🍜"
        case .tacos:           return "🌮"
        case .dimSum:          return "🥟"
        case .pizza:           return "🍕"
        case .birria:          return "🫕"
        case .oysters:         return "🦪"
        case .pho:             return "🍲"
        }
    }

    /// SF Symbol used where an emoji can't be used (e.g. Picker, map Marker)
    var icon: String {
        switch self {
        case .mezcal:          return "cup.and.saucer"
        case .naturalWine:     return "wineglass"
        case .craftBeer:       return "mug"
        case .sake:            return "wineglass.fill"
        case .specialtyCoffee: return "cup.and.saucer.fill"
        case .boba:            return "takeoutbag.and.cup.and.straw"
        case .cocktails:       return "wineglass"
        case .flan:            return "fork.knife"
        case .mochi:           return "fork.knife"
        case .churros:         return "fork.knife"
        case .gelato:          return "fork.knife"
        case .crepes:          return "fork.knife"
        case .baklava:         return "fork.knife"
        case .sushi:           return "fork.knife"
        case .ramen:           return "fork.knife"
        case .tacos:           return "fork.knife"
        case .dimSum:          return "fork.knife"
        case .pizza:           return "fork.knife"
        case .birria:          return "fork.knife"
        case .oysters:         return "fork.knife"
        case .pho:             return "fork.knife"
        }
    }

    /// Accent color for badges, filter chips, and map pins
    var color: Color {
        switch self {
        case .mezcal:          return .green
        case .naturalWine:     return Color(red: 0.6, green: 0.1, blue: 0.3)
        case .craftBeer:       return Color(red: 0.8, green: 0.5, blue: 0.1)
        case .sake:            return Color(red: 0.2, green: 0.5, blue: 0.7)
        case .specialtyCoffee: return Color(red: 0.4, green: 0.25, blue: 0.1)
        case .boba:            return Color(red: 0.7, green: 0.45, blue: 0.2)
        case .cocktails:       return Color(red: 0.2, green: 0.3, blue: 0.7)
        case .flan:            return .orange
        case .mochi:           return Color(red: 0.9, green: 0.5, blue: 0.7)
        case .churros:         return Color(red: 0.85, green: 0.55, blue: 0.1)
        case .gelato:          return Color(red: 0.4, green: 0.7, blue: 0.9)
        case .crepes:          return Color(red: 0.9, green: 0.75, blue: 0.4)
        case .baklava:         return Color(red: 0.75, green: 0.55, blue: 0.1)
        case .sushi:           return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .ramen:           return Color(red: 0.85, green: 0.2, blue: 0.1)
        case .tacos:           return Color(red: 0.95, green: 0.6, blue: 0.0)
        case .dimSum:          return Color(red: 0.8, green: 0.15, blue: 0.15)
        case .pizza:           return Color(red: 0.8, green: 0.2, blue: 0.1)
        case .birria:          return Color(red: 0.7, green: 0.1, blue: 0.0)
        case .oysters:         return Color(red: 0.2, green: 0.45, blue: 0.5)
        case .pho:             return Color(red: 0.6, green: 0.35, blue: 0.1)
        }
    }

    /// Keywords scanned on a venue's homepage (mirrors FoodCategory.websiteKeywords)
    var websiteKeywords: [String] {
        switch self {
        case .mezcal:
            return ["mezcal", "mezcalería", "agave", "mezcales", "mezcal list", "mezcal menu", "mezcal selection"]
        case .naturalWine:
            return ["natural wine", "natty wine", "orange wine", "biodynamic wine", "skin contact"]
        case .craftBeer:
            return ["craft beer", "microbrewery", "taproom", "IPA", "craft ale", "local brew"]
        case .sake:
            return ["sake", "nihonshu", "junmai", "sake selection", "sake list", "sake bar"]
        case .specialtyCoffee:
            return ["specialty coffee", "single origin", "pour over", "espresso", "third wave", "direct trade"]
        case .boba:
            return ["boba", "bubble tea", "tapioca", "milk tea", "taro", "boba shop"]
        case .cocktails:
            return ["craft cocktail", "mixology", "artisan cocktail", "cocktail menu", "signature cocktail"]
        case .flan:
            return ["flan", "flan casero", "postre", "custard", "caramel custard"]
        case .mochi:
            return ["mochi", "daifuku", "mochi ice cream", "wagashi", "japanese sweets"]
        case .churros:
            return ["churros", "churro", "churrería", "churros con chocolate"]
        case .gelato:
            return ["gelato", "gelateria", "artigianale", "italian gelato", "artisan gelato"]
        case .crepes:
            return ["crepes", "crêpes", "creperie", "crêperie", "sweet crepes", "savory crepes"]
        case .baklava:
            return ["baklava", "baklawa", "turkish sweets", "pistachio baklava", "pastry", "middle eastern sweets"]
        case .sushi:
            return ["sushi", "omakase", "nigiri", "sashimi", "sushi bar", "maki", "sushi roll"]
        case .ramen:
            return ["ramen", "tonkotsu", "shoyu ramen", "miso ramen", "ramen shop", "noodle soup"]
        case .tacos:
            return ["tacos", "taqueria", "al pastor", "birria tacos", "taco", "mexican street food"]
        case .dimSum:
            return ["dim sum", "yum cha", "har gow", "siu mai", "dumplings", "dim sum menu"]
        case .pizza:
            return ["neapolitan", "wood fired", "napoletana", "pizza napoletana", "00 flour", "fior di latte"]
        case .birria:
            return ["birria", "birrieria", "consomé", "birria tacos", "quesabirria"]
        case .oysters:
            return ["oysters", "oyster bar", "fresh oysters", "raw bar", "oyster selection", "shucked"]
        case .pho:
            return ["pho", "phở", "vietnamese noodle", "beef noodle soup", "pho menu"]
        }
    }

    /// Prompt shown on the Add Spot screen
    var addSpotPrompt: String {
        switch self {
        case .mezcal:          return "Search for a bar, restaurant, or store to add it as a mezcal spot."
        case .naturalWine:     return "Search for a wine bar or shop that carries natural wines."
        case .craftBeer:       return "Search for a brewery, taproom, or craft beer bar."
        case .sake:            return "Search for a sake bar or Japanese restaurant with a sake program."
        case .specialtyCoffee: return "Search for a specialty coffee shop or roastery."
        case .boba:            return "Search for a boba or bubble tea shop."
        case .cocktails:       return "Search for a craft cocktail bar."
        case .flan:            return "Search for a restaurant or bakery to add it as a flan spot."
        case .mochi:           return "Search for a mochi shop or Japanese sweets cafe."
        case .churros:         return "Search for a churro shop or Mexican bakery."
        case .gelato:          return "Search for a gelateria or artisan ice cream shop."
        case .crepes:          return "Search for a creperie or cafe that serves crepes."
        case .baklava:         return "Search for a bakery or shop that makes baklava."
        case .sushi:           return "Search for a sushi bar or Japanese restaurant."
        case .ramen:           return "Search for a ramen restaurant."
        case .tacos:           return "Search for a taqueria or taco spot."
        case .dimSum:          return "Search for a dim sum restaurant."
        case .pizza:           return "Search for a Neapolitan or wood-fired pizzeria."
        case .birria:          return "Search for a birria restaurant or truck."
        case .oysters:         return "Search for an oyster bar or raw bar restaurant."
        case .pho:             return "Search for a pho or Vietnamese noodle restaurant."
        }
    }

    /// All categories now support user-contributed offerings (brands, styles, types).
    var supportsOfferings: Bool { true }

    /// Label for the offerings section header
    var offeringsLabel: String {
        switch self {
        case .mezcal:          return "Mezcal Brands"
        case .naturalWine:     return "Wine Styles"
        case .craftBeer:       return "Beer Styles"
        case .sake:            return "Sake Types"
        case .specialtyCoffee: return "Coffee Methods"
        case .boba:            return "Drink Flavors"
        case .cocktails:       return "Cocktail Styles"
        case .flan:            return "Flan Styles"
        case .mochi:           return "Mochi Types"
        case .churros:         return "Churro Varieties"
        case .gelato:          return "Gelato Flavors"
        case .crepes:          return "Crepe Varieties"
        case .baklava:         return "Baklava Types"
        case .sushi:           return "Sushi Highlights"
        case .ramen:           return "Ramen Styles"
        case .tacos:           return "Taco Types"
        case .dimSum:          return "Dim Sum Dishes"
        case .pizza:           return "Pizza Styles"
        case .birria:          return "Birria Styles"
        case .oysters:         return "Oyster Varieties"
        case .pho:             return "Pho Types"
        }
    }

    /// Singular label for an offering entry (e.g. "brand", "style", "flavor")
    var offeringSingular: String {
        switch self {
        case .mezcal:          return "brand"
        case .naturalWine:     return "style"
        case .craftBeer:       return "style"
        case .sake:            return "type"
        case .specialtyCoffee: return "method"
        case .boba:            return "flavor"
        case .cocktails:       return "style"
        case .flan:            return "style"
        case .mochi:           return "type"
        case .churros:         return "variety"
        case .gelato:          return "flavor"
        case .crepes:          return "variety"
        case .baklava:         return "type"
        case .sushi:           return "highlight"
        case .ramen:           return "style"
        case .tacos:           return "type"
        case .dimSum:          return "dish"
        case .pizza:           return "style"
        case .birria:          return "style"
        case .oysters:         return "variety"
        case .pho:             return "type"
        }
    }

    /// Example offerings shown as placeholder hints
    var offeringsExamples: String {
        switch self {
        case .mezcal:          return "e.g. Del Maguey, Vago, Bozal"
        case .naturalWine:     return "e.g. Pet-Nat, Orange, Skin Contact"
        case .craftBeer:       return "e.g. Hazy IPA, Stout, Sour"
        case .sake:            return "e.g. Junmai, Daiginjo, Nigori"
        case .specialtyCoffee: return "e.g. Pour Over, Espresso, Cold Brew"
        case .boba:            return "e.g. Taro, Brown Sugar, Matcha"
        case .cocktails:       return "e.g. Negroni, Old Fashioned, Mezcal Mule"
        case .flan:            return "e.g. Classic, Coconut, Cheese Flan"
        case .mochi:           return "e.g. Daifuku, Ice Cream, Strawberry"
        case .churros:         return "e.g. Classic, Filled, Chocolate Dipped"
        case .gelato:          return "e.g. Pistachio, Stracciatella, Hazelnut"
        case .crepes:          return "e.g. Nutella, Savory Ham & Cheese"
        case .baklava:         return "e.g. Pistachio, Walnut, Bird's Nest"
        case .sushi:           return "e.g. Omakase, Chirashi, Salmon Nigiri"
        case .ramen:           return "e.g. Tonkotsu, Shoyu, Miso, Tsukemen"
        case .tacos:           return "e.g. Al Pastor, Carnitas, Suadero"
        case .dimSum:          return "e.g. Har Gow, Siu Mai, Char Siu Bao"
        case .pizza:           return "e.g. Margherita, Marinara, Diavola"
        case .birria:          return "e.g. Tacos, Consomme, Quesabirria"
        case .oysters:         return "e.g. Wellfleet, Kumamoto, Blue Point"
        case .pho:             return "e.g. Tai (Rare Beef), Dac Biet (Special)"
        }
    }
}
