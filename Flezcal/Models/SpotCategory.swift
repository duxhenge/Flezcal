import Foundation
import SwiftUI

// ============================================================
// SpotCategory — the full set of confirmable food/drink types.
//
// Built-in cases have rawValue == FoodCategory.id.
// Custom Flezcals use `.custom("custom_pupusas")` — they behave
// identically to built-ins, pulling display metadata from the
// registered FoodCategory at runtime.
//
// Backward-compatible: existing Firestore documents decode
// without any migration. Unknown category strings decode as
// `.custom(id)` instead of being silently dropped.
// ============================================================

enum SpotCategory: Hashable, Identifiable {

    // ── 🍽️ FOOD ──────────────────────────────────────────────

    // Launch trio
    case mezcal
    case flan
    case tortillas

    // Latin / Mexican
    case tacos
    case birria
    case pozole
    case ceviche
    case mole
    case pupusas

    // Asian
    case ramen
    case sushi
    case omakase
    case dimSum
    case pho
    case bibimbap
    case koreanBBQ
    case dumplings
    case poke

    // European / Mediterranean
    case tapas
    case paella
    case ibericoHam
    case woodFiredPizza

    // Seafood / Raw
    case oysters
    case lobsterRolls
    case tartare
    case caviar

    // ── 🍹 DRINKS ─────────────────────────────────────────────

    case whiskey
    case amaro
    case newEnglandIPA
    case craftBeer
    case naturalWine
    case sake
    case cocktails
    case specialtyCoffee
    case boba
    case tea
    case matcha
    case kombucha
    case cider

    // ── 🍰 SWEETS & SPECIALTY ─────────────────────────────────

    case artisanChocolate
    case khachapuri
    case baklava
    case churros
    case gelato
    case mochi
    case empanadas
    case crepes
    case cremeBrulee
    case croissants
    case tresLeches

    // ── Legacy (demoted — kept for Firestore backward compat) ─

    case negroni
    case bourbon
    case singleMaltScotch
    case fernetBranca
    case peamealBacon
    case mapleSyrup
    case fugu
    case pierogi
    case smashburgers
    case pizza

    // ── Custom Flezcals (user-created, same capabilities) ─────

    /// A user-created category. The associated string is the category ID
    /// (e.g. "custom_pupusas"). Display metadata is looked up from
    /// the registered FoodCategory at runtime.
    case custom(String)

    // MARK: - ID & Raw Value

    /// Stable string identifier. Matches FoodCategory.id and is used as
    /// the Firestore key in categories, categoryRatings, offerings, etc.
    var id: String { rawValue }

    /// String representation for Firestore storage and Codable encoding.
    var rawValue: String {
        switch self {
        case .mezcal:            return "mezcal"
        case .flan:              return "flan"
        case .tortillas:         return "tortillas"
        case .tacos:             return "tacos"
        case .birria:            return "birria"
        case .pozole:            return "pozole"
        case .ceviche:           return "ceviche"
        case .mole:              return "mole"
        case .pupusas:           return "pupusas"
        case .ramen:             return "ramen"
        case .sushi:             return "sushi"
        case .omakase:           return "omakase"
        case .dimSum:            return "dim_sum"
        case .pho:               return "pho"
        case .bibimbap:          return "bibimbap"
        case .koreanBBQ:         return "korean_bbq"
        case .dumplings:         return "dumplings"
        case .poke:              return "poke"
        case .tapas:             return "tapas"
        case .paella:            return "paella"
        case .ibericoHam:        return "iberico_ham"
        case .woodFiredPizza:    return "wood_fired_pizza"
        case .oysters:           return "oysters"
        case .lobsterRolls:      return "lobster_rolls"
        case .tartare:           return "tartare"
        case .caviar:            return "caviar"
        case .whiskey:           return "whiskey"
        case .amaro:             return "amaro"
        case .newEnglandIPA:     return "new_england_ipa"
        case .craftBeer:         return "craft_beer"
        case .naturalWine:       return "natural_wine"
        case .sake:              return "sake"
        case .cocktails:         return "cocktails"
        case .specialtyCoffee:   return "specialty_coffee"
        case .boba:              return "boba"
        case .tea:               return "tea"
        case .matcha:            return "matcha"
        case .kombucha:          return "kombucha"
        case .cider:             return "cider"
        case .artisanChocolate:  return "artisan_chocolate"
        case .khachapuri:        return "khachapuri"
        case .baklava:           return "baklava"
        case .churros:           return "churros"
        case .gelato:            return "gelato"
        case .mochi:             return "mochi"
        case .empanadas:         return "empanadas"
        case .crepes:            return "crepes"
        case .cremeBrulee:       return "creme_brulee"
        case .croissants:        return "croissants"
        case .tresLeches:        return "tres_leches"
        case .negroni:           return "negroni"
        case .bourbon:           return "bourbon"
        case .singleMaltScotch:  return "single_malt_scotch"
        case .fernetBranca:      return "fernet_branca"
        case .peamealBacon:      return "peameal_bacon"
        case .mapleSyrup:        return "maple_syrup"
        case .fugu:              return "fugu"
        case .pierogi:           return "pierogi"
        case .smashburgers:      return "smashburgers"
        case .pizza:             return "pizza"
        case .custom(let id):    return id
        }
    }

