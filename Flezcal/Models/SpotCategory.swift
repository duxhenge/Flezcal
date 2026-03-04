import Foundation
import SwiftUI

// ============================================================
// SpotCategory — the full set of confirmable food/drink types.
//
// Each case rawValue matches the corresponding FoodCategory.id
// so SpotCategory(rawValue: foodCategory.id) always succeeds.
//
// Backward-compatible: existing Firestore documents decode
// without any migration. Legacy cases (sushi, ramen, etc.)
// are kept but won't appear in the picker grid.
// ============================================================

enum SpotCategory: String, Codable, CaseIterable, Identifiable {

    // Launch trio (permanent)
    case mezcal
    case flan
    case tortillas

    // Drinks
    case bourbon
    case fernetBranca   = "fernet_branca"
    case newEnglandIPA  = "new_england_ipa"
    case singleMaltScotch = "single_malt_scotch"

    // Savory
    case peamealBacon   = "peameal_bacon"
    case woodFiredPizza = "wood_fired_pizza"
    case paella
    case oysters
    case pho
    case pozole
    case tartare
    case fugu
    case bibimbap
    case ibericoHam     = "iberico_ham"
    case caviar
    case pierogi
    case lobsterRolls   = "lobster_rolls"
    case smashburgers

    // Sweets & Specialty
    case mapleSyrup     = "maple_syrup"
    case artisanChocolate = "artisan_chocolate"

    // Legacy cases (kept for Firestore backward compat — not in picker grid)
    case naturalWine    = "natural_wine"
    case craftBeer      = "craft_beer"
    case sake
    case specialtyCoffee = "specialty_coffee"
    case boba
    case cocktails
    case mochi
    case churros
    case gelato
    case crepes
    case baklava
    case sushi
    case ramen
    case tacos
    case dimSum         = "dim_sum"
    case pizza
    case birria

    var id: String { rawValue }

    /// Whether this is a legacy category no longer shown in the picker grid.
    var isLegacy: Bool {
        switch self {
        case .naturalWine, .craftBeer, .sake, .specialtyCoffee, .boba, .cocktails,
             .mochi, .churros, .gelato, .crepes, .baklava, .sushi, .ramen,
             .tacos, .dimSum, .pizza, .birria:
            return true
        default:
            return false
        }
    }

    /// Name shown in the UI
    var displayName: String {
        switch self {
        // Launch trio
        case .mezcal:            return "Mezcal"
        case .flan:              return "Flan"
        case .tortillas:         return "Handmade Tortillas"
        // Drinks
        case .bourbon:           return "Bourbon"
        case .fernetBranca:      return "Fernet Branca"
        case .newEnglandIPA:     return "New England IPA"
        case .singleMaltScotch:  return "Single Malt Scotch"
        // Savory
        case .peamealBacon:      return "Peameal Bacon"
        case .woodFiredPizza:    return "Wood-Fired Pizza"
        case .paella:            return "Paella"
        case .oysters:           return "Oysters"
        case .pho:               return "Pho"
        case .pozole:            return "Pozole"
        case .tartare:           return "Tartare"
        case .fugu:              return "Fugu"
        case .bibimbap:          return "Bibimbap"
        case .ibericoHam:        return "Iberico Ham"
        case .caviar:            return "Caviar"
        case .pierogi:           return "Pierogi"
        case .lobsterRolls:      return "Lobster Rolls"
        case .smashburgers:      return "Smashburgers"
        // Sweets & Specialty
        case .mapleSyrup:        return "Maple Syrup"
        case .artisanChocolate:  return "Artisan Chocolate"
        // Legacy
        case .naturalWine:       return "Natural Wine"
        case .craftBeer:         return "Craft Beer"
        case .sake:              return "Sake"
        case .specialtyCoffee:   return "Specialty Coffee"
        case .boba:              return "Boba"
        case .cocktails:         return "Craft Cocktails"
        case .mochi:             return "Mochi"
        case .churros:           return "Churros"
        case .gelato:            return "Gelato"
        case .crepes:            return "Crepes"
        case .baklava:           return "Baklava"
        case .sushi:             return "Sushi"
        case .ramen:             return "Ramen"
        case .tacos:             return "Tacos"
        case .dimSum:            return "Dim Sum"
        case .pizza:             return "Neapolitan Pizza"
        case .birria:            return "Birria"
        }
    }

