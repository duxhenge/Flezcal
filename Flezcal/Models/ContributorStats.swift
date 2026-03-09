import Foundation

/// Tracks a user's contributions to the Flezcal community.
/// Rankings are computed from the spots, ratings, and verifications data.
struct ContributorStats: Identifiable {
    let id: String          // User ID
    let displayName: String
    let spotsAdded: Int     // Total locations added
    let categoryCounts: [String: Int] // Per-category spot counts (keyed by SpotCategory rawValue)
    let categoriesIdentified: Int // Total food/drink categories identified across all spots
    let brandsLogged: Int   // Total unique brands/varieties contributed
    let ratingsGiven: Int
    let verificationsGiven: Int // Distinct spot/category combos verified

    /// Overall contribution score for ranking.
    /// Spot +10, Rating +5, Find (category ID) +3, Brand +1, Verify +1
    var score: Int {
        (spotsAdded * 10) + (ratingsGiven * 5) + (categoriesIdentified * 3) + (brandsLogged * 1) + (verificationsGiven * 1)
    }

    /// The user's percentile within the community (0.0 = top, 1.0 = bottom).
    /// Set by `ContributorStatsBuilder.assignPercentiles()` after building all stats.
    var percentile: Double = 1.0

    /// Contributor rank title based on percentile within the community.
    /// Shows "New" when the community is too small for percentile ranking.
    var rankTitle: String { RankConfig.title(forPercentile: percentile, score: score) }

    /// SF Symbol icon for the rank
    var rankIcon: String { RankConfig.icon(forPercentile: percentile, score: score) }

    /// Whether the user has earned the Brand Collector badge (10+ unique brands logged)
    var isBrandCollector: Bool { brandsLogged >= RankConfig.brandCollectorThreshold }

    /// Returns the user's top N categories by count, sorted descending.
    /// Each element is (categoryID, count). Useful for profile/leaderboard display.
    func topCategories(_ n: Int = 3) -> [(id: String, count: Int)] {
        categoryCounts
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { (id: $0.key, count: $0.value) }
    }

    /// Convenience: count for a specific category
    func count(for categoryID: String) -> Int {
        categoryCounts[categoryID] ?? 0
    }
}

// MARK: - Rank Configuration
// Percentile-based ranking — ranks are determined by where a user falls
// relative to all contributors, not by fixed point thresholds.
//
// Pepper heat scale (top → bottom):
//   Ghost Pepper   — Top 10%
//   Habanero       — Next 20%  (top 10–30%)
//   Serrano        — Next 20%  (top 30–50%)
//   Jalapeño       — Next 20%  (top 50–70%)
//   Poblano        — Next 20%  (top 70–90%)
//   Bell Pepper    — Bottom 10%

enum RankConfig {

    /// Minimum contributors needed before percentile ranking kicks in.
    /// Below this threshold, everyone with score > 0 is ranked "New".
    static let minimumForPercentiles = 20

    /// The "New" rank shown when the community is too small for percentile ranking.
    static let newRank: (title: String, icon: String, cumulativePct: Double) =
        ("New", "sparkles", 1.0)

    /// Rank levels ordered from highest to lowest.
    /// `cumulativePct` = the cumulative % from the top that this tier covers.
    /// e.g. Ghost Pepper covers the top 10%, Habanero the next 20% (top 10–30%).
    static let levels: [(title: String, icon: String, cumulativePct: Double)] = [
        ("Ghost Pepper",  "flame.fill",          0.10),  // Top 10%
        ("Habanero",      "flame",               0.30),  // Next 20%
        ("Serrano",       "bolt.fill",           0.50),  // Next 20%
        ("Jalapeño",      "leaf.fill",           0.70),  // Next 20%
        ("Poblano",       "leaf",                0.90),  // Next 20%
        ("Bell Pepper",   "carrot.fill",         1.00),  // Bottom 10%
    ]

    // Brand Collector badge threshold — edit here to change the requirement
    static let brandCollectorThreshold = 10

    /// Whether the community is large enough for percentile ranking.
    static var isPercentileActive: Bool { _communitySize >= minimumForPercentiles }

