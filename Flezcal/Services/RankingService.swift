import Foundation
import FirebaseFirestore

/// Fetches and caches category rankings from Firestore `app_config/flezcal_rankings`.
/// Provides tier lookups (Top 50 vs Trending) consumed by FoodCategoryGridView.
///
/// **Offline fallback:** If the document doesn't exist or fetch fails, all 50 built-in
/// category IDs are Top 50 and everything else is Trending. This ensures the app works
/// identically to pre-ranking behavior when offline or before the first admin recompute.
@MainActor
final class RankingService: ObservableObject {

    // MARK: - Published state

    /// Ordered list of ranked categories (Top 50 first, then Trending).
    @Published var rankings: [RankedCategory] = []

    /// IDs in the Top 50 tier (fast lookup).
    @Published var top50IDs: Set<String> = Set(FoodCategory.allCategories.map(\.id))

    /// IDs in the Trending tier (fast lookup).
    @Published var trendingIDs: Set<String> = []

    /// When the rankings were last recomputed by admin.
    @Published var lastUpdated: Date?

    /// True while the initial fetch is in progress.
    @Published var isLoading = false

    // MARK: - Private

    private let db = Firestore.firestore()

    // MARK: - Tier queries

    func isTop50(_ id: String) -> Bool { top50IDs.contains(id) }
    func isTrending(_ id: String) -> Bool { trendingIDs.contains(id) }

    /// Returns the tier for a category ID. Defaults to `.trending` for unknown IDs.
    func tier(for id: String) -> RankedCategory.Tier {
        if top50IDs.contains(id) { return .top50 }
        return .trending
    }

    // MARK: - Fetch from Firestore

    /// One-shot fetch of the rankings document. Called from ContentView `.task`.
    func fetchRankings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let doc = try await db.collection(FirestoreCollections.appConfig)
                .document(FirestoreCollections.flezcalRankings)
                .getDocument()

            guard let data = doc.data() else {
                // Document doesn't exist yet — keep hardcoded defaults.
                return
            }

            // Parse top50 and trending ID arrays
            let top50 = data["top50"] as? [String] ?? []
            let trending = data["trending"] as? [String] ?? []

            // Parse the full rankings array
            var parsed: [RankedCategory] = []
            if let rankingsData = data["rankings"] as? [[String: Any]] {
                for entry in rankingsData {
                    guard let categoryID = entry["categoryID"] as? String,
                          let displayName = entry["displayName"] as? String else { continue }
                    let rank = entry["rank"] as? Int ?? 0
                    let pickCount = entry["pickCount"] as? Int ?? 0
                    let tierStr = entry["tier"] as? String ?? "trending"
                    let isCustom = entry["isCustom"] as? Bool ?? false
                    let emoji = entry["emoji"] as? String ?? ""
                    parsed.append(RankedCategory(
                        categoryID: categoryID,
                        displayName: displayName,
                        emoji: emoji,
                        rank: rank,
                        pickCount: pickCount,
                        tier: tierStr == "top50" ? .top50 : .trending,
                        isCustom: isCustom
                    ))
                }
            }

            if let ts = data["lastUpdated"] as? Timestamp {
                lastUpdated = ts.dateValue()
            }

            // Only apply Firestore data if we got valid arrays.
            // Empty top50 means the doc was created but not populated yet.
            if !top50.isEmpty {
                top50IDs = Set(top50)
                trendingIDs = Set(trending)
                rankings = parsed
            }
        } catch {
            // Fetch failed (offline, permissions, etc.) — keep hardcoded defaults.
            #if DEBUG
            print("[RankingService] fetchRankings failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Admin: Compute and save rankings

    /// Recomputes rankings from pick data and writes to Firestore.
    /// Called from AdminRankingsView. Returns the computed rankings for display.
    func computeAndSaveRankings(
        builtInCounts: [String: Int],
        customCounts: [String: Int],
        customCategories: [CustomCategory]
    ) async throws -> [RankedCategory] {
        // Build unified list: built-in + custom
        var all: [RankedCategory] = []

        // Built-in categories
        for cat in FoodCategory.allCategories {
            let count = builtInCounts[cat.id] ?? 0
            all.append(RankedCategory(
                categoryID: cat.id,
                displayName: cat.displayName,
                emoji: cat.emoji,
                rank: 0,
                pickCount: count,
                tier: .top50,
                isCustom: false
            ))
        }

        // Custom categories
        for custom in customCategories {
            let count = customCounts[custom.normalizedName] ?? 0
            all.append(RankedCategory(
                categoryID: "custom_\(custom.normalizedName)",
                displayName: custom.displayName,
                emoji: custom.emoji,
                rank: 0,
                pickCount: count,
                tier: .trending,
                isCustom: true
            ))
        }

        // Sort by pick count descending, then alphabetically for ties
        all.sort { lhs, rhs in
            if lhs.pickCount != rhs.pickCount { return lhs.pickCount > rhs.pickCount }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        // Assign ranks and tiers: top 50 → .top50, rest → .trending
        var top50: [String] = []
        var trending: [String] = []
        for i in all.indices {
            all[i].rank = i + 1
            if i < 50 {
                all[i].tier = .top50
                top50.append(all[i].categoryID)
            } else {
                all[i].tier = .trending
                trending.append(all[i].categoryID)
            }
        }

        // Build Firestore document
        let rankingsData: [[String: Any]] = all.map { entry in
            [
                "categoryID": entry.categoryID,
                "displayName": entry.displayName,
                "emoji": entry.emoji,
                "rank": entry.rank,
                "pickCount": entry.pickCount,
                "tier": entry.tier == .top50 ? "top50" : "trending",
                "isCustom": entry.isCustom,
            ]
        }

        let docData: [String: Any] = [
            "lastUpdated": FieldValue.serverTimestamp(),
            "rankings": rankingsData,
            "top50": top50,
            "trending": trending,
        ]

        try await db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.flezcalRankings)
            .setData(docData)

        // Update local state
        rankings = all
        top50IDs = Set(top50)
        trendingIDs = Set(trending)

        return all
    }
}

// MARK: - RankedCategory model

struct RankedCategory: Identifiable {
    let categoryID: String
    let displayName: String
    let emoji: String
    var rank: Int
    let pickCount: Int
    var tier: Tier
    let isCustom: Bool

    var id: String { categoryID }

    enum Tier: String {
        case top50
        case trending
    }
}