    /// Emoji shown on map pins, badges, and filter chips
    var emoji: String {
        switch self {
        // Launch trio
        case .mezcal:            return "🥃"
        case .flan:              return "🍮"
        case .tortillas:         return "🫓"
        // Drinks
        case .bourbon:           return "🥃"
        case .fernetBranca:      return "🌿"
        case .newEnglandIPA:     return "🍺"
        case .singleMaltScotch:  return "🥃"
        // Savory
        case .peamealBacon:      return "🥓"
        case .woodFiredPizza:    return "🍕"
        case .paella:            return "🥘"
        case .oysters:           return "🦪"
        case .pho:               return "🍲"
        case .pozole:            return "🍲"
        case .tartare:           return "🥩"
        case .fugu:              return "🐡"
        case .bibimbap:          return "🍚"
        case .ibericoHam:        return "🍖"
        case .caviar:            return "🫧"
        case .pierogi:           return "🥟"
        case .lobsterRolls:      return "🦞"
        case .smashburgers:      return "🍔"
        // Sweets & Specialty
        case .mapleSyrup:        return "🍁"
        case .artisanChocolate:  return "🍫"
        // Legacy
        case .naturalWine:       return "🍷"
        case .craftBeer:         return "🍺"
        case .sake:              return "🍶"
        case .specialtyCoffee:   return "☕"
        case .boba:              return "🧋"
        case .cocktails:         return "🍸"
        case .mochi:             return "🍡"
        case .churros:           return "🍩"
        case .gelato:            return "🍨"
        case .crepes:            return "🥞"
        case .baklava:           return "🍯"
        case .sushi:             return "🍣"
        case .ramen:             return "🍜"
        case .tacos:             return "🌮"
        case .dimSum:            return "🥟"
        case .pizza:             return "🍕"
        case .birria:            return "🫕"
        }
    }

    /// SF Symbol used where an emoji can't be used (e.g. Picker, map Marker)
    var icon: String {
        switch self {
        // Drinks get drink icons
        case .mezcal, .bourbon, .fernetBranca, .singleMaltScotch:
            return "cup.and.saucer"
        case .newEnglandIPA:
            return "mug"
        // Legacy drinks
        case .naturalWine, .sake, .cocktails:
            return "wineglass"
        case .craftBeer:
            return "mug"
        case .specialtyCoffee:
            return "cup.and.saucer.fill"
        case .boba:
            return "takeoutbag.and.cup.and.straw"
        // Everything else
        default:
            return "fork.knife"
        }
    }