    /// Creates a SpotCategory from a raw string. Returns a built-in case
    /// if one matches, otherwise `.custom(id)` — never returns nil.
    init(rawValue: String) {
        switch rawValue {
        case "mezcal":            self = .mezcal
        case "flan":              self = .flan
        case "tortillas":        self = .tortillas
        case "tacos":            self = .tacos
        case "birria":           self = .birria
        case "pozole":           self = .pozole
        case "ceviche":          self = .ceviche
        case "mole":             self = .mole
        case "pupusas":          self = .pupusas
        case "ramen":            self = .ramen
        case "sushi":            self = .sushi
        case "omakase":          self = .omakase
        case "dim_sum":          self = .dimSum
        case "pho":              self = .pho
        case "bibimbap":         self = .bibimbap
        case "korean_bbq":       self = .koreanBBQ
        case "dumplings":        self = .dumplings
        case "poke":             self = .poke
        case "tapas":            self = .tapas
        case "paella":           self = .paella
        case "iberico_ham":      self = .ibericoHam
        case "wood_fired_pizza": self = .woodFiredPizza
        case "oysters":          self = .oysters
        case "lobster_rolls":    self = .lobsterRolls
        case "tartare":          self = .tartare
        case "caviar":           self = .caviar
        case "whiskey":          self = .whiskey
        case "amaro":            self = .amaro
        case "new_england_ipa":  self = .newEnglandIPA
        case "craft_beer":       self = .craftBeer
        case "natural_wine":     self = .naturalWine
        case "sake":             self = .sake
        case "cocktails":        self = .cocktails
        case "specialty_coffee": self = .specialtyCoffee
        case "boba":             self = .boba
        case "tea":              self = .tea
        case "matcha":           self = .matcha
        case "kombucha":         self = .kombucha
        case "cider":            self = .cider
        case "artisan_chocolate": self = .artisanChocolate
        case "khachapuri":       self = .khachapuri
        case "baklava":          self = .baklava
        case "churros":          self = .churros
        case "gelato":           self = .gelato
        case "mochi":            self = .mochi
        case "empanadas":        self = .empanadas
        case "crepes":           self = .crepes
        case "creme_brulee":     self = .cremeBrulee
        case "croissants":       self = .croissants
        case "tres_leches":      self = .tresLeches
        case "negroni":          self = .negroni
        case "bourbon":          self = .bourbon
        case "single_malt_scotch": self = .singleMaltScotch
        case "fernet_branca":    self = .fernetBranca
        case "peameal_bacon":    self = .peamealBacon
        case "maple_syrup":      self = .mapleSyrup
        case "fugu":             self = .fugu
        case "pierogi":          self = .pierogi
        case "smashburgers":     self = .smashburgers
        case "pizza":            self = .pizza
        default:                 self = .custom(rawValue)
        }
    }

    /// All built-in cases (excludes `.custom`). Replaces CaseIterable.
    static let allCases: [SpotCategory] = [
        // Food
        .mezcal, .flan, .tortillas,
        .tacos, .birria, .pozole, .ceviche, .mole, .pupusas,
        .ramen, .sushi, .omakase, .dimSum, .pho, .bibimbap, .koreanBBQ, .dumplings, .poke,
        .tapas, .paella, .ibericoHam, .woodFiredPizza,
        .oysters, .lobsterRolls, .tartare, .caviar,
        // Drinks
        .whiskey, .amaro, .newEnglandIPA, .craftBeer, .naturalWine,
        .sake, .cocktails, .specialtyCoffee, .boba, .tea, .matcha, .kombucha, .cider,
        // Sweets & Specialty
        .artisanChocolate, .khachapuri, .baklava, .churros, .gelato,
        .mochi, .empanadas, .crepes, .cremeBrulee, .croissants, .tresLeches,
        // Legacy
        .negroni, .bourbon, .singleMaltScotch, .fernetBranca,
        .peamealBacon, .mapleSyrup, .fugu, .pierogi, .smashburgers, .pizza,
    ]

    /// Whether this is a custom (user-created) category.
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// Whether this is a legacy category no longer shown in the picker grid.
    var isLegacy: Bool {
        switch self {
        case .negroni, .bourbon, .singleMaltScotch, .fernetBranca,
             .peamealBacon, .mapleSyrup, .fugu, .pierogi, .smashburgers, .pizza:
            return true
        default:
            return false
        }
    }

    // MARK: - FoodCategory Lookup (for custom categories)

    /// Looks up the FoodCategory for this SpotCategory.
    /// Built-in categories use FoodCategory.allKnownCategories.
    /// Custom categories use FoodCategory.activeCustomPicks.
    private var foodCategory: FoodCategory? {
        FoodCategory.by(id: rawValue)
            ?? FoodCategory.activeCustomPicks.first { $0.id == rawValue }
    }

    // MARK: - Display Properties

    /// Name shown in the UI
    var displayName: String {
        switch self {
        // ── Food ──
        case .mezcal:            return "Mezcal"
        case .flan:              return "Flan"
        case .tortillas:         return "Handmade Tortillas"
        case .tacos:             return "Tacos"
        case .birria:            return "Birria"
        case .pozole:            return "Pozole"
        case .ceviche:           return "Ceviche"
        case .mole:              return "Mole"
        case .pupusas:           return "Pupusas"
        case .ramen:             return "Ramen"
        case .sushi:             return "Sushi"
        case .omakase:           return "Omakase"
        case .dimSum:            return "Dim Sum"
        case .pho:               return "Pho"
        case .bibimbap:          return "Bibimbap"
        case .koreanBBQ:         return "Korean BBQ"
        case .dumplings:         return "Dumplings"
        case .poke:              return "Poke"
        case .tapas:             return "Tapas"
        case .paella:            return "Paella"
        case .ibericoHam:        return "Iberico Ham"
        case .woodFiredPizza:    return "Wood-Fired Pizza"
        case .oysters:           return "Oysters"
        case .lobsterRolls:      return "Lobster Rolls"
        case .tartare:           return "Tartare"
        case .caviar:            return "Caviar"
        // ── Drinks ──
        case .whiskey:           return "Whiskey"
        case .amaro:             return "Amaro"
        case .newEnglandIPA:     return "New England IPA"
        case .craftBeer:         return "Craft Beer"
        case .naturalWine:       return "Natural Wine"
        case .sake:              return "Sake"
        case .cocktails:         return "Craft Cocktails"
        case .specialtyCoffee:   return "Specialty Coffee"
        case .boba:              return "Boba"
        case .tea:               return "Tea"
        case .matcha:            return "Matcha"
        case .kombucha:          return "Kombucha"
        case .cider:             return "Cider"
        // ── Sweets & Specialty ──
        case .artisanChocolate:  return "Artisan Chocolate"
        case .khachapuri:        return "Khachapuri"
        case .baklava:           return "Baklava"
        case .churros:           return "Churros"
        case .gelato:            return "Gelato"
        case .mochi:             return "Mochi"
        case .empanadas:         return "Empanadas"
        case .crepes:            return "Crepes"
        case .cremeBrulee:       return "Crème Brûlée"
        case .croissants:        return "Croissants"
        case .tresLeches:        return "Tres Leches"
        // ── Legacy ──
        case .negroni:           return "Negroni"
        case .bourbon:           return "Bourbon"
        case .singleMaltScotch:  return "Single Malt Scotch"
        case .fernetBranca:      return "Fernet Branca"
        case .peamealBacon:      return "Peameal Bacon"
        case .mapleSyrup:        return "Maple Syrup"
        case .fugu:              return "Fugu"
        case .pierogi:           return "Pierogi"
        case .smashburgers:      return "Smashburgers"
        case .pizza:             return "Neapolitan Pizza"
        // ── Custom ──
        case .custom:
            return foodCategory?.displayName ?? rawValue.replacingOccurrences(of: "custom_", with: "").capitalized
        }
    }

