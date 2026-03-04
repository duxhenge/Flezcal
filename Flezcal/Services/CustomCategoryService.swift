import Foundation
import FirebaseFirestore

/// Manages user-created food categories.
///
/// Custom categories are stored in Firestore at `customCategories/{normalizedName}`.
/// Each user can create up to 3 custom picks per session, stored locally in UserDefaults.
/// Firestore tracks global popularity (pickCount) for future promotion/relegation.
@MainActor
class CustomCategoryService: ObservableObject {
    @Published var customCategories: [CustomCategory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private static let collectionName = "customCategories"
    private static let eventsCollection = "customSearchEvents"

    /// Maximum custom picks a user can create per session.
    /// Controlled by FeatureFlags.maxCustomItems (1 at launch, 3 in Phase 4).
    static var maxCustomPicks: Int { FeatureFlags.maxCustomItems }

    // MARK: - Fetch all custom categories

    func fetchAll() async {
        isLoading = true
        do {
            let snapshot = try await db.collection(Self.collectionName)
                .order(by: "pickCount", descending: true)
                .limit(to: 100)
                .getDocuments()

            customCategories = snapshot.documents.compactMap { doc in
                try? doc.data(as: CustomCategory.self)
            }
        } catch {
            errorMessage = "Failed to load custom categories: \(error.localizedDescription)"
            CrashReporter.record(error, context: "CustomCategoryService.fetchAll")
        }
        isLoading = false
    }

    // MARK: - Create or increment pick count

    /// Creates a new custom category if it doesn't exist, or increments its pickCount.
    /// Uses a `pickers` subcollection to deduplicate — each user only counts once
    /// toward `pickCount`, no matter how many times they re-pick the same term.
    /// Also logs a timestamped search event for trend tracking.
    ///
    /// Blocked terms (offensive, non-food) silently skip Firestore writes but still
    /// return a valid FoodCategory so the user's local UI works normally. The term
    /// is never persisted, tracked, or visible to other users.
    /// Returns the FoodCategory representation for use in the pick system.
    func createOrIncrement(_ category: CustomCategory) async -> FoodCategory? {
        // Silently skip Firestore for blocked terms — UI works normally but
        // nothing is persisted, tracked, or visible to other users.
        guard !CustomCategory.isBlocked(category.normalizedName) else {
            return category.toFoodCategory()
        }

        let docRef = db.collection(Self.collectionName).document(category.normalizedName)
        let pickerRef = docRef.collection("pickers").document(category.createdBy)

        do {
            let doc = try await docRef.getDocument()
            if doc.exists {
                // Already exists — only increment if this user hasn't picked before
                let pickerDoc = try await pickerRef.getDocument()
                if !pickerDoc.exists {
                    try await docRef.updateData(["pickCount": FieldValue.increment(Int64(1))])
                    try await pickerRef.setData(["pickedDate": FieldValue.serverTimestamp()])
                    if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
                        customCategories[index].pickCount += 1
                    }
                }
            } else {
                // New — create with pickCount = 1 and record this user as first picker
                var newCat = category
                newCat.pickCount = 1
                try docRef.setData(from: newCat)
                try await pickerRef.setData(["pickedDate": FieldValue.serverTimestamp()])
                customCategories.insert(newCat, at: 0)
            }

            // Log a timestamped event for trend tracking.
            // Fire-and-forget — don't block the pick flow if this fails.
            logSearchEvent(term: category.normalizedName, userID: category.createdBy)

            return category.toFoodCategory()
        } catch {
            errorMessage = "Failed to save custom category: \(error.localizedDescription)"
            CrashReporter.record(error, context: "CustomCategoryService.createOrIncrement")
            return nil
        }
    }

    // MARK: - Lookup

    /// Returns an existing custom category by normalized name, or nil.
    func find(_ name: String) -> CustomCategory? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        return customCategories.first { $0.normalizedName == normalized }
    }

    /// Returns the most popular custom categories (candidates for promotion).
    func topCandidates(limit: Int = 10) -> [CustomCategory] {
        Array(customCategories.sorted { $0.pickCount > $1.pickCount }.prefix(limit))
    }

    // MARK: - Trend Tracking

    /// Logs a timestamped search event to `customSearchEvents`.
    /// Used for identifying trending custom categories over time.
    /// Fire-and-forget — failures are logged but don't affect the user flow.
    private func logSearchEvent(term: String, userID: String) {
        let data: [String: Any] = [
            "term": term,
            "userID": userID,
            "timestamp": FieldValue.serverTimestamp(),
        ]
        db.collection(Self.eventsCollection).addDocument(data: data) { error in
            #if DEBUG
            if let error {
                print("[CustomCategory] search event log failed: \(error.localizedDescription)")
            }
            #endif
        }
    }

    /// Returns custom category terms picked within the given time window,
    /// sorted by frequency (most popular first). Useful for identifying
    /// trending terms for promotion to hardcoded categories.
    func trendingTerms(since date: Date, limit: Int = 20) async -> [(term: String, count: Int)] {
        do {
            let snapshot = try await db.collection(Self.eventsCollection)
                .whereField("timestamp", isGreaterThan: Timestamp(date: date))
                .getDocuments()

            var counts: [String: Int] = [:]
            for doc in snapshot.documents {
                if let term = doc.data()["term"] as? String {
                    counts[term, default: 0] += 1
                }
            }

            return counts
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map { (term: $0.key, count: $0.value) }
        } catch {
            #if DEBUG
            print("[CustomCategory] trending query failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }
}