    /// Stored community size — set by `assignPercentiles()`.
    /// Used by UI to decide whether to show percentile info or "New" badge.
    nonisolated(unsafe) private(set) static var _communitySize: Int = 0

    /// Update the stored community size. Called by ContributorStatsBuilder.
    static func setCommunitySize(_ count: Int) {
        _communitySize = count
    }

    /// The lowest rank level (Bell Pepper). Used as fallback for score == 0.
    private static let bottomLevel = levels[levels.count - 1]

    /// Determine rank level index from a percentile (0.0 = top, 1.0 = bottom).
    static func levelIndex(forPercentile pct: Double) -> Int {
        for (i, level) in levels.enumerated() where pct <= level.cumulativePct {
            return i
        }
        return levels.count - 1
    }

    /// Returns rank title for a given percentile.
    /// When community is too small, returns "New" for anyone with score > 0.
    static func title(forPercentile pct: Double, score: Int = 1) -> String {
        guard score > 0 else { return bottomLevel.title }
        guard isPercentileActive else { return newRank.title }
        return levels[levelIndex(forPercentile: pct)].title
    }

    /// Returns rank icon for a given percentile.
    static func icon(forPercentile pct: Double, score: Int = 1) -> String {
        guard score > 0 else { return bottomLevel.icon }
        guard isPercentileActive else { return newRank.icon }
        return levels[levelIndex(forPercentile: pct)].icon
    }

    /// Returns the current rank level tuple for a given percentile.
    static func currentLevel(forPercentile pct: Double, score: Int = 1) -> (title: String, icon: String, cumulativePct: Double) {
        guard score > 0 else { return bottomLevel }
        guard isPercentileActive else { return newRank }
        return levels[levelIndex(forPercentile: pct)]
    }

    /// Returns the next rank level tuple (one tier higher), or nil if already at top.
    /// Returns nil when community is too small (can't progress through percentile tiers yet).
    static func nextLevel(forPercentile pct: Double, score: Int = 1) -> (title: String, icon: String, cumulativePct: Double)? {
        guard score > 0, isPercentileActive else { return nil }
        let idx = levelIndex(forPercentile: pct)
        guard idx > 0 else { return nil }
        return levels[idx - 1]
    }

    /// Compute the percentile for a specific user within a sorted (descending) list of all scores.
    /// Returns a value from 0.0 (best) to 1.0 (worst).
    /// Users with score == 0 always return 1.0 (bottom tier).
    static func percentile(forUserScore score: Int, allScoresSorted: [Int]) -> Double {
        guard score > 0 else { return 1.0 }
        let total = allScoresSorted.count
        guard total > 0 else { return 1.0 }
        // Position: how many users are ranked above this user (0-based from top)
        // For tied scores, use the first occurrence (best possible rank)
        let position = allScoresSorted.firstIndex(where: { $0 <= score }) ?? total
        return Double(position) / Double(total)
    }
}

/// Builds contributor stats from the existing spots, ratings, and verifications data.
enum ContributorStatsBuilder {