    /// Accent color for badges, filter chips, and map pins
    var color: Color {
        switch self {
        // Launch trio
        case .mezcal:            return .green
        case .flan:              return .orange
        case .tortillas:         return Color(red: 0.85, green: 0.65, blue: 0.2)
        // Drinks
        case .bourbon:           return Color(red: 0.72, green: 0.45, blue: 0.1)
        case .fernetBranca:      return Color(red: 0.1, green: 0.35, blue: 0.15)
        case .newEnglandIPA:     return Color(red: 0.85, green: 0.65, blue: 0.15)
        case .singleMaltScotch:  return Color(red: 0.55, green: 0.3, blue: 0.05)
        // Savory
        case .peamealBacon:      return Color(red: 0.7, green: 0.4, blue: 0.2)
        case .woodFiredPizza:    return Color(red: 0.8, green: 0.2, blue: 0.1)
        case .paella:            return Color(red: 0.9, green: 0.7, blue: 0.1)
        case .oysters:           return Color(red: 0.2, green: 0.45, blue: 0.5)
        case .pho:               return Color(red: 0.6, green: 0.35, blue: 0.1)
        case .pozole:            return Color(red: 0.7, green: 0.2, blue: 0.15)
        case .tartare:           return Color(red: 0.6, green: 0.1, blue: 0.1)
        case .fugu:              return Color(red: 0.15, green: 0.4, blue: 0.65)
        case .bibimbap:          return Color(red: 0.8, green: 0.25, blue: 0.15)
        case .ibericoHam:        return Color(red: 0.65, green: 0.15, blue: 0.25)
        case .caviar:            return Color(red: 0.15, green: 0.2, blue: 0.3)
        case .pierogi:           return Color(red: 0.8, green: 0.6, blue: 0.15)
        case .lobsterRolls:      return Color(red: 0.85, green: 0.3, blue: 0.2)
        case .smashburgers:      return Color(red: 0.8, green: 0.15, blue: 0.1)
        // Sweets & Specialty
        case .mapleSyrup:        return Color(red: 0.72, green: 0.4, blue: 0.08)
        case .artisanChocolate:  return Color(red: 0.35, green: 0.18, blue: 0.08)
        // Legacy
        case .naturalWine:       return Color(red: 0.6, green: 0.1, blue: 0.3)
        case .craftBeer:         return Color(red: 0.8, green: 0.5, blue: 0.1)
        case .sake:              return Color(red: 0.2, green: 0.5, blue: 0.7)
        case .specialtyCoffee:   return Color(red: 0.4, green: 0.25, blue: 0.1)
        case .boba:              return Color(red: 0.7, green: 0.45, blue: 0.2)
        case .cocktails:         return Color(red: 0.2, green: 0.3, blue: 0.7)
        case .mochi:             return Color(red: 0.9, green: 0.5, blue: 0.7)
        case .churros:           return Color(red: 0.85, green: 0.55, blue: 0.1)
        case .gelato:            return Color(red: 0.4, green: 0.7, blue: 0.9)
        case .crepes:            return Color(red: 0.9, green: 0.75, blue: 0.4)
        case .baklava:           return Color(red: 0.75, green: 0.55, blue: 0.1)
        case .sushi:             return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .ramen:             return Color(red: 0.85, green: 0.2, blue: 0.1)
        case .tacos:             return Color(red: 0.95, green: 0.6, blue: 0.0)
        case .dimSum:            return Color(red: 0.8, green: 0.15, blue: 0.15)
        case .pizza:             return Color(red: 0.8, green: 0.2, blue: 0.1)
        case .birria:            return Color(red: 0.7, green: 0.1, blue: 0.0)
        }
    }

    /// Keywords scanned on a venue's homepage (mirrors FoodCategory.websiteKeywords)
    var websiteKeywords: [String] {
        switch self {
        // Launch trio
        case .mezcal:
            return ["mezcal", "mezcalería", "agave", "mezcales", "mezcal list", "mezcal menu", "mezcal selection"]
        case .flan:
            return ["flan", "flan casero", "postre", "custard", "caramel custard"]
        case .tortillas:
            return ["handmade tortillas", "tortillas hechas a mano", "fresh tortillas",
                    "tortilleria", "house-made tortillas", "corn tortillas", "flour tortillas"]
        // Drinks
        case .bourbon:
            return ["bourbon", "kentucky bourbon", "small batch bourbon", "single barrel bourbon", "bourbon selection"]
        case .fernetBranca:
            return ["fernet", "fernet branca", "fernet-branca", "amaro", "digestif"]
        case .newEnglandIPA:
            return ["new england ipa", "neipa", "hazy ipa", "juicy ipa", "hazy pale ale"]
        case .singleMaltScotch:
            return ["single malt", "scotch whisky", "single malt scotch", "speyside", "islay", "highland scotch"]
        // Savory
        case .peamealBacon:
            return ["peameal bacon", "peameal", "canadian bacon", "back bacon", "cornmeal bacon"]
        case .woodFiredPizza:
            return ["wood fired", "wood-fired", "wood oven", "brick oven", "neapolitan", "napoletana", "pizza napoletana"]
        case .paella:
            return ["paella", "paella valenciana", "paella mixta", "arroz", "bomba rice"]
        case .oysters:
            return ["oysters", "oyster bar", "fresh oysters", "raw bar", "oyster selection", "shucked"]
        case .pho:
            return ["pho", "phở", "vietnamese noodle", "beef noodle soup", "pho menu"]
        case .pozole:
            return ["pozole", "pozole rojo", "pozole verde", "pozole blanco", "pozolería"]
        case .tartare:
            return ["tartare", "steak tartare", "beef tartare", "tuna tartare", "salmon tartare"]
        case .fugu:
            return ["fugu", "pufferfish", "blowfish", "fugu sashimi", "tessa"]
        case .bibimbap:
            return ["bibimbap", "dolsot bibimbap", "stone pot bibimbap", "mixed rice bowl"]
        case .ibericoHam:
            return ["iberico", "ibérico", "jamón ibérico", "jamon iberico", "pata negra", "bellota"]
        case .caviar:
            return ["caviar", "osetra", "beluga caviar", "sturgeon caviar", "caviar service"]
        case .pierogi:
            return ["pierogi", "pierog", "pierogy", "pierogies", "polish dumplings", "ruskie"]
        case .lobsterRolls:
            return ["lobster roll", "lobster rolls", "lobster sandwich", "maine lobster roll", "connecticut lobster roll"]
        case .smashburgers:
            return ["smashburger", "smash burger", "smashed burger", "smash patty", "crispy edges"]
        // Sweets & Specialty
        case .mapleSyrup:
            return ["maple syrup", "pure maple", "maple sugar", "sugar shack", "cabane à sucre", "grade a maple"]
        case .artisanChocolate:
            return ["artisan chocolate", "bean to bar", "craft chocolate", "single origin chocolate", "chocolatier", "cacao"]
        // Legacy
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
        }
    }