    /// Emoji shown on map pins, badges, and filter chips
    var emoji: String {
        switch self {
        // ── Food ──
        case .mezcal:            return "🥃"
        case .flan:              return "🍮"
        case .tortillas:         return "🫓"
        case .tacos:             return "🌮"
        case .birria:            return "🫕"
        case .pozole:            return "🍲"
        case .ceviche:           return "🐟"
        case .mole:              return "🫕"
        case .pupusas:           return "🫓"
        case .ramen:             return "🍜"
        case .sushi:             return "🍣"
        case .omakase:           return "🍣"
        case .dimSum:            return "🥟"
        case .pho:               return "🍲"
        case .bibimbap:          return "🍚"
        case .koreanBBQ:         return "🥩"
        case .dumplings:         return "🥟"
        case .poke:              return "🐟"
        case .tapas:             return "🍢"
        case .paella:            return "🥘"
        case .ibericoHam:        return "🍖"
        case .woodFiredPizza:    return "🍕"
        case .oysters:           return "🦪"
        case .lobsterRolls:      return "🦞"
        case .tartare:           return "🥩"
        case .caviar:            return "🫧"
        // ── Drinks ──
        case .whiskey:           return "🥃"
        case .amaro:             return "🌿"
        case .newEnglandIPA:     return "🍺"
        case .craftBeer:         return "🍺"
        case .naturalWine:       return "🍷"
        case .sake:              return "🍶"
        case .cocktails:         return "🍸"
        case .specialtyCoffee:   return "☕"
        case .boba:              return "🧋"
        case .tea:               return "🫖"
        case .matcha:            return "🍵"
        case .kombucha:          return "🫙"
        case .cider:             return "🍎"
        // ── Sweets & Specialty ──
        case .artisanChocolate:  return "🍫"
        case .khachapuri:        return "🧀"
        case .baklava:           return "🍯"
        case .churros:           return "🍩"
        case .gelato:            return "🍨"
        case .mochi:             return "🍡"
        case .empanadas:         return "🥟"
        case .crepes:            return "🥞"
        case .cremeBrulee:       return "🍮"
        case .croissants:        return "🥐"
        case .tresLeches:        return "🍰"
        // ── Legacy ──
        case .negroni:           return "🍹"
        case .bourbon:           return "🥃"
        case .singleMaltScotch:  return "🥃"
        case .fernetBranca:      return "🌿"
        case .peamealBacon:      return "🥓"
        case .mapleSyrup:        return "🍁"
        case .fugu:              return "🐡"
        case .pierogi:           return "🥟"
        case .smashburgers:      return "🍔"
        case .pizza:             return "🍕"
        // ── Custom ──
        case .custom:
            return foodCategory?.emoji ?? "🍽️"
        }
    }

    /// SF Symbol used where an emoji can't be used (e.g. Picker, map Marker)
    var icon: String {
        switch self {
        // Spirit drinks
        case .mezcal, .whiskey, .amaro, .cider:
            return "cup.and.saucer"
        // Beer
        case .newEnglandIPA, .craftBeer:
            return "mug"
        // Wine / cocktails / sake
        case .naturalWine, .sake, .cocktails:
            return "wineglass"
        // Coffee / tea
        case .specialtyCoffee, .tea, .matcha:
            return "cup.and.saucer.fill"
        // Boba / kombucha
        case .boba, .kombucha:
            return "takeoutbag.and.cup.and.straw"
        // Legacy spirits
        case .negroni, .bourbon, .singleMaltScotch, .fernetBranca:
            return "cup.and.saucer"
        // Everything else (food + sweets + custom)
        default:
            return "fork.knife"
        }
    }