    /// Build stats for all contributors from spots, ratings, and verifications.
    /// Pass a `userNames` dict (userID → display name) built from ratings to show real names.
    /// Ratings are counted from both legacy reviews AND verification.rating, deduplicated
    /// per user + spotID + category to avoid double-counting.
    static func buildAll(spots: [Spot], reviews: [Review], verifications: [Verification] = [], userNames: [String: String] = [:]) -> [ContributorStats] {
        let validSpots = spots.filter { !$0.isHidden && $0.source == nil }

        // Group spots by creator (for spotsAdded count)
        var userCreatedSpots: [String: [Spot]] = [:]
        for spot in validSpots {
            userCreatedSpots[spot.addedByUserID, default: []].append(spot)
        }

        // Per-category attribution: count categories each user actually confirmed.
        // Uses categoryAddedBy when available; falls back to addedByUserID for legacy spots.
        var userCategoryCount: [String: Int] = [:]
        var userCategoryCounts: [String: [String: Int]] = [:]  // userID → [categoryID: count]
        var userBrands: [String: Set<String>] = [:]

        for spot in validSpots {
            for category in spot.categories {
                let attributedUser = spot.categoryAddedBy?[category.rawValue] ?? spot.addedByUserID
                userCategoryCount[attributedUser, default: 0] += 1
                userCategoryCounts[attributedUser, default: [:]][category.rawValue, default: 0] += 1
            }
            // Brands are attributed to the spot creator (they entered the offerings)
            if let allOfferings = spot.offerings {
                for (_, items) in allOfferings {
                    for item in items {
                        userBrands[spot.addedByUserID, default: []].insert(item.lowercased())
                    }
                }
            }
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
        let allUserIDs = Set(userCreatedSpots.keys)
            .union(userCategoryCount.keys)
            .union(userRatingKeys.keys)
            .union(userVerifications.keys)
            .subtracting(excludedUserIDs)

        // Build stats for each user
        var allStats: [ContributorStats] = []
        for userID in allUserIDs {
            let displayName = userNames[userID] ?? "Contributor"

            allStats.append(ContributorStats(
                id: userID,
                displayName: displayName,
                spotsAdded: userCreatedSpots[userID]?.count ?? 0,
                categoryCounts: userCategoryCounts[userID] ?? [:],
                categoriesIdentified: userCategoryCount[userID] ?? 0,
                brandsLogged: userBrands[userID]?.count ?? 0,
                ratingsGiven: userRatingKeys[userID]?.count ?? 0,
                verificationsGiven: userVerifications[userID]?.count ?? 0
            ))
        }

        // Filter out zero-score entries and orphaned UIDs (no resolved name AND no user-added spots)
        var filtered = allStats
            .filter { $0.score > 0 && !($0.displayName == "Contributor" && $0.spotsAdded == 0) }
            .sorted { $0.score > $1.score }

        // Assign percentiles based on position in the sorted list
        assignPercentiles(&filtered)

        return filtered
    }

    /// Assigns percentile values to each contributor based on their position.
    /// Also updates `RankConfig._communitySize` so the UI knows whether
    /// percentile ranking is active or everyone should show "New".
    static func assignPercentiles(_ stats: inout [ContributorStats]) {
        let total = stats.count
        RankConfig.setCommunitySize(total)
        guard total > 0 else { return }
        let allScores = stats.map(\.score)
        for i in stats.indices {
            stats[i].percentile = RankConfig.percentile(
                forUserScore: stats[i].score,
                allScoresSorted: allScores
            )
        }
    }

    /// Build stats for a specific user.
    /// Ratings are counted from both legacy reviews AND verification.rating,
    /// deduplicated per spotID + category.
    static func buildForUser(userID: String, spots: [Spot], reviews: [Review], verifications: [Verification] = [], displayName: String) -> ContributorStats {
        let validSpots = spots.filter { !$0.isHidden && $0.source == nil }
        let userCreatedSpots = validSpots.filter { $0.addedByUserID == userID }

        // Per-category attribution: count only categories this user actually confirmed.
        // Uses categoryAddedBy when available; falls back to addedByUserID for legacy spots.
        var totalCategories = 0
        var perCategoryCounts: [String: Int] = [:]

        for spot in validSpots {
            for category in spot.categories {
                let attributedUser = spot.categoryAddedBy?[category.rawValue] ?? spot.addedByUserID
                if attributedUser == userID {
                    totalCategories += 1
                    perCategoryCounts[category.rawValue, default: 0] += 1
                }
            }
        }

        // Count ratings from both sources, deduplicated
        var ratingKeys: Set<String> = []
        for review in reviews where review.userID == userID && !review.isHidden {
            ratingKeys.insert("\(review.spotID)_\(review.category ?? "legacy")")
        }
        for v in verifications where v.userID == userID && v.rating != nil {
            ratingKeys.insert("\(v.spotID)_\(v.category)")
        }

        // Count unique brands/varieties (attributed to spot creator)
        var uniqueBrands: Set<String> = []
        for spot in userCreatedSpots {
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
            spotsAdded: userCreatedSpots.count,
            categoryCounts: perCategoryCounts,
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

    /// Assigns the correct percentile to a single-user stat using the full leaderboard.
    static func assignPercentile(to stats: inout ContributorStats, using allStats: [ContributorStats]) {
        let allScores = allStats.map(\.score)
        stats.percentile = RankConfig.percentile(
            forUserScore: stats.score,
            allScoresSorted: allScores
        )
    }
}
