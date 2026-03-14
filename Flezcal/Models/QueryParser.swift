import Foundation
import CoreLocation

// MARK: - Result Types

/// The four supported voice command patterns
enum VoiceCommandType {
    case categoryAndLocation(category: String, location: VoiceLocation)
    case categoryOnly(category: String)         // uses device location
    case locationOnly(location: VoiceLocation)  // shows all categories nearby
    case spotName(name: String)                 // direct spot name search
    case unrecognized
}

enum VoiceLocation {
    case nearMe                                 // use CLLocationManager
    case city(String)                           // geocode this string
}

/// Parsed result returned to the search layer
struct VoiceQuery {
    let command: VoiceCommandType
    let rawTranscript: String
    /// Suggestions if the category was a near-miss (for "did you mean" UI)
    let categorySuggestions: [String]
}

// MARK: - QueryParser

/// Parses natural-language voice transcripts into structured VoiceQuery results.
///
/// Design principles:
/// - **Category-first**: always tries to extract a Flezcal category and/or
///   location before falling back to spot-name search. Works with any phrasing
///   as long as a recognizable category or location is present.
/// - Normalises text (strips hyphens, punctuation, diacritics) before matching
/// - Uses keyword aliases so "pizza" matches "Wood-Fired Pizza", "IPA" matches
///   "New England IPA", etc.
/// - Sliding-window n-gram matching (1–4 words) for multi-word categories
/// - Fuzzy Levenshtein matching on n-grams, not just single words
/// - Spot name search is a fallback only when no category or location is found
class QueryParser {

    // MARK: - Category Data

    /// Canonical category names from FoodCategory (lowercased).
    static let knownCategories: [String] = FoodCategory.allKnownCategories
        .map { $0.displayName.lowercased() }

    /// Normalised form of each category for matching against normalised transcript.
    /// e.g. "wood-fired pizza" → "wood fired pizza", "crème brûlée" → "creme brulee"
    private static let normalizedCategories: [(original: String, normalized: String)] =
        knownCategories.map { ($0, normalize($0)) }

