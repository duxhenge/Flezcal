import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Persists the user's chosen food/drink picks across app launches.
/// Picks are stored as JSON in UserDefaults for device-local use,
/// AND synced to Firestore `categoryPicks` collection for global
/// popularity tracking (admin dashboard).
///
/// Users can select up to 3 picks at a time from any combination of
/// Top 50 and trending (custom) categories. At least 1 pick must
/// remain active.
@MainActor
class UserPicksService: ObservableObject {

    /// The user's current picks (1–3). Any mix of Top 50 and trending categories.
    @Published private(set) var picks: [FoodCategory] = []

    /// Maximum picks a user can have active at once.
    static let maxPicks = 3

    /// Whether the user can add another pick.
    var canAddMore: Bool { picks.count < Self.maxPicks }

    /// Search radius in degrees. Fixed at 0.5° ≈ 35 miles. The closest-N
    /// results from MKLocalSearch naturally define the effective radius.
    let searchRadiusDegrees: Double = 0.5

    private let defaultsKey = "userFoodCategoryPicks"
    /// IDs of built-in categories whose mapSearchTerms the user intentionally
    /// customized via EditSpotSearchView. These are NOT refreshed from the
    /// static definition on load — the user's edits take precedence.
    private let customizedTermsKey = "userCustomizedTermsIDs"
    private var cancellables = Set<AnyCancellable>()