    /// Prompt shown on the Add Spot screen
    var addSpotPrompt: String {
        switch self {
        // Launch trio
        case .mezcal:            return "Search for a bar, restaurant, or store to add it as a mezcal spot."
        case .flan:              return "Search for a restaurant or bakery to add it as a flan spot."
        case .tortillas:         return "Search for a restaurant or tortilleria that makes handmade tortillas."
        // Drinks
        case .bourbon:           return "Search for a bar or restaurant with a bourbon selection."
        case .fernetBranca:      return "Search for a bar that serves Fernet Branca."
        case .newEnglandIPA:     return "Search for a brewery or taproom with New England IPAs."
        case .singleMaltScotch:  return "Search for a bar with a single malt scotch selection."
        // Savory
        case .peamealBacon:      return "Search for a restaurant or deli that serves peameal bacon."
        case .woodFiredPizza:    return "Search for a wood-fired pizzeria."
        case .paella:            return "Search for a restaurant that serves paella."
        case .oysters:           return "Search for an oyster bar or raw bar restaurant."
        case .pho:               return "Search for a pho or Vietnamese noodle restaurant."
        case .pozole:            return "Search for a restaurant that serves pozole."
        case .tartare:           return "Search for a restaurant that serves tartare."
        case .fugu:              return "Search for a Japanese restaurant that serves fugu."
        case .bibimbap:          return "Search for a Korean restaurant that serves bibimbap."
        case .ibericoHam:        return "Search for a restaurant or shop that serves Iberico ham."
        case .caviar:            return "Search for a restaurant with a caviar service."
        case .pierogi:           return "Search for a restaurant that serves pierogi."
        case .lobsterRolls:      return "Search for a seafood spot that serves lobster rolls."
        case .smashburgers:      return "Search for a restaurant that serves smashburgers."
        // Sweets & Specialty
        case .mapleSyrup:        return "Search for a spot that serves or sells real maple syrup."
        case .artisanChocolate:  return "Search for a chocolatier or artisan chocolate shop."
        // Legacy
        case .naturalWine:       return "Search for a wine bar or shop that carries natural wines."
        case .craftBeer:         return "Search for a brewery, taproom, or craft beer bar."
        case .sake:              return "Search for a sake bar or Japanese restaurant with a sake program."
        case .specialtyCoffee:   return "Search for a specialty coffee shop or roastery."
        case .boba:              return "Search for a boba or bubble tea shop."
        case .cocktails:         return "Search for a craft cocktail bar."
        case .mochi:             return "Search for a mochi shop or Japanese sweets cafe."
        case .churros:           return "Search for a churro shop or Mexican bakery."
        case .gelato:            return "Search for a gelateria or artisan ice cream shop."
        case .crepes:            return "Search for a creperie or cafe that serves crepes."
        case .baklava:           return "Search for a bakery or shop that makes baklava."
        case .sushi:             return "Search for a sushi bar or Japanese restaurant."
        case .ramen:             return "Search for a ramen restaurant."
        case .tacos:             return "Search for a taqueria or taco spot."
        case .dimSum:            return "Search for a dim sum restaurant."
        case .pizza:             return "Search for a Neapolitan or wood-fired pizzeria."
        case .birria:            return "Search for a birria restaurant or truck."
        }
    }

