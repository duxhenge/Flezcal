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

    /// Maximum custom picks a user can create per session.
    static let maxCustomPicks = 3

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
        }
        isLoading = false
    }

    // MARK: - Create or increment pick count

    /// Creates a new custom category if it doesn't exist, or increments its pickCount.
    /// Returns the FoodCategory representation for use in the pick system.
    func createOrIncrement(_ category: CustomCategory) async -> FoodCategory? {
        let docRef = db.collection(Self.collectionName).document(category.normalizedName)

        do {
            let doc = try await docRef.getDocument()
            if doc.exists {
                // Already exists — increment pickCount
                try await docRef.updateData(["pickCount": FieldValue.increment(Int64(1))])
                if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
                    customCategories[index].pickCount += 1
                }
            } else {
                // New — create with pickCount = 1
                var newCat = category
                newCat.pickCount = 1
                try docRef.setData(from: newCat)
                customCategories.insert(newCat, at: 0)
            }
            return category.toFoodCategory()
        } catch {
            errorMessage = "Failed to save custom category: \(error.localizedDescription)"
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
}
