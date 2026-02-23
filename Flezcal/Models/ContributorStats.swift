import Foundation

/// Tracks a user's contributions to the Flezcal community.
/// Rankings are computed from the spots collection data.
struct ContributorStats: Identifiable {
    let id: String          // User ID
    let displayName: String
    let spotsAdded: Int     // Total locations added
    let flanSpotsAdded: Int // Flan spots added
    let mezcalSpotsAdded: Int // Mezcal spots added
    let mezcalBrandsAdded: Int // Total unique mezcal brands contributed
    let reviewsWritten: Int

    /// Overall contribution score for ranking.
    /// Each spot = 10 points, each mezcal brand = 3 points, each review = 5 points.
    var score: Int {
        (spotsAdded * 10) + (mezcalBrandsAdded * 3) + (reviewsWritten * 5)
    }

    /// Contributor rank title based on score.
    /// Edit RankConfig below to rename levels without touching this logic.
    var rankTitle: String { RankConfig.title(for: score) }

    /// SF Symbol icon for the rank
    var rankIcon: String { RankConfig.icon(for: score) }

    /// Whether the user has earned the Brand Collector badge (10+ unique mezcal brands)
    var isBrandCollector: Bool { mezcalBrandsAdded >= RankConfig.brandCollectorThreshold }
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

/// Builds contributor stats from the existing spots and reviews data.
enum ContributorStatsBuilder {

    /// Build stats for all contributors from spots and reviews.
    /// Pass a `userNames` dict (userID → display name) built from reviews to show real names.
    static func buildAll(spots: [Spot], reviews: [Review], userNames: [String: String] = [:]) -> [ContributorStats] {
        // Group spots by user
        var userSpots: [String: [Spot]] = [:]
        for spot in spots where !spot.isHidden {
            userSpots[spot.addedByUserID, default: []].append(spot)
        }

        // Group reviews by user
        var userReviews: [String: Int] = [:]
        for review in reviews where !review.isHidden {
            userReviews[review.userID, default: 0] += 1
        }

        // Collect all user IDs
        let allUserIDs = Set(userSpots.keys).union(userReviews.keys)

        // Build stats for each user
        var allStats: [ContributorStats] = []
        for userID in allUserIDs {
            let spots = userSpots[userID] ?? []
            let flanCount = spots.filter { $0.hasFlan }.count
            let mezcalCount = spots.filter { $0.hasMezcal }.count

            // Count unique mezcal brands this user contributed
            var uniqueBrands: Set<String> = []
            for spot in spots {
                if let offerings = spot.mezcalOfferings {
                    for brand in offerings {
                        uniqueBrands.insert(brand.lowercased())
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
                mezcalBrandsAdded: uniqueBrands.count,
                reviewsWritten: userReviews[userID] ?? 0
            ))
        }

        // Sort by score descending
        return allStats.sorted { $0.score > $1.score }
    }

    /// Build stats for a specific user
    static func buildForUser(userID: String, spots: [Spot], reviews: [Review], displayName: String) -> ContributorStats {
        let userSpots = spots.filter { $0.addedByUserID == userID && !$0.isHidden }
        let flanCount = userSpots.filter { $0.hasFlan }.count
        let mezcalCount = userSpots.filter { $0.hasMezcal }.count
        let reviewCount = reviews.filter { $0.userID == userID && !$0.isHidden }.count

        var uniqueBrands: Set<String> = []
        for spot in userSpots {
            if let offerings = spot.mezcalOfferings {
                for brand in offerings {
                    uniqueBrands.insert(brand.lowercased())
                }
            }
        }

        return ContributorStats(
            id: userID,
            displayName: displayName,
            spotsAdded: userSpots.count,
            flanSpotsAdded: flanCount,
            mezcalSpotsAdded: mezcalCount,
            mezcalBrandsAdded: uniqueBrands.count,
            reviewsWritten: reviewCount
        )
    }

    /// Get the rank position (1-based) for a specific user
    static func rankPosition(userID: String, allStats: [ContributorStats]) -> Int? {
        guard let index = allStats.firstIndex(where: { $0.id == userID }) else { return nil }
        return index + 1
    }
}
