import Foundation

/// Tracks a user's contributions to the Flezcal community.
/// Rankings are computed from the spots, ratings, and verifications data.
struct ContributorStats: Identifiable {
    let id: String          // User ID
    let displayName: String
    let spotsAdded: Int     // Total locations added
    let flanSpotsAdded: Int // Flan spots added
    let mezcalSpotsAdded: Int // Mezcal spots added
    let categoriesIdentified: Int // Total food/drink categories identified across all spots
    let brandsLogged: Int   // Total unique brands/varieties contributed
    let ratingsGiven: Int
    let verificationsGiven: Int // Distinct spot/category combos verified

    /// Overall contribution score for ranking.
    /// Spot +10, Rating +5, Find (category ID) +3, Brand +1, Verify +1
    var score: Int {
        (spotsAdded * 10) + (ratingsGiven * 5) + (categoriesIdentified * 3) + (brandsLogged * 1) + (verificationsGiven * 1)
    }

    /// Contributor rank title based on score.
    /// Edit RankConfig below to rename levels without touching this logic.
    var rankTitle: String { RankConfig.title(for: score) }

    /// SF Symbol icon for the rank
    var rankIcon: String { RankConfig.icon(for: score) }

    /// Whether the user has earned the Brand Collector badge (10+ unique brands logged)
    var isBrandCollector: Bool { brandsLogged >= RankConfig.brandCollectorThreshold }
}

// MARK: - Rank Configuration
// ✏️ Edit the titles and icons here to change leaderboard rank names app-wide.

enum RankConfig {
    // Score thresholds: (minScore, title, sfSymbol)
    static let levels: [(minScore: Int, title: String, icon: String)] = [
        (0,   "Turista",       "figure.walk"),
        (1,   "Chilango",      "binoculars"),
        (20,  "Flanático",     "fork.knife"),
        (50,  "Mezcalero",     "flame"),
        (100, "Conocedor",     "star.circle"),
        (200, "Leyenda CDMX",  "star.circle.fill"),
        (500, "Inmortal",      "crown.fill"),
    ]

    // Brand Collector badge threshold — edit here to change the requirement
    static let brandCollectorThreshold = 10

    static func title(for score: Int) -> String {
        levels.last(where: { score >= $0.minScore })?.title ?? levels[0].title
    }

    static func icon(for score: Int) -> String {
        levels.last(where: { score >= $0.minScore })?.icon ?? levels[0].icon
    }
}

/// Builds contributor stats from the existing spots, ratings, and verifications data.
enum ContributorStatsBuilder {