    /// All categories now support user-contributed offerings (brands, styles, types).
    var supportsOfferings: Bool { true }

    /// Label for the offerings section header
    var offeringsLabel: String {
        switch self {
        // Launch trio
        case .mezcal:            return "Mezcal Brands"
        case .flan:              return "Flan Styles"
        case .tortillas:         return "Tortilla Types"
        // Drinks
        case .bourbon:           return "Bourbon Brands"
        case .fernetBranca:      return "Serving Styles"
        case .newEnglandIPA:     return "Beer Brands"
        case .singleMaltScotch:  return "Scotch Brands"
        // Savory
        case .peamealBacon:      return "Serving Styles"
        case .woodFiredPizza:    return "Pizza Styles"
        case .paella:            return "Paella Types"
        case .oysters:           return "Oyster Varieties"
        case .pho:               return "Pho Types"
        case .pozole:            return "Pozole Styles"
        case .tartare:           return "Tartare Types"
        case .fugu:              return "Fugu Preparations"
        case .bibimbap:          return "Bibimbap Types"
        case .ibericoHam:        return "Ham Grades"
        case .caviar:            return "Caviar Types"
        case .pierogi:           return "Pierogi Fillings"
        case .lobsterRolls:      return "Roll Styles"
        case .smashburgers:      return "Burger Styles"
        // Sweets & Specialty
        case .mapleSyrup:        return "Syrup Grades"
        case .artisanChocolate:  return "Chocolate Types"
        // Legacy
        case .naturalWine:       return "Wine Styles"
        case .craftBeer:         return "Beer Styles"
        case .sake:              return "Sake Types"
        case .specialtyCoffee:   return "Coffee Methods"
        case .boba:              return "Drink Flavors"
        case .cocktails:         return "Cocktail Styles"
        case .mochi:             return "Mochi Types"
        case .churros:           return "Churro Varieties"
        case .gelato:            return "Gelato Flavors"
        case .crepes:            return "Crepe Varieties"
        case .baklava:           return "Baklava Types"
        case .sushi:             return "Sushi Highlights"
        case .ramen:             return "Ramen Styles"
        case .tacos:             return "Taco Types"
        case .dimSum:            return "Dim Sum Dishes"
        case .pizza:             return "Pizza Styles"
        case .birria:            return "Birria Styles"
        }
    }

    /// Singular label for an offering entry (e.g. "brand", "style", "flavor")
    var offeringSingular: String {
        switch self {
        // Launch trio
        case .mezcal:            return "brand"
        case .flan:              return "style"
        case .tortillas:         return "type"
        // Drinks
        case .bourbon:           return "brand"
        case .fernetBranca:      return "style"
        case .newEnglandIPA:     return "brand"
        case .singleMaltScotch:  return "brand"
        // Savory
        case .peamealBacon:      return "style"
        case .woodFiredPizza:    return "style"
        case .paella:            return "type"
        case .oysters:           return "variety"
        case .pho:               return "type"
        case .pozole:            return "style"
        case .tartare:           return "type"
        case .fugu:              return "preparation"
        case .bibimbap:          return "type"
        case .ibericoHam:        return "grade"
        case .caviar:            return "type"
        case .pierogi:           return "filling"
        case .lobsterRolls:      return "style"
        case .smashburgers:      return "style"
        // Sweets & Specialty
        case .mapleSyrup:        return "grade"
        case .artisanChocolate:  return "type"
        // Legacy
        case .naturalWine:       return "style"
        case .craftBeer:         return "style"
        case .sake:              return "type"
        case .specialtyCoffee:   return "method"
        case .boba:              return "flavor"
        case .cocktails:         return "style"
        case .mochi:             return "type"
        case .churros:           return "variety"
        case .gelato:            return "flavor"
        case .crepes:            return "variety"
        case .baklava:           return "type"
        case .sushi:             return "highlight"
        case .ramen:             return "style"
        case .tacos:             return "type"
        case .dimSum:            return "dish"
        case .pizza:             return "style"
        case .birria:            return "style"
        }
    }