    /// Accent color for badges, filter chips, and map pins.
    /// Custom Flezcals use white — they get a permanent color when promoted.
    var color: Color {
        switch self {
        // ── Food ──
        case .mezcal:            return .green
        case .flan:              return .orange
        case .tortillas:         return Color(red: 0.85, green: 0.65, blue: 0.2)
        case .tacos:             return Color(red: 0.95, green: 0.6, blue: 0.0)
        case .birria:            return Color(red: 0.7, green: 0.1, blue: 0.0)
        case .pozole:            return Color(red: 0.7, green: 0.2, blue: 0.15)
        case .ceviche:           return Color(red: 0.0, green: 0.6, blue: 0.6)
        case .mole:              return Color(red: 0.4, green: 0.15, blue: 0.1)
        case .pupusas:           return Color(red: 0.75, green: 0.5, blue: 0.15)
        case .ramen:             return Color(red: 0.85, green: 0.2, blue: 0.1)
        case .sushi:             return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .omakase:           return Color(red: 0.2, green: 0.2, blue: 0.4)
        case .dimSum:            return Color(red: 0.8, green: 0.15, blue: 0.15)
        case .pho:               return Color(red: 0.6, green: 0.35, blue: 0.1)
        case .bibimbap:          return Color(red: 0.8, green: 0.25, blue: 0.15)
        case .koreanBBQ:         return Color(red: 0.75, green: 0.15, blue: 0.1)
        case .dumplings:         return Color(red: 0.85, green: 0.55, blue: 0.2)
        case .poke:              return Color(red: 0.1, green: 0.55, blue: 0.7)
        case .tapas:             return Color(red: 0.8, green: 0.4, blue: 0.1)
        case .paella:            return Color(red: 0.9, green: 0.7, blue: 0.1)
        case .ibericoHam:        return Color(red: 0.65, green: 0.15, blue: 0.25)
        case .woodFiredPizza:    return Color(red: 0.8, green: 0.2, blue: 0.1)
        case .oysters:           return Color(red: 0.2, green: 0.45, blue: 0.5)
        case .lobsterRolls:      return Color(red: 0.85, green: 0.3, blue: 0.2)
        case .tartare:           return Color(red: 0.6, green: 0.1, blue: 0.1)
        case .caviar:            return Color(red: 0.15, green: 0.2, blue: 0.3)
        // ── Drinks ──
        case .whiskey:           return Color(red: 0.65, green: 0.38, blue: 0.08)
        case .amaro:             return Color(red: 0.1, green: 0.35, blue: 0.15)
        case .newEnglandIPA:     return Color(red: 0.85, green: 0.65, blue: 0.15)
        case .craftBeer:         return Color(red: 0.8, green: 0.5, blue: 0.1)
        case .naturalWine:       return Color(red: 0.6, green: 0.1, blue: 0.3)
        case .sake:              return Color(red: 0.2, green: 0.5, blue: 0.7)
        case .cocktails:         return Color(red: 0.2, green: 0.3, blue: 0.7)
        case .specialtyCoffee:   return Color(red: 0.4, green: 0.25, blue: 0.1)
        case .boba:              return Color(red: 0.7, green: 0.45, blue: 0.2)
        case .tea:               return Color(red: 0.4, green: 0.55, blue: 0.3)
        case .matcha:            return Color(red: 0.3, green: 0.6, blue: 0.2)
        case .kombucha:          return Color(red: 0.5, green: 0.7, blue: 0.3)
        case .cider:             return Color(red: 0.7, green: 0.3, blue: 0.15)
        // ── Sweets & Specialty ──
        case .artisanChocolate:  return Color(red: 0.35, green: 0.18, blue: 0.08)
        case .khachapuri:        return Color(red: 0.85, green: 0.65, blue: 0.25)
        case .baklava:           return Color(red: 0.75, green: 0.55, blue: 0.1)
        case .churros:           return Color(red: 0.85, green: 0.55, blue: 0.1)
        case .gelato:            return Color(red: 0.4, green: 0.7, blue: 0.9)
        case .mochi:             return Color(red: 0.9, green: 0.5, blue: 0.7)
        case .empanadas:         return Color(red: 0.8, green: 0.5, blue: 0.1)
        case .crepes:            return Color(red: 0.9, green: 0.75, blue: 0.4)
        case .cremeBrulee:       return Color(red: 0.9, green: 0.75, blue: 0.3)
        case .croissants:        return Color(red: 0.85, green: 0.7, blue: 0.3)
        case .tresLeches:        return Color(red: 0.95, green: 0.85, blue: 0.65)
        // ── Legacy ──
        case .negroni:           return Color(red: 0.7, green: 0.15, blue: 0.1)
        case .bourbon:           return Color(red: 0.72, green: 0.45, blue: 0.1)
        case .singleMaltScotch:  return Color(red: 0.55, green: 0.3, blue: 0.05)
        case .fernetBranca:      return Color(red: 0.1, green: 0.35, blue: 0.15)
        case .peamealBacon:      return Color(red: 0.7, green: 0.4, blue: 0.2)
        case .mapleSyrup:        return Color(red: 0.72, green: 0.4, blue: 0.08)
        case .fugu:              return Color(red: 0.15, green: 0.4, blue: 0.65)
        case .pierogi:           return Color(red: 0.8, green: 0.6, blue: 0.15)
        case .smashburgers:      return Color(red: 0.8, green: 0.15, blue: 0.1)
        case .pizza:             return Color(red: 0.8, green: 0.2, blue: 0.1)
        // ── Custom — white pin until promoted ──
        case .custom:            return .white
        }
    }