    /// Maps a short keyword or common speech variant to its canonical category name.
    /// Speech recognition often drops hyphens, uses singular/plural, or abbreviates.
    private static let categoryAliases: [String: String] = {
        var map: [String: String] = [:]

        // Build automatic aliases from display names
        for category in knownCategories {
            let normalized = normalize(category)
            let words = normalized.components(separatedBy: " ")

            // Multi-word categories: last word is a strong alias
            // e.g. "pizza" → "wood-fired pizza", "rolls" → "lobster rolls"
            if words.count >= 2, let last = words.last, last.count >= 4 {
                // Only set if not already mapped (first one wins — more specific)
                if map[last] == nil { map[last] = category }
            }

            // Hyphenated categories: join words without spaces as an alias
            // "woodfired" → "wood-fired pizza"
            if normalized.contains(" ") && category.contains("-") {
                let joined = normalized.replacingOccurrences(of: " ", with: "")
                map[joined] = category
            }
        }

        // ── Explicit aliases for common speech patterns ──

        // Food
        map["pizza"] = "wood-fired pizza"
        map["wood fired pizza"] = "wood-fired pizza"
        map["woodfired pizza"] = "wood-fired pizza"
        map["wood fire pizza"] = "wood-fired pizza"
        map["fired pizza"] = "wood-fired pizza"
        map["lobster roll"] = "lobster rolls"
        map["lobster"] = "lobster rolls"
        map["dim sum"] = "dim sum"            // already exact, but confirm
        map["dimsum"] = "dim sum"
        map["korean barbecue"] = "korean bbq"
        map["korean barbeque"] = "korean bbq"
        map["kbbq"] = "korean bbq"
        map["bbq"] = "korean bbq"
        map["smash burger"] = "smashburgers"
        map["smash burgers"] = "smashburgers"
        map["burger"] = "smashburgers"
        map["burgers"] = "smashburgers"
        map["iberico"] = "iberico ham"
        map["ham"] = "iberico ham"
        map["jamon"] = "iberico ham"
        map["dumpling"] = "dumplings"
        map["oyster"] = "oysters"
        map["croissant"] = "croissants"
        map["empanada"] = "empanadas"
        map["crepe"] = "crepes"
        map["taco"] = "tacos"
        map["pupusa"] = "pupusas"
        map["churro"] = "churros"
        map["pierogy"] = "pierogi"
        map["perogies"] = "pierogi"
        map["perogi"] = "pierogi"
        map["peameal"] = "peameal bacon"
        map["bacon"] = "peameal bacon"
        map["neapolitan"] = "neapolitan pizza"
        map["neapolitan pizza"] = "neapolitan pizza"
        map["artisan chocolate"] = "artisan chocolate"
        map["chocolate"] = "artisan chocolate"
        map["tres leche"] = "tres leches"
        map["three milk"] = "tres leches"
        map["creme brulee"] = "crème brûlée"
        map["creme brûlée"] = "crème brûlée"
        map["brulee"] = "crème brûlée"

        // Drinks
        map["cocktails"] = "craft cocktails"
        map["cocktail"] = "craft cocktails"
        map["craft cocktail"] = "craft cocktails"
        map["mixed drinks"] = "craft cocktails"
        map["drinks"] = "craft cocktails"
        map["ipa"] = "new england ipa"
        map["new england"] = "new england ipa"
        map["neipa"] = "new england ipa"
        map["hazy ipa"] = "new england ipa"
        map["hazy"] = "new england ipa"
        map["beer"] = "craft beer"
        map["beers"] = "craft beer"
        map["craft beers"] = "craft beer"
        map["wine"] = "natural wine"
        map["wines"] = "natural wine"
        map["natural wines"] = "natural wine"
        map["coffee"] = "specialty coffee"
        map["espresso"] = "specialty coffee"
        map["latte"] = "specialty coffee"
        map["scotch"] = "single malt scotch"
        map["single malt"] = "single malt scotch"
        map["malt scotch"] = "single malt scotch"
        map["fernet"] = "fernet branca"
        map["maple"] = "maple syrup"
        map["syrup"] = "maple syrup"
        map["bubble tea"] = "boba"
        map["ice cream"] = "gelato"

        // Catch-all natural speech
        map["mezcal"] = "mezcal"
        map["mescal"] = "mezcal"
        map["mezcals"] = "mezcal"

        return map
    }()

    // MARK: - Triggers

    private static let nearMeTriggers = [
        "near me", "nearby", "around me", "close to me", "around here",
        "close by", "in my area", "where i am", "this area"
    ]

    /// Spot name triggers — only used as a fallback when no category or
    /// location was found. Longer phrases first so "find me" matches before "find".
    private static let spotTriggers = [
        "find me", "look up", "take me to",
        "where is", "wheres", "directions to", "navigate to",
        "find"
    ]

    private static let locationPreps = ["in", "near", "around", "at", "close to"]

    // MARK: - Public

    /// Parses a voice transcript into a structured query.
    ///
    /// Strategy: **category-first** — always tries to extract a Flezcal category
    /// and/or location before anything else. Spot name search is a fallback only
    /// when neither category nor location is found. This means any phrasing works
    /// ("find me pizza in Calgary", "I want tacos nearby", "where can I get flan
    /// in Boston", "show me craft beer around here") as long as the transcript
    /// contains a recognizable category name/alias and/or location.
    static func parse(_ raw: String) -> VoiceQuery {
        let text = normalize(raw)

        // 1. Extract location (always — works regardless of phrasing)
        let location = extractLocation(from: text)

        // 2. Strip location text before category matching so city names
        //    don't interfere with n-gram matching
        let textForCategory = stripLocationText(from: text)

        // 3. Match category from the remainder
        let (matchedCategory, suggestions) = extractCategory(from: textForCategory, fullText: text)

        // 4. If category and/or location found → return structured result
        switch (matchedCategory, location) {
        case (.some(let cat), .some(let loc)):
            return VoiceQuery(command: .categoryAndLocation(category: cat, location: loc),
                              rawTranscript: raw, categorySuggestions: [])
        case (.some(let cat), .none):
            return VoiceQuery(command: .categoryOnly(category: cat),
                              rawTranscript: raw, categorySuggestions: [])
        case (.none, .some(let loc)):
            return VoiceQuery(command: .locationOnly(location: loc),
                              rawTranscript: raw, categorySuggestions: suggestions)
        case (.none, .none):
            break  // Fall through to spot name fallback
        }

        // 5. Fallback: spot name search (only when no category or location found)
        //    e.g. "find Taqueria El Rancho", "look up Joe's Pizza"
        if let spotName = extractSpotName(from: text, raw: raw) {
            return VoiceQuery(command: .spotName(name: spotName),
                              rawTranscript: raw, categorySuggestions: [])
        }

        // 6. Nothing recognized
        return VoiceQuery(command: .unrecognized,
                          rawTranscript: raw, categorySuggestions: suggestions)
    }