    init() {
        picks = loadPicks()
        FoodCategory.registerUserPicks(picks)
        // Clean up legacy preferences
        UserDefaults.standard.removeObject(forKey: "userSearchRadiusDegrees")
        UserDefaults.standard.removeObject(forKey: "userCustomPicks")

        // Re-apply picks when admin overrides change mid-session
        SearchTermOverrideService.shared.$overrides
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.refreshPicksFromOverrides()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Whether a given category is currently selected.
    func isSelected(_ category: FoodCategory) -> Bool {
        picks.contains(category)
    }

    /// Toggle a pick on/off.
    /// Adding: blocked at `maxPicks`. Removing: blocked at 1 pick (minimum).
    @discardableResult
    func toggle(_ category: FoodCategory) -> Bool {
        if isSelected(category) {
            guard picks.count > 1 else { return false }
            picks.removeAll { $0 == category }
        } else {
            guard canAddMore else { return false }
            picks.append(category)
        }
        savePicks()
        return true
    }

    /// Add a trending category as a pick. Same cap as Top 50 — max 3 total.
    @discardableResult
    func addCustomPick(_ category: FoodCategory) -> Bool {
        toggle(category)
    }

    /// Replace an existing pick with an updated version (e.g. edited search terms).
    /// Works for both built-in and custom picks. The old and new must have the same ID.
    /// Marks built-in categories as user-customized so their terms aren't overwritten
    /// by code updates on next load.
    /// Returns false if not found.
    @discardableResult
    func updatePick(_ updated: FoodCategory) -> Bool {
        guard let index = picks.firstIndex(where: { $0.id == updated.id }) else { return false }
        picks[index] = updated
        // Mark this built-in category as intentionally customized so loadPicks
        // won't overwrite the user's edits with the static definition.
        if !updated.id.hasPrefix("custom_") {
            var ids = loadCustomizedTermsIDs()
            ids.insert(updated.id)
            UserDefaults.standard.set(Array(ids), forKey: customizedTermsKey)
        }
        savePicks()
        return true
    }

    /// Clears the "user-customized" flag for a category, so its terms will be
    /// refreshed from the static definition on next load. Called by
    /// EditSpotSearchView's "Reset to defaults" when the user saves default terms.
    func clearCustomizedFlag(for categoryID: String) {
        var ids = loadCustomizedTermsIDs()
        ids.remove(categoryID)
        UserDefaults.standard.set(Array(ids), forKey: customizedTermsKey)
    }

    private func loadCustomizedTermsIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: customizedTermsKey) ?? [])
    }

    /// Re-applies admin overrides to current picks when Firestore overrides change mid-session.
    /// User-customized picks are left untouched (same precedence as loadPicks).
    private func refreshPicksFromOverrides() {
        let customizedIDs = loadCustomizedTermsIDs()
        let refreshed = picks.map { pick -> FoodCategory in
            guard !customizedIDs.contains(pick.id) else { return pick }
            return SearchTermOverrideService.shared.defaultCategory(for: pick)
        }
        picks = refreshed
        FoodCategory.registerUserPicks(picks)
        #if DEBUG
        print("[UserPicks] Refreshed picks from admin overrides")
        #endif
    }

    // MARK: - Persistence

    private func savePicks() {
        guard let data = try? JSONEncoder().encode(picks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        FoodCategory.registerUserPicks(picks)
        syncPicksToFirestore()
    }

    private func loadPicks() -> [FoodCategory] {
        // Load whatever was saved, or use defaults for first launch
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([FoodCategory].self, from: data),
              !saved.isEmpty
        else {
            return FoodCategory.defaultPicks
        }

        // Refresh terms from the single source of truth:
        // Firestore admin override > hardcoded static definition > saved pick.
        // User-customized categories (edited via EditSpotSearchView) keep their terms.
        let customizedIDs = loadCustomizedTermsIDs()
        let refreshed = saved.map { pick -> FoodCategory in
            // User intentionally customized this one — keep their edits (just refresh color for custom_)
            if customizedIDs.contains(pick.id) {
                if pick.id.hasPrefix("custom_") {
                    return FoodCategory(
                        id: pick.id, displayName: pick.displayName, emoji: pick.emoji,
                        color: .cyan, mapSearchTerms: pick.mapSearchTerms,
                        websiteKeywords: pick.websiteKeywords, relatedKeywords: pick.relatedKeywords,
                        addSpotPrompt: pick.addSpotPrompt
                    )
                }
                return pick
            }
            // Not customized — use canonical defaults (Firestore override > hardcoded)
            return SearchTermOverrideService.shared.defaultCategory(for: pick)
        }

        if FeatureFlags.broadSearchEnabled {
            return refreshed
        }

        // Launch mode: respect saved picks from launch categories,
        // plus append saved custom picks
        let launchIDs = Set(FeatureFlags.defaultCategories)
        let savedLaunch = refreshed.filter { launchIDs.contains($0.id) }
        let savedCustom = refreshed.filter { !launchIDs.contains($0.id) }

        var result = savedLaunch
        for pick in savedCustom where !result.contains(pick) {
            result.append(pick)
        }

        // Must have at least 1 pick — fall back to defaults if somehow empty
        return result.isEmpty ? FoodCategory.defaultPicks : result
    }

    // MARK: - Firestore Pick Tracking

    private static let pickCollection = "categoryPicks"
    private let db = Firestore.firestore()

    /// Track which built-in categories the user has picked in the `categoryPicks`
    /// Firestore collection with per-user dedup via `pickers` subcollection.
    /// Only counts additions — picks are never decremented (permanent tally).
    /// Custom picks (custom_*) are excluded — they're tracked separately
    /// via CustomCategoryService → `customCategories` collection.
    /// Fire-and-forget — never blocks the UI.
    private func syncPicksToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let currentIDs = Set(picks.map { $0.id })
        let previousIDs = Set(previousSyncedPicks)

        let added = currentIDs.subtracting(previousIDs)
            .filter { !$0.hasPrefix("custom_") } // Custom picks tracked separately

        for catID in added {
            let displayName = picks.first(where: { $0.id == catID })?.displayName ?? catID
            incrementPick(categoryID: catID, displayName: displayName, uid: uid)
        }

        previousSyncedPicks = Array(currentIDs)
        UserDefaults.standard.set(previousSyncedPicks, forKey: syncedPicksKey)
    }

    private let syncedPicksKey = "syncedCategoryPicks"

    /// Tracks what was last synced so we can compute add/remove deltas.
    private lazy var previousSyncedPicks: [String] = {
        UserDefaults.standard.stringArray(forKey: syncedPicksKey) ?? []
    }()

    private func incrementPick(categoryID: String, displayName: String, uid: String) {
        let docRef = db.collection(Self.pickCollection).document(categoryID)
        let pickerRef = docRef.collection("pickers").document(uid)

        Task.detached { @Sendable in
            do {
                let pickerDoc = try await pickerRef.getDocument()
                if pickerDoc.exists { return } // Already counted

                let docSnap = try await docRef.getDocument()
                if docSnap.exists {
                    try await docRef.updateData(["pickCount": FieldValue.increment(Int64(1))])
                } else {
                    try await docRef.setData([
                        "categoryID": categoryID,
                        "displayName": displayName,
                        "pickCount": 1
                    ])
                }
                try await pickerRef.setData(["pickedDate": FieldValue.serverTimestamp()])
                #if DEBUG
                print("[PickTrack] Incremented '\(categoryID)' for user \(uid)")
                #endif
            } catch {
                #if DEBUG
                print("[PickTrack] Error incrementing '\(categoryID)': \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Admin: Fetch Global Pick Counts

    /// Fetches built-in category pick counts from Firestore, ranked by popularity.
    /// Excludes custom picks (custom_*) — those are tracked in `customCategories`.
    /// Used by the admin dashboard to rank hardcoded categories.
    static func fetchPickCounts() async -> [(categoryID: String, displayName: String, pickCount: Int)] {
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection(pickCollection)
                .order(by: "pickCount", descending: true)
                .limit(to: 60)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                // Exclude custom picks — they belong in the Custom Picks table
                guard !doc.documentID.hasPrefix("custom_") else { return nil }
                let data = doc.data()
                guard let displayName = data["displayName"] as? String,
                      let pickCount = data["pickCount"] as? Int
                else { return nil }
                return (categoryID: doc.documentID, displayName: displayName, pickCount: pickCount)
            }
        } catch {
            #if DEBUG
            print("[PickTrack] fetchPickCounts error: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    /// Fetches built-in pick counts filtered by time window. Counts only pickers
    /// whose `pickedDate` falls on or after `since`. Excludes custom picks (custom_*).
    /// Returns results ranked by count.
    static func fetchPickCounts(since: Date) async -> [(categoryID: String, displayName: String, pickCount: Int)] {
        let db = Firestore.firestore()
        do {
            let catSnapshot = try await db.collection(pickCollection).getDocuments()
            var results: [(categoryID: String, displayName: String, pickCount: Int)] = []

            for doc in catSnapshot.documents {
                // Exclude custom picks — they belong in the Custom Picks table
                guard !doc.documentID.hasPrefix("custom_") else { continue }
                let data = doc.data()
                guard let displayName = data["displayName"] as? String else { continue }

                let pickersSnapshot = try await doc.reference.collection("pickers")
                    .whereField("pickedDate", isGreaterThanOrEqualTo: Timestamp(date: since))
                    .getDocuments()

                let count = pickersSnapshot.documents.count
                if count > 0 {
                    results.append((categoryID: doc.documentID, displayName: displayName, pickCount: count))
                }
            }

            return results.sorted { $0.pickCount > $1.pickCount }
        } catch {
            #if DEBUG
            print("[PickTrack] fetchPickCounts(since:) error: \(error.localizedDescription)")
            #endif
            return []
        }
    }
}