    /// Build stats for all contributors from spots, ratings, and verifications.
    /// Pass a `userNames` dict (userID → display name) built from ratings to show real names.
    /// Ratings are counted from both legacy reviews AND verification.rating, deduplicated
    /// per user + spotID + category to avoid double-counting.
    static func buildAll(spots: [Spot], reviews: [Review], verifications: [Verification] = [], userNames: [String: String] = [:]) -> [ContributorStats] {
        // Group spots by user — exclude imported/seeded spots (source != nil)
        var userSpots: [String: [Spot]] = [:]
        for spot in spots where !spot.isHidden && spot.source == nil {
            userSpots[spot.addedByUserID, default: []].append(spot)
        }

        // Count ratings from both sources, deduplicated per user+spot+category
        var userRatingKeys: [String: Set<String>] = [:]  // userID → set of "spotID_category"
        for review in reviews where !review.isHidden {
            let key = "\(review.spotID)_\(review.category ?? "legacy")"
            userRatingKeys[review.userID, default: []].insert(key)
        }
        for verification in verifications where verification.rating != nil {
            let key = "\(verification.spotID)_\(verification.category)"
            userRatingKeys[verification.userID, default: []].insert(key)
        }

        // Count distinct verification combos per user (spotID + category)
        var userVerifications: [String: Set<String>] = [:]
        for verification in verifications {
            let key = "\(verification.spotID)_\(verification.category)"
            userVerifications[verification.userID, default: []].insert(key)
        }

        // Collect all user IDs — exclude the import script sentinel
        let excludedUserIDs: Set<String> = ["IMPORT_SCRIPT"]
        let allUserIDs = Set(userSpots.keys).union(userRatingKeys.keys).union(userVerifications.keys)
            .subtracting(excludedUserIDs)

        // Build stats for each user
        var allStats: [ContributorStats] = []
        for userID in allUserIDs {
            let spots = userSpots[userID] ?? []
            let flanCount = spots.filter { $0.hasFlan }.count
            let mezcalCount = spots.filter { $0.hasMezcal }.count

            // Count total category identifications (sum of categories.count per spot)
            let totalCategories = spots.reduce(0) { $0 + $1.categories.count }

            // Count unique brands/varieties across all categories
            var uniqueBrands: Set<String> = []
            for spot in spots {
                if let allOfferings = spot.offerings {
                    for (_, items) in allOfferings {
                        for item in items {
                            uniqueBrands.insert(item.lowercased())
                        }
                    }
                }
            }

            let displayName = userNames[userID] ?? "Contributor"

            allStats.append(ContributorStats(
                id: userID,
                displayName: displayName,
                spotsAdded: spots.count,
                flanSpotsAdded: flanCount,
                mezcalSpotsAdded: mezcalCount,
                categoriesIdentified: totalCategories,
                brandsLogged: uniqueBrands.count,
                ratingsGiven: userRatingKeys[userID]?.count ?? 0,
                verificationsGiven: userVerifications[userID]?.count ?? 0
            ))
        }

        // Filter out zero-score entries and orphaned UIDs (no resolved name AND no user-added spots)
        return allStats
            .filter { $0.score > 0 && !($0.displayName == "Contributor" && $0.spotsAdded == 0) }
            .sorted { $0.score > $1.score }
    }

    /// Build stats for a specific user.
    /// Ratings are counted from both legacy reviews AND verification.rating,
    /// deduplicated per spotID + category.
    static func buildForUser(userID: String, spots: [Spot], reviews: [Review], verifications: [Verification] = [], displayName: String) -> ContributorStats {
        let userSpots = spots.filter { $0.addedByUserID == userID && !$0.isHidden && $0.source == nil }
        let flanCount = userSpots.filter { $0.hasFlan }.count
        let mezcalCount = userSpots.filter { $0.hasMezcal }.count

        // Count ratings from both sources, deduplicated
        var ratingKeys: Set<String> = []
        for review in reviews where review.userID == userID && !review.isHidden {
            ratingKeys.insert("\(review.spotID)_\(review.category ?? "legacy")")
        }
        for v in verifications where v.userID == userID && v.rating != nil {
            ratingKeys.insert("\(v.spotID)_\(v.category)")
        }

        // Count total category identifications
        let totalCategories = userSpots.reduce(0) { $0 + $1.categories.count }

        // Count unique brands/varieties across all categories
        var uniqueBrands: Set<String> = []
        for spot in userSpots {
            if let allOfferings = spot.offerings {
                for (_, items) in allOfferings {
                    for item in items {
                        uniqueBrands.insert(item.lowercased())
                    }
                }
            }
        }

        // Count distinct verification combos
        var verificationKeys: Set<String> = []
        for v in verifications where v.userID == userID {
            verificationKeys.insert("\(v.spotID)_\(v.category)")
        }

        return ContributorStats(
            id: userID,
            displayName: displayName,
            spotsAdded: userSpots.count,
            flanSpotsAdded: flanCount,
            mezcalSpotsAdded: mezcalCount,
            categoriesIdentified: totalCategories,
            brandsLogged: uniqueBrands.count,
            ratingsGiven: ratingKeys.count,
            verificationsGiven: verificationKeys.count
        )
    }

    /// Get the rank position (1-based) for a specific user
    static func rankPosition(userID: String, allStats: [ContributorStats]) -> Int? {
        guard let index = allStats.firstIndex(where: { $0.id == userID }) else { return nil }
        return index + 1
    }
}