    // MARK: - Category Extraction

    /// Returns the best matching category name, plus close suggestions for "did you mean".
    ///
    /// Strategy (in priority order):
    /// 1. Exact substring match of normalised category in normalised text
    /// 2. Alias/keyword match (single word or multi-word phrase)
    /// 3. N-gram sliding window with fuzzy Levenshtein matching
    private static func extractCategory(from text: String, fullText: String) -> (match: String?, suggestions: [String]) {

        // ── Pass 1: Exact substring match (normalised) ──
        // Check longest categories first so "wood fired pizza" beats "pizza"
        let sortedCats = normalizedCategories.sorted { $0.normalized.count > $1.normalized.count }
        for cat in sortedCats {
            if text.contains(cat.normalized) || fullText.contains(cat.normalized) {
                return (cat.original, [])
            }
        }

        // ── Pass 2: Alias / keyword match ──
        // Build n-grams from the text (1–4 words) and check against alias map
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        for windowSize in stride(from: min(4, words.count), through: 1, by: -1) {
            for startIdx in 0...(words.count - windowSize) {
                let phrase = words[startIdx..<(startIdx + windowSize)].joined(separator: " ")
                if let match = categoryAliases[phrase] {
                    return (match, [])
                }
            }
        }

        // ── Pass 3: Fuzzy n-gram matching ──
        // Compare every 1–3 word window from the transcript against every
        // normalised category name using Levenshtein distance.
        var best: String? = nil
        var bestScore = Int.max
        var suggestions: [String] = []

        for cat in normalizedCategories {
            let catWords = cat.normalized.components(separatedBy: " ")
            let catWordCount = catWords.count

            // Try matching n-grams of the same word count as the category
            for windowSize in [catWordCount, 1] {
                guard windowSize <= words.count else { continue }
                for startIdx in 0...(words.count - windowSize) {
                    let phrase = words[startIdx..<(startIdx + windowSize)].joined(separator: " ")
                    guard phrase.count >= 3 else { continue }

                    let distance = levenshtein(phrase, cat.normalized)
                    // Scale threshold by category length — longer names tolerate more error
                    let threshold = max(2, cat.normalized.count / 3)

                    if distance <= threshold {
                        if !suggestions.contains(cat.original) {
                            suggestions.append(cat.original)
                        }
                        if distance < bestScore {
                            bestScore = distance
                            best = cat.original
                        }
                    }
                }
            }
        }

        // Only hard-match if very confident (≤ 30% error rate)
        let confirmed: String?
        if let best, bestScore <= 2 {
            confirmed = best
        } else if let best, let cat = normalizedCategories.first(where: { $0.original == best }),
                  Double(bestScore) / Double(cat.normalized.count) <= 0.3 {
            confirmed = best
        } else {
            confirmed = nil
        }

        let dedupedSuggestions = Array(Set(suggestions)).sorted().prefix(3).map { $0 }
        return (confirmed, dedupedSuggestions)
    }

    // MARK: - Location Extraction