    /// Keywords scanned on a venue's homepage (mirrors FoodCategory.websiteKeywords)
    var websiteKeywords: [String] {
        switch self {
        // ── Food ──
        case .mezcal:
            return ["mezcal", "mezcalería", "mezcales",
                    "mezcal list", "mezcal menu", "mezcal selection", "agave spirits"]
        case .flan:
            return ["flan", "flan casero"]
        case .tortillas:
            return ["handmade tortillas", "tortillas hechas a mano", "fresh tortillas",
                    "tortilleria", "house-made tortillas", "homemade tortillas"]
        case .tacos:
            return ["tacos", "taqueria", "al pastor", "carnitas",
                    "suadero", "taco menu"]
        case .birria:
            return ["birria", "birrieria", "consomé", "birria tacos",
                    "quesabirria", "birria de res"]
        case .pozole:
            return ["pozole", "pozole rojo", "pozole verde",
                    "pozole blanco", "pozolería"]
        case .ceviche:
            return ["ceviche", "cevichería", "leche de tigre",
                    "ceviche mixto", "ceviche de pescado"]
        case .mole:
            return ["mole", "mole negro", "mole poblano", "mole rojo",
                    "mole oaxaqueño", "mole coloradito"]
        case .pupusas:
            return ["pupusas", "pupusería", "curtido", "pupusa",
                    "pupusas revueltas"]
        case .ramen:
            return ["ramen", "tonkotsu", "shoyu ramen", "miso ramen",
                    "ramen shop", "tsukemen"]
        case .sushi:
            return ["sushi", "nigiri", "sashimi", "sushi bar",
                    "maki", "sushi roll", "chirashi"]
        case .omakase:
            return ["omakase", "chef's choice", "tasting menu sushi",
                    "omakase menu", "kappo"]
        case .dimSum:
            return ["dim sum", "yum cha", "har gow", "siu mai",
                    "dim sum menu", "steamed dumplings"]
        case .pho:
            return ["pho", "phở", "pho menu"]
        case .bibimbap:
            return ["bibimbap", "dolsot bibimbap", "stone pot bibimbap",
                    "mixed rice bowl"]
        case .koreanBBQ:
            return ["korean bbq", "korean barbecue", "kbbq", "bulgogi",
                    "galbi", "samgyeopsal", "ssam"]
        case .dumplings:
            return ["dumplings", "xiaolongbao", "gyoza", "jiaozi",
                    "soup dumplings", "potstickers", "mandu"]
        case .poke:
            return ["poke", "poké", "poke bowl", "ahi poke",
                    "poke menu", "build your bowl"]
        case .tapas:
            return ["tapas", "pintxos", "pinchos", "tapas bar",
                    "raciones", "croquetas", "patatas bravas"]
        case .paella:
            return ["paella", "paella valenciana", "paella mixta",
                    "arroz", "bomba rice"]
        case .ibericoHam:
            return ["iberico", "ibérico", "jamón ibérico", "jamon iberico",
                    "pata negra", "bellota"]
        case .woodFiredPizza:
            return ["wood fired", "wood-fired", "wood oven", "brick oven",
                    "neapolitan", "napoletana", "pizza napoletana"]
        case .oysters:
            return ["oysters", "oyster bar", "fresh oysters",
                    "oyster selection", "shucked"]
        case .lobsterRolls:
            return ["lobster roll", "lobster rolls", "lobster sandwich",
                    "maine lobster roll", "connecticut lobster roll"]
        case .tartare:
            return ["tartare", "steak tartare", "beef tartare",
                    "tuna tartare", "salmon tartare"]
        case .caviar:
            return ["caviar", "osetra", "beluga caviar",
                    "sturgeon caviar", "caviar service"]
        // ── Drinks ──
        case .whiskey:
            return ["whiskey", "whisky", "bourbon", "scotch", "rye whiskey",
                    "single malt", "whiskey selection", "whiskey list"]
        case .amaro:
            return ["amaro", "amari", "digestif", "digestivo",
                    "fernet", "averna", "montenegro"]
        case .newEnglandIPA:
            return ["new england ipa", "neipa", "hazy ipa",
                    "juicy ipa", "hazy pale ale"]
        case .craftBeer:
            return ["craft beer", "microbrewery", "taproom", "craft ale",
                    "local brew", "on tap", "draft list"]
        case .naturalWine:
            return ["natural wine", "natty wine", "orange wine",
                    "biodynamic wine", "skin contact", "low intervention"]
        case .sake:
            return ["sake", "nihonshu", "junmai", "sake selection",
                    "sake list", "sake bar", "daiginjo"]
        case .cocktails:
            return ["craft cocktail", "mixology", "artisan cocktail",
                    "cocktail menu", "signature cocktail", "house cocktail"]
        case .specialtyCoffee:
            return ["specialty coffee", "single origin", "pour over",
                    "third wave", "direct trade", "micro roast"]
        case .boba:
            return ["boba", "bubble tea", "tapioca", "milk tea",
                    "taro", "boba shop"]
        case .tea:
            return ["loose leaf tea", "tea service", "afternoon tea",
                    "high tea", "tea house", "tea room", "tea menu",
                    "chai", "oolong", "pu-erh"]
        case .matcha:
            return ["matcha", "matcha latte", "ceremonial matcha",
                    "matcha menu", "koicha", "usucha"]
        case .kombucha:
            return ["kombucha", "kombucha on tap", "fermented tea",
                    "probiotic", "jun kombucha"]
        case .cider:
            return ["cider", "hard cider", "craft cider", "cidery",
                    "cider house", "cider on tap"]
        // ── Sweets & Specialty ──
        case .artisanChocolate:
            return ["artisan chocolate", "bean to bar", "craft chocolate",
                    "single origin chocolate", "chocolatier", "cacao"]
        case .khachapuri:
            return ["khachapuri", "adjaruli", "adjarian",
                    "cheese bread", "georgian bread"]
        case .baklava:
            return ["baklava", "baklawa", "pistachio baklava",
                    "turkish sweets", "middle eastern sweets"]
        case .churros:
            return ["churros", "churro", "churrería",
                    "churros con chocolate", "churro shop"]
        case .gelato:
            return ["gelato", "gelateria", "artigianale",
                    "italian gelato", "artisan gelato"]
        case .mochi:
            return ["mochi", "daifuku", "mochi ice cream",
                    "wagashi", "japanese sweets"]
        case .empanadas:
            return ["empanadas", "empanada", "empanadas argentinas",
                    "empanada de carne", "empanadas caseras"]
        case .crepes:
            return ["crepes", "crêpes", "creperie", "crêperie",
                    "sweet crepes", "savory crepes", "galettes"]
        case .cremeBrulee:
            return ["crème brûlée", "creme brulee", "crema catalana",
                    "burnt cream"]
        case .croissants:
            return ["croissant", "croissants", "viennoiserie",
                    "pain au chocolat", "butter croissant", "laminated dough"]
        case .tresLeches:
            return ["tres leches", "three milk cake", "pastel tres leches",
                    "tres leches cake"]
        // ── Legacy ──
        case .negroni:
            return ["negroni", "sbagliato", "boulevardier",
                    "negroni menu", "negroni variations"]
        case .bourbon:
            return ["bourbon", "kentucky bourbon", "small batch bourbon",
                    "single barrel bourbon", "bourbon selection"]
        case .singleMaltScotch:
            return ["single malt", "scotch whisky", "single malt scotch",
                    "speyside", "islay", "highland scotch"]
        case .fernetBranca:
            return ["fernet", "fernet branca", "fernet-branca", "amaro", "digestif"]
        case .peamealBacon:
            return ["peameal bacon", "peameal", "canadian bacon",
                    "back bacon", "cornmeal bacon"]
        case .mapleSyrup:
            return ["maple syrup", "pure maple", "maple sugar",
                    "sugar shack", "cabane à sucre", "grade a maple"]
        case .fugu:
            return ["fugu", "pufferfish", "blowfish", "fugu sashimi", "tessa"]
        case .pierogi:
            return ["pierogi", "pierog", "pierogy", "pierogies",
                    "polish dumplings", "ruskie"]
        case .smashburgers:
            return ["smashburger", "smash burger", "smashed burger",
                    "smash patty", "crispy edges"]
        case .pizza:
            return ["neapolitan", "wood fired", "napoletana",
                    "pizza napoletana", "00 flour", "fior di latte"]
        // ── Custom — pull from registered FoodCategory ──
        case .custom:
            return foodCategory?.websiteKeywords ?? []
        }
    }

