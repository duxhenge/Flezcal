import Foundation
import FirebaseFirestore

/// Manages user-created (trending) food categories.
///
/// Custom categories are stored in Firestore at `customCategories/{normalizedName}`.
/// Firestore tracks global popularity (pickCount) for future promotion to Top 50.
@MainActor
class CustomCategoryService: ObservableObject {
    @Published var customCategories: [CustomCategory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private static let collectionName = "customCategories"
    private static let eventsCollection = "customSearchEvents"

    // MARK: - Fetch all custom categories

    func fetchAll() async {
        isLoading = true
        do {
            let snapshot = try await db.collection(Self.collectionName)
                .order(by: "pickCount", descending: true)
                .limit(to: 100)
                .getDocuments()

            #if DEBUG
            print("[CustomCategory] fetchAll: \(snapshot.documents.count) documents in '\(Self.collectionName)' collection")
            #endif

            customCategories = snapshot.documents.compactMap { doc in
                do {
                    let cat = try doc.data(as: CustomCategory.self)
                    #if DEBUG
                    print("[CustomCategory]   Decoded: \(cat.emoji) \(cat.displayName) pickCount=\(cat.pickCount)")
                    #endif
                    return cat
                } catch {
                    #if DEBUG
                    print("[CustomCategory]   DECODE FAILED for doc '\(doc.documentID)': \(error)")
                    print("[CustomCategory]   Raw data: \(doc.data())")
                    #endif
                    return nil
                }
            }
        } catch {
            errorMessage = "Failed to load custom categories: \(error.localizedDescription)"
            CrashReporter.record(error, context: "CustomCategoryService.fetchAll")
            #if DEBUG
            print("[CustomCategory] fetchAll ERROR: \(error.localizedDescription)")
            #endif
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
        #if DEBUG
        print("[CustomCategory] createOrIncrement called: '\(category.displayName)' normalized='\(category.normalizedName)' emoji=\(category.emoji) createdBy=\(category.createdBy)")
        print("[CustomCategory]   websiteKeywords: \(category.websiteKeywords)")
        print("[CustomCategory]   mapSearchTerms: \(category.mapSearchTerms)")
        #endif

        // Silently skip Firestore for blocked terms — UI works normally but
        // nothing is persisted, tracked, or visible to other users.
        guard !CustomCategory.isBlocked(category.normalizedName) else {
            #if DEBUG
            print("[CustomCategory]   BLOCKED — skipping Firestore write")
            #endif
            return category.toFoodCategory()
        }

        let docRef = db.collection(Self.collectionName).document(category.normalizedName)
        let pickerRef = docRef.collection("pickers").document(category.createdBy)

        do {
            let doc = try await docRef.getDocument()
            if doc.exists {
                #if DEBUG
                print("[CustomCategory]   Doc EXISTS in Firestore — checking picker dedup")
                #endif
                // Already exists — only increment if this user hasn't picked before
                let pickerDoc = try await pickerRef.getDocument()
                if !pickerDoc.exists {
                    try await docRef.updateData(["pickCount": FieldValue.increment(Int64(1))])
                    try await pickerRef.setData(["pickedDate": FieldValue.serverTimestamp()])
                    if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
                        customCategories[index].pickCount += 1
                    }
                    #if DEBUG
                    print("[CustomCategory]   Incremented pickCount (new picker)")
                    #endif
                } else {
                    #if DEBUG
                    print("[CustomCategory]   User already picked this — no increment")
                    #endif
                }
            } else {
                #if DEBUG
                print("[CustomCategory]   Doc NOT found — creating NEW document")
                #endif
                // New — create with pickCount = 1 and record this user as first picker
                var newCat = category
                newCat.pickCount = 1
                try docRef.setData(from: newCat)
                try await pickerRef.setData(["pickedDate": FieldValue.serverTimestamp()])
                customCategories.insert(newCat, at: 0)
                #if DEBUG
                print("[CustomCategory]   Created successfully — pickCount=1")
                #endif
            }

            // Log a timestamped event for trend tracking.
            // Fire-and-forget — don't block the pick flow if this fails.
            logSearchEvent(term: category.normalizedName, userID: category.createdBy)

            #if DEBUG
            print("[CustomCategory]   Returning FoodCategory id=custom_\(category.normalizedName)")
            #endif
            return category.toFoodCategory()
        } catch {
            errorMessage = "Failed to save custom category: \(error.localizedDescription)"
            CrashReporter.record(error, context: "CustomCategoryService.createOrIncrement")
            #if DEBUG
            print("[CustomCategory]   ERROR: \(error.localizedDescription)")
            #endif
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

    /// Returns custom pick counts filtered by time window. Counts only pickers
    /// whose `pickedDate` falls on or after `since`. Returns results ranked by count.
    func fetchPickCounts(since: Date) async -> [(category: CustomCategory, pickCount: Int)] {
        do {
            let snapshot = try await db.collection(Self.collectionName).getDocuments()
            var results: [(category: CustomCategory, pickCount: Int)] = []

            for doc in snapshot.documents {
                guard let cat = try? doc.data(as: CustomCategory.self) else { continue }

                let pickersSnapshot = try await doc.reference.collection("pickers")
                    .whereField("pickedDate", isGreaterThanOrEqualTo: Timestamp(date: since))
                    .getDocuments()

                let count = pickersSnapshot.documents.count
                if count > 0 {
                    results.append((category: cat, pickCount: count))
                }
            }

            return results.sorted { $0.pickCount > $1.pickCount }
        } catch {
            #if DEBUG
            print("[CustomCategory] fetchPickCounts(since:) error: \(error.localizedDescription)")
            #endif
            return []
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