    /// Example offerings shown as placeholder hints
    var offeringsExamples: String {
        switch self {
        // Launch trio
        case .mezcal:            return "e.g. Del Maguey, Vago, Bozal"
        case .flan:              return "e.g. Classic, Coconut, Cheese Flan"
        case .tortillas:         return "e.g. Corn, Flour, Blue Corn, Handmade"
        // Drinks
        case .bourbon:           return "e.g. Maker's Mark, Woodford Reserve, Buffalo Trace"
        case .fernetBranca:      return "e.g. Neat, with Cola, Cocktail"
        case .newEnglandIPA:     return "e.g. Trillium, Tree House, Other Half"
        case .singleMaltScotch:  return "e.g. Lagavulin, Macallan, Glenfiddich"
        // Savory
        case .peamealBacon:      return "e.g. Classic Sandwich, Eggs Benedict, Platter"
        case .woodFiredPizza:    return "e.g. Margherita, Marinara, Diavola"
        case .paella:            return "e.g. Valenciana, Mixta, Mariscos"
        case .oysters:           return "e.g. Wellfleet, Kumamoto, Blue Point"
        case .pho:               return "e.g. Tai (Rare Beef), Dac Biet (Special)"
        case .pozole:            return "e.g. Rojo, Verde, Blanco"
        case .tartare:           return "e.g. Steak, Tuna, Salmon"
        case .fugu:              return "e.g. Sashimi (Tessa), Hot Pot (Tecchiri)"
        case .bibimbap:          return "e.g. Dolsot (Stone Pot), Vegetable, Beef"
        case .ibericoHam:        return "e.g. Bellota, Cebo, Reserva"
        case .caviar:            return "e.g. Osetra, Beluga, Paddlefish"
        case .pierogi:           return "e.g. Potato & Cheese, Sauerkraut, Meat"
        case .lobsterRolls:      return "e.g. Maine Style, Connecticut Style"
        case .smashburgers:      return "e.g. Single, Double, Cheese, Special Sauce"
        // Sweets & Specialty
        case .mapleSyrup:        return "e.g. Grade A Amber, Dark Robust, Maple Candy"
        case .artisanChocolate:  return "e.g. Single Origin Bar, Truffles, Bonbons"
        // Legacy
        case .naturalWine:       return "e.g. Pet-Nat, Orange, Skin Contact"
        case .craftBeer:         return "e.g. Hazy IPA, Stout, Sour"
        case .sake:              return "e.g. Junmai, Daiginjo, Nigori"
        case .specialtyCoffee:   return "e.g. Pour Over, Espresso, Cold Brew"
        case .boba:              return "e.g. Taro, Brown Sugar, Matcha"
        case .cocktails:         return "e.g. Negroni, Old Fashioned, Mezcal Mule"
        case .mochi:             return "e.g. Daifuku, Ice Cream, Strawberry"
        case .churros:           return "e.g. Classic, Filled, Chocolate Dipped"
        case .gelato:            return "e.g. Pistachio, Stracciatella, Hazelnut"
        case .crepes:            return "e.g. Nutella, Savory Ham & Cheese"
        case .baklava:           return "e.g. Pistachio, Walnut, Bird's Nest"
        case .sushi:             return "e.g. Omakase, Chirashi, Salmon Nigiri"
        case .ramen:             return "e.g. Tonkotsu, Shoyu, Miso, Tsukemen"
        case .tacos:             return "e.g. Al Pastor, Carnitas, Suadero"
        case .dimSum:            return "e.g. Har Gow, Siu Mai, Char Siu Bao"
        case .pizza:             return "e.g. Margherita, Marinara, Diavola"
        case .birria:            return "e.g. Tacos, Consomme, Quesabirria"
        }
    }
}
