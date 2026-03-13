import Foundation
import FirebaseFirestore
import Combine

/// Per-category search term override loaded from Firestore.
/// Nil fields mean "keep the hardcoded default."
struct CategoryTermOverride {
    let mapSearchTerms: [String]?
    let websiteKeywords: [String]?
    let relatedKeywords: [String]?
}

/// Reads admin search-term overrides from Firestore `app_config/search_term_overrides`.
/// Uses a snapshot listener for real-time updates (no app restart needed).
/// Fail-closed: if Firestore is unavailable, all categories use hardcoded defaults.
@MainActor
final class SearchTermOverrideService: ObservableObject {
    static let shared = SearchTermOverrideService()

    /// Category ID → override data. Empty dict = no overrides (fail-closed).
    @Published private(set) var overrides: [String: CategoryTermOverride] = [:] {
        didSet { Self.overridesSnapshot = overrides }
    }

    /// Thread-safe snapshot for use from non-MainActor contexts (e.g. SpotCategory.websiteKeywords).
    nonisolated(unsafe) private(set) static var overridesSnapshot: [String: CategoryTermOverride] = [:]

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        listener = db.collection("app_config").document(FirestoreCollections.searchTermOverrides)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    #if DEBUG
                    print("[TermOverrides] Listener error: \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let data = snapshot?.data() else {
                    #if DEBUG
                    print("[TermOverrides] No document found. Using hardcoded defaults.")
                    #endif
                    Task { @MainActor in self.overrides = [:] }
                    return
                }

                var parsed: [String: CategoryTermOverride] = [:]
                for (key, value) in data {
                    // Skip metadata fields
                    guard key != "updatedAt" else { continue }
                    guard let dict = value as? [String: Any] else { continue }

                    let mapTerms = dict["mapSearchTerms"] as? [String]
                    let webKeys = dict["websiteKeywords"] as? [String]
                    let related = dict["relatedKeywords"] as? [String]

                    // Only store if at least one field is present
                    if mapTerms != nil || webKeys != nil || related != nil {
                        parsed[key] = CategoryTermOverride(
                            mapSearchTerms: mapTerms,
                            websiteKeywords: webKeys,
                            relatedKeywords: related
                        )
                    }
                }

                Task { @MainActor in
                    self.overrides = parsed
                }
                #if DEBUG
                print("[TermOverrides] Loaded \(parsed.count) override(s): \(parsed.keys.sorted().joined(separator: ", "))")
                #endif
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Apply

    /// Merges admin overrides into a FoodCategory. Nil fields fall back to the original.
    /// Checks both the exact ID and the stripped `custom_` prefix to match trending categories.
    func applyOverride(to category: FoodCategory) -> FoodCategory {
        let strippedID = category.id.hasPrefix("custom_") ? String(category.id.dropFirst(7)) : category.id
        guard let override = overrides[category.id] ?? overrides[strippedID] else { return category }
        return FoodCategory(
            id: category.id,
            displayName: category.displayName,
            emoji: category.emoji,
            color: category.color,
            mapSearchTerms: override.mapSearchTerms ?? category.mapSearchTerms,
            websiteKeywords: override.websiteKeywords ?? category.websiteKeywords,
            relatedKeywords: override.relatedKeywords ?? category.relatedKeywords,
            addSpotPrompt: category.addSpotPrompt
        )
    }

    /// Returns the canonical default FoodCategory for a given ID.
    /// Single source of truth: Firestore override > hardcoded static definition > generated fallback.
    /// Use this anywhere you need "the default terms" for a category (e.g. reset-to-defaults).
    func defaultCategory(for category: FoodCategory) -> FoodCategory {
        let strippedID = category.id.hasPrefix("custom_") ? String(category.id.dropFirst(7)) : category.id

        // 1. Check Firestore override
        if let override = overrides[category.id] ?? overrides[strippedID] {
            // Start from the hardcoded built-in if it exists, otherwise the passed-in category
            let base = FoodCategory.allKnownCategories.first(where: { $0.id == strippedID }) ?? category
            return FoodCategory(
                id: category.id,
                displayName: category.displayName,
                emoji: category.emoji,
                color: category.color,
                mapSearchTerms: override.mapSearchTerms ?? base.mapSearchTerms,
                websiteKeywords: override.websiteKeywords ?? base.websiteKeywords,
                relatedKeywords: override.relatedKeywords ?? base.relatedKeywords,
                addSpotPrompt: category.addSpotPrompt
            )
        }

        // 2. Hardcoded built-in (matches both "pierogi" and "custom_pierogi" → looks up "pierogi")
        if let builtIn = FoodCategory.allKnownCategories.first(where: { $0.id == strippedID }) {
            return FoodCategory(
                id: category.id,
                displayName: category.displayName,
                emoji: category.emoji,
                color: category.color,
                mapSearchTerms: builtIn.mapSearchTerms,
                websiteKeywords: builtIn.websiteKeywords,
                relatedKeywords: builtIn.relatedKeywords,
                addSpotPrompt: category.addSpotPrompt
            )
        }

        // 3. No override, no built-in — return as-is (truly custom category with no static match)
        return category
    }

    // MARK: - Admin writes

    /// Saves an override for a single category. Merges into the existing document.
    func saveOverride(categoryID: String, override: CategoryTermOverride) async throws {
        var data: [String: Any] = [:]
        if let terms = override.mapSearchTerms { data["mapSearchTerms"] = terms }
        if let keywords = override.websiteKeywords { data["websiteKeywords"] = keywords }
        if let related = override.relatedKeywords { data["relatedKeywords"] = related }

        try await db.collection("app_config").document(FirestoreCollections.searchTermOverrides)
            .setData([
                categoryID: data,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    /// Removes the override for a single category (reverts to hardcoded defaults).
    func removeOverride(categoryID: String) async throws {
        try await db.collection("app_config").document(FirestoreCollections.searchTermOverrides)
            .updateData([
                categoryID: FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }
}