    /// Prompt shown on the Add Spot screen
    var addSpotPrompt: String {
        switch self {
        // ── Food ──
        case .mezcal:            return "Search for a bar, restaurant, or store to add it as a mezcal spot."
        case .flan:              return "Search for a restaurant or bakery to add it as a flan spot."
        case .tortillas:         return "Search for a restaurant or tortilleria that makes handmade tortillas."
        case .tacos:             return "Search for a taqueria or taco spot."
        case .birria:            return "Search for a birria restaurant or truck."
        case .pozole:            return "Search for a restaurant that serves pozole."
        case .ceviche:           return "Search for a restaurant that serves ceviche."
        case .mole:              return "Search for a restaurant that serves mole."
        case .pupusas:           return "Search for a pupuseria or Salvadoran restaurant."
        case .ramen:             return "Search for a ramen restaurant."
        case .sushi:             return "Search for a sushi bar or Japanese restaurant."
        case .omakase:           return "Search for a restaurant offering omakase."
        case .dimSum:            return "Search for a dim sum restaurant."
        case .pho:               return "Search for a pho or Vietnamese noodle restaurant."
        case .bibimbap:          return "Search for a Korean restaurant that serves bibimbap."
        case .koreanBBQ:         return "Search for a Korean BBQ restaurant."
        case .dumplings:         return "Search for a dumpling restaurant."
        case .poke:              return "Search for a poke restaurant."
        case .tapas:             return "Search for a tapas bar or Spanish restaurant."
        case .paella:            return "Search for a restaurant that serves paella."
        case .ibericoHam:        return "Search for a restaurant or shop that serves Iberico ham."
        case .woodFiredPizza:    return "Search for a wood-fired pizzeria."
        case .oysters:           return "Search for an oyster bar or raw bar restaurant."
        case .lobsterRolls:      return "Search for a seafood spot that serves lobster rolls."
        case .tartare:           return "Search for a restaurant that serves tartare."
        case .caviar:            return "Search for a restaurant with a caviar service."
        // ── Drinks ──
        case .whiskey:           return "Search for a bar or restaurant with a whiskey selection."
        case .amaro:             return "Search for a bar with an amaro selection."
        case .newEnglandIPA:     return "Search for a brewery or taproom with New England IPAs."
        case .craftBeer:         return "Search for a brewery, taproom, or craft beer bar."
        case .naturalWine:       return "Search for a wine bar or shop that carries natural wines."
        case .sake:              return "Search for a sake bar or Japanese restaurant with a sake program."
        case .cocktails:         return "Search for a craft cocktail bar."
        case .specialtyCoffee:   return "Search for a specialty coffee shop or roastery."
        case .boba:              return "Search for a boba or bubble tea shop."
        case .tea:               return "Search for a tea house, tea room, or cafe with a tea program."
        case .matcha:            return "Search for a matcha cafe or tea house."
        case .kombucha:          return "Search for a kombucha bar or shop."
        case .cider:             return "Search for a cidery or cider bar."
        // ── Sweets & Specialty ──
        case .artisanChocolate:  return "Search for a chocolatier or artisan chocolate shop."
        case .khachapuri:        return "Search for a Georgian restaurant that serves khachapuri."
        case .baklava:           return "Search for a bakery or shop that makes baklava."
        case .churros:           return "Search for a churro shop or bakery."
        case .gelato:            return "Search for a gelateria or artisan gelato shop."
        case .mochi:             return "Search for a mochi shop or Japanese sweets cafe."
        case .empanadas:         return "Search for an empanada shop or Latin American restaurant."
        case .crepes:            return "Search for a creperie or cafe that serves crepes."
        case .cremeBrulee:       return "Search for a restaurant that serves crème brûlée."
        case .croissants:        return "Search for a bakery known for its croissants."
        case .tresLeches:        return "Search for a bakery or restaurant that serves tres leches."
        // ── Legacy ──
        case .negroni:           return "Search for a bar known for its negroni."
        case .bourbon:           return "Search for a bar or restaurant with a bourbon selection."
        case .singleMaltScotch:  return "Search for a bar with a single malt scotch selection."
        case .fernetBranca:      return "Search for a bar that serves Fernet Branca."
        case .peamealBacon:      return "Search for a restaurant or deli that serves peameal bacon."
        case .mapleSyrup:        return "Search for a spot that serves or sells real maple syrup."
        case .fugu:              return "Search for a Japanese restaurant that serves fugu."
        case .pierogi:           return "Search for a restaurant that serves pierogi."
        case .smashburgers:      return "Search for a restaurant that serves smashburgers."
        case .pizza:             return "Search for a Neapolitan or wood-fired pizzeria."
        // ── Custom ──
        case .custom:
            return foodCategory?.addSpotPrompt
                ?? "Search for a restaurant or shop that serves \(displayName.lowercased())."
        }
    }