    private static func extractLocation(from text: String) -> VoiceLocation? {
        // "near me" variants
        for trigger in nearMeTriggers where text.contains(trigger) {
            return .nearMe
        }

        // "[prep] [City/POI Name]" pattern — e.g., "in Calgary Alberta",
        // "near Columbus Circle in NYC". Find the LONGEST match across all
        // prepositions so "near Columbus Circle in NYC" wins over "in NYC".
        var bestMatch: (prep: String, city: String, length: Int)?

        for prep in locationPreps {
            let pattern = "\\b\(prep)\\s+([a-z][a-z\\s]{1,40})"
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                var city = match
                    .replacingOccurrences(of: "^\\w+\\s+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Strip any trailing category match from the city name
                for cat in normalizedCategories {
                    if city.hasSuffix(cat.normalized) {
                        city = city.replacingOccurrences(of: cat.normalized, with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    for (alias, _) in categoryAliases {
                        if city.hasSuffix(alias) && alias.count >= 3 {
                            city = String(city.dropLast(alias.count))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }

                let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !isKnownCategory(trimmed) {
                    let fullLength = match.count
                    if bestMatch == nil || fullLength > bestMatch!.length {
                        bestMatch = (prep: prep, city: trimmed, length: fullLength)
                    }
                }
            }
        }

        if let best = bestMatch {
            let capitalised = best.city.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            return .city(capitalised)
        }

        return nil
    }

    // MARK: - Spot Name Extraction (fallback only)

    /// Extracts a venue name from the transcript after stripping a trigger prefix.
    /// Only called as a fallback when no category or location was found, so there
    /// is no need to check `isKnownCategory` — the category extractor already
    /// failed to find anything.
    private static func extractSpotName(from text: String, raw: String) -> String? {
        for trigger in spotTriggers {
            let normalizedTrigger = normalize(trigger)
            if text.hasPrefix(normalizedTrigger + " ") {
                let name = text.replacingOccurrences(of: "^\(normalizedTrigger)\\s+", with: "",
                                                     options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                // Use original casing from raw transcript for spot names
                let rawCleaned = raw.lowercased()
                    .replacingOccurrences(of: "^\(normalizedTrigger)\\s+", with: "",
                                          options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return rawCleaned.isEmpty ? name.capitalized :
                    rawCleaned.split(separator: " ")
                        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                        .joined(separator: " ")
            }
        }
        return nil
    }

    // MARK: - Text Normalization

    /// Strips hyphens, punctuation, diacritics, and lowercases.
    /// "Wood-Fired Pizza" → "wood fired pizza"
    /// "Crème Brûlée" → "creme brulee"
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)  // é→e, ü→u
            .replacingOccurrences(of: "-", with: " ")                  // hyphens → spaces
            .replacingOccurrences(of: "'", with: "")                   // apostrophes
            .replacingOccurrences(of: "'", with: "")                   // curly apostrophes
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression) // strip other punctuation
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)        // collapse whitespace
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips location-related text from the input so it doesn't interfere
    /// with category matching. Position-independent — works whether the
    /// location is at the beginning, middle, or end of the transcript.
    /// e.g. "craft beer in calgary" → "craft beer"
    /// e.g. "in calgary pizza" → "pizza"
    private static func stripLocationText(from text: String) -> String {
        var result = text

        // Strip "near me" variants
        for trigger in nearMeTriggers {
            result = result.replacingOccurrences(of: trigger, with: "")
        }

        // Strip "[prep] [city...]" from anywhere in the text
        for prep in locationPreps {
            let pattern = "\\b\(prep)\\s+[a-z][a-z\\s]{1,40}"
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func isKnownCategory(_ text: String) -> Bool {
        let n = normalize(text)
        return normalizedCategories.contains(where: { n.contains($0.normalized) })
            || categoryAliases.keys.contains(n)
    }

    /// Classic Levenshtein distance for fuzzy category matching
    static func levenshtein(_ s: String, _ t: String) -> Int {
        let s = Array(s), t = Array(t)
        let m = s.count, n = t.count
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = s[i-1] == t[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}
