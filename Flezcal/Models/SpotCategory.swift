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
    case pierogi

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
        default:
            // Auto-promote: if a "custom_X" value matches a built-in case,
            // decode as the built-in. Supports dynamic promotion of trending
            // categories without requiring a Firestore migration first.
            if rawValue.hasPrefix("custom_") {
                let stripped = String(rawValue.dropFirst(7))
                let promoted = SpotCategory(rawValue: stripped)
                if case .custom = promoted {
                    // stripped ID isn't built-in either — keep as custom
                    self = .custom(rawValue)
                } else {
                    self = promoted
                }
            } else {
                self = .custom(rawValue)
            }
        }
    }

    /// All built-in cases (excludes `.custom`). Replaces CaseIterable.
    static let allCases: [SpotCategory] = [
        // Food
        .mezcal, .flan,
        .tacos, .birria, .pozole, .ceviche, .mole, .pupusas,
        .ramen, .sushi, .omakase, .dimSum, .pho, .bibimbap, .koreanBBQ, .dumplings, .poke,
        .tapas, .paella, .ibericoHam, .woodFiredPizza,
        .oysters, .lobsterRolls, .tartare, .caviar, .pierogi,
        // Drinks
        .whiskey, .amaro, .newEnglandIPA, .craftBeer, .naturalWine,
        .sake, .cocktails, .specialtyCoffee, .boba, .tea, .matcha, .kombucha, .cider,
        // Sweets & Specialty
        .artisanChocolate, .khachapuri, .baklava, .churros, .gelato,
        .mochi, .empanadas, .crepes, .cremeBrulee, .croissants, .tresLeches,
        // Legacy
        .negroni, .bourbon, .singleMaltScotch, .fernetBranca,
        .peamealBacon, .mapleSyrup, .fugu, .smashburgers, .pizza,
    ]

    /// Whether this is a custom (user-created) category.
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// Whether this is a legacy category no longer shown in the picker grid.
    var isLegacy: Bool {
        foodCategory?.isLegacy ?? false
    }

    // MARK: - FoodCategory Lookup (for custom categories)

    /// Looks up the FoodCategory for this SpotCategory.
    /// Built-in categories use FoodCategory.allKnownCategories.
    /// Custom categories use the nonisolated snapshot of activeCustomPicks.
    private var foodCategory: FoodCategory? {
        FoodCategory.by(id: rawValue)
    }

    // MARK: - Display Properties
    //
    // All display metadata delegates to FoodCategory as the single source of truth.
    // Firestore overrides (via SearchTermOverrideService) take precedence.
    // When dynamic ranking ships, FoodCategory definitions will move to Firestore.

    /// Name shown in the UI
    var displayName: String {
        if let override = SearchTermOverrideService.overridesSnapshot[rawValue],
           let name = override.displayName { return name }
        return foodCategory?.displayName
            ?? rawValue.replacingOccurrences(of: "custom_", with: "").capitalized
    }

    /// Emoji shown on map pins, badges, and filter chips.
    /// Custom/trending categories use the admin-configurable default emoji.
    var emoji: String {
        if let override = SearchTermOverrideService.overridesSnapshot[rawValue],
           let e = override.emoji { return e }
        if isCustom { return FeatureFlagService.trendingEmojiSnapshot }
        return foodCategory?.emoji ?? FeatureFlagService.trendingEmojiSnapshot
    }

    /// SF Symbol used where an emoji can't be rendered (e.g. Picker, map Marker)
    var icon: String {
        foodCategory?.icon ?? "fork.knife"
    }

    /// Accent color for badges, filter chips, and map pins.
    /// Custom / Trending Flezcals use cyan to match the trending tier.
    var color: Color {
        if let override = SearchTermOverrideService.overridesSnapshot[rawValue],
           let hex = override.colorHex { return Color(hex: hex) }
        if isCustom { return .cyan }
        return foodCategory?.color ?? .cyan
    }

    /// Keywords scanned on a venue's homepage.
    /// Checks admin Firestore overrides first, then delegates to FoodCategory.
    var websiteKeywords: [String] {
        if let override = SearchTermOverrideService.overridesSnapshot[rawValue],
           let keywords = override.websiteKeywords {
            return keywords
        }
        return foodCategory?.websiteKeywords ?? []
    }

    /// Prompt shown on the Add Spot screen
    var addSpotPrompt: String {
        if let override = SearchTermOverrideService.overridesSnapshot[rawValue],
           let prompt = override.addSpotPrompt { return prompt }
        return foodCategory?.addSpotPrompt
            ?? "Search for a restaurant or shop that serves \(displayName.lowercased())."
    }

    /// All categories support user-contributed offerings (brands, styles, types).
    var supportsOfferings: Bool { true }

    /// Label for the offerings section header
    var offeringsLabel: String {
        foodCategory?.offeringsLabel ?? "\(displayName) Varieties"
    }

    /// Singular label for an offering entry (e.g. "brand", "style", "flavor")
    var offeringSingular: String {
        foodCategory?.offeringSingular ?? "variety"
    }

    /// Example offerings shown as placeholder hints
    var offeringsExamples: String {
        foodCategory?.offeringsExamples ?? "e.g. Add specific varieties or styles"
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