    /// All categories now support user-contributed offerings (brands, styles, types).
    var supportsOfferings: Bool { true }

    /// Label for the offerings section header
    var offeringsLabel: String {
        switch self {
        // ── Food ──
        case .mezcal:            return "Mezcal Brands"
        case .flan:              return "Flan Styles"
        case .tortillas:         return "Tortilla Types"
        case .tacos:             return "Taco Types"
        case .birria:            return "Birria Styles"
        case .pozole:            return "Pozole Styles"
        case .ceviche:           return "Ceviche Types"
        case .mole:              return "Mole Varieties"
        case .pupusas:           return "Pupusa Fillings"
        case .ramen:             return "Ramen Styles"
        case .sushi:             return "Sushi Highlights"
        case .omakase:           return "Omakase Style"
        case .dimSum:            return "Dim Sum Dishes"
        case .pho:               return "Pho Types"
        case .bibimbap:          return "Bibimbap Types"
        case .koreanBBQ:         return "BBQ Cuts"
        case .dumplings:         return "Dumpling Types"
        case .poke:              return "Poke Bowls"
        case .tapas:             return "Tapas Dishes"
        case .paella:            return "Paella Types"
        case .ibericoHam:        return "Ham Grades"
        case .woodFiredPizza:    return "Pizza Styles"
        case .oysters:           return "Oyster Varieties"
        case .lobsterRolls:      return "Roll Styles"
        case .tartare:           return "Tartare Types"
        case .caviar:            return "Caviar Types"
        // ── Drinks ──
        case .whiskey:           return "Whiskey Brands"
        case .amaro:             return "Amaro Brands"
        case .newEnglandIPA:     return "Beer Brands"
        case .craftBeer:         return "Beer Styles"
        case .naturalWine:       return "Wine Styles"
        case .sake:              return "Sake Types"
        case .cocktails:         return "Cocktail Styles"
        case .specialtyCoffee:   return "Coffee Methods"
        case .boba:              return "Drink Flavors"
        case .tea:               return "Tea Varieties"
        case .matcha:            return "Matcha Types"
        case .kombucha:          return "Kombucha Flavors"
        case .cider:             return "Cider Styles"
        // ── Sweets & Specialty ──
        case .artisanChocolate:  return "Chocolate Types"
        case .khachapuri:        return "Khachapuri Styles"
        case .baklava:           return "Baklava Types"
        case .churros:           return "Churro Varieties"
        case .gelato:            return "Gelato Flavors"
        case .mochi:             return "Mochi Types"
        case .empanadas:         return "Empanada Fillings"
        case .crepes:            return "Crepe Varieties"
        case .cremeBrulee:       return "Brûlée Flavors"
        case .croissants:        return "Croissant Types"
        case .tresLeches:        return "Tres Leches Styles"
        // ── Legacy ──
        case .negroni:           return "Negroni Variations"
        case .bourbon:           return "Bourbon Brands"
        case .singleMaltScotch:  return "Scotch Brands"
        case .fernetBranca:      return "Serving Styles"
        case .peamealBacon:      return "Serving Styles"
        case .mapleSyrup:        return "Syrup Grades"
        case .fugu:              return "Fugu Preparations"
        case .pierogi:           return "Pierogi Fillings"
        case .smashburgers:      return "Burger Styles"
        case .pizza:             return "Pizza Styles"
        // ── Custom ──
        case .custom:            return "\(displayName) Varieties"
        }
    }

    /// Singular label for an offering entry (e.g. "brand", "style", "flavor")
    var offeringSingular: String {
        switch self {
        // ── Food ──
        case .mezcal:            return "brand"
        case .flan:              return "style"
        case .tortillas:         return "type"
        case .tacos:             return "type"
        case .birria:            return "style"
        case .pozole:            return "style"
        case .ceviche:           return "type"
        case .mole:              return "variety"
        case .pupusas:           return "filling"
        case .ramen:             return "style"
        case .sushi:             return "highlight"
        case .omakase:           return "style"
        case .dimSum:            return "dish"
        case .pho:               return "type"
        case .bibimbap:          return "type"
        case .koreanBBQ:         return "cut"
        case .dumplings:         return "type"
        case .poke:              return "bowl"
        case .tapas:             return "dish"
        case .paella:            return "type"
        case .ibericoHam:        return "grade"
        case .woodFiredPizza:    return "style"
        case .oysters:           return "variety"
        case .lobsterRolls:      return "style"
        case .tartare:           return "type"
        case .caviar:            return "type"
        // ── Drinks ──
        case .whiskey:           return "brand"
        case .amaro:             return "brand"
        case .newEnglandIPA:     return "brand"
        case .craftBeer:         return "style"
        case .naturalWine:       return "style"
        case .sake:              return "type"
        case .cocktails:         return "style"
        case .specialtyCoffee:   return "method"
        case .boba:              return "flavor"
        case .tea:               return "variety"
        case .matcha:            return "type"
        case .kombucha:          return "flavor"
        case .cider:             return "style"
        // ── Sweets & Specialty ──
        case .artisanChocolate:  return "type"
        case .khachapuri:        return "style"
        case .baklava:           return "type"
        case .churros:           return "variety"
        case .gelato:            return "flavor"
        case .mochi:             return "type"
        case .empanadas:         return "filling"
        case .crepes:            return "variety"
        case .cremeBrulee:       return "flavor"
        case .croissants:        return "type"
        case .tresLeches:        return "style"
        // ── Legacy ──
        case .negroni:           return "variation"
        case .bourbon:           return "brand"
        case .singleMaltScotch:  return "brand"
        case .fernetBranca:      return "style"
        case .peamealBacon:      return "style"
        case .mapleSyrup:        return "grade"
        case .fugu:              return "preparation"
        case .pierogi:           return "filling"
        case .smashburgers:      return "style"
        case .pizza:             return "style"
        // ── Custom ──
        case .custom:            return "variety"
        }
    }

    /// Example offerings shown as placeholder hints
    var offeringsExamples: String {
        switch self {
        // ── Food ──
        case .mezcal:            return "e.g. Del Maguey, Vago, Bozal"
        case .flan:              return "e.g. Classic, Coconut, Cheese Flan"
        case .tortillas:         return "e.g. Corn, Flour, Blue Corn, Handmade"
        case .tacos:             return "e.g. Al Pastor, Carnitas, Suadero"
        case .birria:            return "e.g. Tacos, Consomme, Quesabirria"
        case .pozole:            return "e.g. Rojo, Verde, Blanco"
        case .ceviche:           return "e.g. Mixto, Pescado, Shrimp"
        case .mole:              return "e.g. Negro, Poblano, Rojo, Coloradito"
        case .pupusas:           return "e.g. Revueltas, Queso, Frijol, Loroco"
        case .ramen:             return "e.g. Tonkotsu, Shoyu, Miso, Tsukemen"
        case .sushi:             return "e.g. Omakase, Chirashi, Salmon Nigiri"
        case .omakase:           return "e.g. Edomae, Seasonal, Chef's Special"
        case .dimSum:            return "e.g. Har Gow, Siu Mai, Char Siu Bao"
        case .pho:               return "e.g. Tai (Rare Beef), Dac Biet (Special)"
        case .bibimbap:          return "e.g. Dolsot (Stone Pot), Vegetable, Beef"
        case .koreanBBQ:         return "e.g. Bulgogi, Galbi, Samgyeopsal"
        case .dumplings:         return "e.g. Xiaolongbao, Gyoza, Potstickers"
        case .poke:              return "e.g. Ahi Tuna, Salmon, Spicy Mayo"
        case .tapas:             return "e.g. Croquetas, Patatas Bravas, Gambas"
        case .paella:            return "e.g. Valenciana, Mixta, Mariscos"
        case .ibericoHam:        return "e.g. Bellota, Cebo, Reserva"
        case .woodFiredPizza:    return "e.g. Margherita, Marinara, Diavola"
        case .oysters:           return "e.g. Wellfleet, Kumamoto, Blue Point"
        case .lobsterRolls:      return "e.g. Maine Style, Connecticut Style"
        case .tartare:           return "e.g. Steak, Tuna, Salmon"
        case .caviar:            return "e.g. Osetra, Beluga, Paddlefish"
        // ── Drinks ──
        case .whiskey:           return "e.g. Maker's Mark, Lagavulin, Nikka"
        case .amaro:             return "e.g. Fernet, Averna, Montenegro, Cynar"
        case .newEnglandIPA:     return "e.g. Trillium, Tree House, Other Half"
        case .craftBeer:         return "e.g. Hazy IPA, Stout, Sour, Pilsner"
        case .naturalWine:       return "e.g. Pet-Nat, Orange, Skin Contact"
        case .sake:              return "e.g. Junmai, Daiginjo, Nigori"
        case .cocktails:         return "e.g. Negroni, Old Fashioned, Mezcal Mule"
        case .specialtyCoffee:   return "e.g. Pour Over, Espresso, Cold Brew"
        case .boba:              return "e.g. Taro, Brown Sugar, Matcha"
        case .tea:               return "e.g. Earl Grey, Oolong, Pu-erh, Chai"
        case .matcha:            return "e.g. Ceremonial, Latte, Iced, Koicha"
        case .kombucha:          return "e.g. Ginger, Lavender, Hibiscus"
        case .cider:             return "e.g. Dry, Semi-Sweet, Rosé, Perry"
        // ── Sweets & Specialty ──
        case .artisanChocolate:  return "e.g. Single Origin Bar, Truffles, Bonbons"
        case .khachapuri:        return "e.g. Adjaruli, Imeruli, Megruli"
        case .baklava:           return "e.g. Pistachio, Walnut, Bird's Nest"
        case .churros:           return "e.g. Classic, Filled, Chocolate Dipped"
        case .gelato:            return "e.g. Pistachio, Stracciatella, Hazelnut"
        case .mochi:             return "e.g. Daifuku, Ice Cream, Strawberry"
        case .empanadas:         return "e.g. Beef, Chicken, Cheese, Spinach"
        case .crepes:            return "e.g. Nutella, Savory Ham & Cheese"
        case .cremeBrulee:       return "e.g. Classic Vanilla, Lavender, Espresso"
        case .croissants:        return "e.g. Butter, Almond, Pain au Chocolat"
        case .tresLeches:        return "e.g. Classic, Chocolate, Strawberry"
        // ── Legacy ──
        case .negroni:           return "e.g. Classic, Sbagliato, White, Mezcal"
        case .bourbon:           return "e.g. Maker's Mark, Woodford Reserve, Buffalo Trace"
        case .singleMaltScotch:  return "e.g. Lagavulin, Macallan, Glenfiddich"
        case .fernetBranca:      return "e.g. Neat, with Cola, Cocktail"
        case .peamealBacon:      return "e.g. Classic Sandwich, Eggs Benedict, Platter"
        case .mapleSyrup:        return "e.g. Grade A Amber, Dark Robust, Maple Candy"
        case .fugu:              return "e.g. Sashimi (Tessa), Hot Pot (Tecchiri)"
        case .pierogi:           return "e.g. Potato & Cheese, Sauerkraut, Meat"
        case .smashburgers:      return "e.g. Single, Double, Cheese, Special Sauce"
        case .pizza:             return "e.g. Margherita, Marinara, Diavola"
        // ── Custom ──
        case .custom:            return "e.g. Add specific varieties or styles"
        }
    }
}

// MARK: - Codable

extension SpotCategory: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
