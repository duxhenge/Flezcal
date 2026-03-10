import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Persists the user's chosen food/drink picks across app launches.
/// Picks are stored as JSON in UserDefaults for device-local use,
/// AND synced to Firestore `categoryPicks` collection for global
/// popularity tracking (admin dashboard).
///
/// Users can freely select/deselect any of the 3 launch categories
/// (mezcal, flan, handmade tortillas) plus custom picks, with a minimum
/// of 1 pick required. When `FeatureFlags.broadSearchEnabled` is true
/// (Phase 4), all categories become freely selectable and custom slots
/// expand to 3.
@MainActor
class UserPicksService: ObservableObject {

    /// The user's current picks — freely selectable from launch categories
    /// and custom picks. At least 1 pick must remain active.
    @Published private(set) var picks: [FoodCategory] = []

    /// Total pick capacity: the 3 launch categories + custom slots.
    /// When broadSearchEnabled, this reverts to the original 3-total behavior
    /// (users choose freely from all categories).
    static var maxPicks: Int {
        if FeatureFlags.broadSearchEnabled {
            return 3
        }
        return FoodCategory.launchCategories.count + FeatureFlags.maxCustomItems
    }

    /// Number of custom picks the user has created this session.
    @Published private(set) var customPickCount: Int = 0

    /// User's chosen search radius in degrees. Controls how wide the Apple Maps
    /// search area is for both Explore and Map tabs. Default 0.5° ≈ 35 miles.
    @Published var searchRadiusDegrees: Double = 0.5

    private let defaultsKey = "userFoodCategoryPicks"
    private let customPicksKey = "userCustomPicks"
    private let searchRadiusKey = "userSearchRadiusDegrees"
    /// IDs of built-in categories whose mapSearchTerms the user intentionally
    /// customized via EditSpotSearchView. These are NOT refreshed from the
    /// static definition on load — the user's edits take precedence.
    private let customizedTermsKey = "userCustomizedTermsIDs"

    init() {
        picks = loadPicks()
        customPickCount = loadCustomPickCount()
        searchRadiusDegrees = loadSearchRadius()
        FoodCategory.registerUserPicks(picks)
        // No Firestore sync on launch — only deliberate user actions
        // (toggle/addCustomPick) trigger pick tracking.
    }

    // MARK: - Public API

    /// Whether a given category is currently selected.
    func isSelected(_ category: FoodCategory) -> Bool {
        picks.contains(category)
    }

    /// Toggle a pick on/off.
    /// - Any pick (including launch defaults) can be toggled off as long as
    ///   at least 1 pick remains active.
    /// - Adding: only allowed when picks.count < maxPicks.
    /// - Removing: only allowed when picks.count > 1 (must keep at least one).
    @discardableResult
    func toggle(_ category: FoodCategory) -> Bool {
        if isSelected(category) {
            guard picks.count > 1 else { return false }
            picks.removeAll { $0 == category }
        } else {
            guard picks.count < Self.maxPicks else { return false }
            picks.append(category)
        }
        savePicks()
        return true
    }

    /// Add a custom food category as a pick.
    /// Returns false if at custom pick limit or total pick limit.
    @discardableResult
    func addCustomPick(_ category: FoodCategory) -> Bool {
        guard picks.count < Self.maxPicks else { return false }
        guard customPickCount < FeatureFlags.maxCustomItems else { return false }
        guard !isSelected(category) else { return false }

        picks.append(category)
        customPickCount += 1
        savePicks()
        saveCustomPickCount()
        return true
    }

    /// Remove a custom pick and decrement the custom count.
    /// Returns false if not found or if it would leave zero picks.
    @discardableResult
    func removeCustomPick(_ category: FoodCategory) -> Bool {
        guard picks.count > 1 else { return false }
        guard let index = picks.firstIndex(of: category) else { return false }
        picks.remove(at: index)
        customPickCount = max(0, customPickCount - 1)
        savePicks()
        saveCustomPickCount()
        return true
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

    // MARK: - Search Radius

    /// Discrete radius options. Degrees are internal; miles and km are user-facing.
    static let radiusOptions: [(miles: Int, km: Int, degrees: Double)] = [
        (10,  16,  0.15),
        (25,  40,  0.35),
        (35,  56,  0.5),   // default
        (50,  80,  0.7),
        (75,  121, 1.1),
    ]

    /// Sets the search radius and persists to UserDefaults.
    func setSearchRadius(_ degrees: Double) {
        searchRadiusDegrees = degrees
        UserDefaults.standard.set(degrees, forKey: searchRadiusKey)
    }

    /// Returns the approximate miles label for a given radius in degrees.
    static func radiusInMiles(_ degrees: Double) -> Int {
        radiusOptions.min(by: { abs($0.degrees - degrees) < abs($1.degrees - degrees) })?.miles ?? 35
    }

    /// Returns the approximate km label for a given radius in degrees.
    static func radiusInKm(_ degrees: Double) -> Int {
        radiusOptions.min(by: { abs($0.degrees - degrees) < abs($1.degrees - degrees) })?.km ?? 56
    }

    private func loadSearchRadius() -> Double {
        let saved = UserDefaults.standard.double(forKey: searchRadiusKey)
        // 0.0 means never set — use default
        return saved > 0 ? saved : 0.5
    }

    /// Whether adding more picks is currently allowed.
    var canAddMore: Bool { picks.count < Self.maxPicks }

    /// Whether the user can create another custom pick.
    var canCreateCustom: Bool {
        customPickCount < FeatureFlags.maxCustomItems && canAddMore
    }

    /// The user's custom picks (user-created categories with custom_ prefix).
    var customPicks: [FoodCategory] {
        picks.filter { $0.id.hasPrefix("custom_") }
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

        // Refresh built-in categories from static definitions so code updates
        // to mapSearchTerms/websiteKeywords propagate automatically.
        // User-customized categories (edited via EditSpotSearchView) keep their terms.
        let customizedIDs = loadCustomizedTermsIDs()
        let refreshed = saved.map { pick -> FoodCategory in
            // Custom user-created categories — refresh color to match current
            // CustomCategory.color (prevents stale serialized colors persisting).
            if pick.id.hasPrefix("custom_") {
                return FoodCategory(
                    id: pick.id,
                    displayName: pick.displayName,
                    emoji: pick.emoji,
                    color: .cyan,
                    mapSearchTerms: pick.mapSearchTerms,
                    websiteKeywords: pick.websiteKeywords,
                    relatedKeywords: pick.relatedKeywords,
                    addSpotPrompt: pick.addSpotPrompt
                )
            }
            // User intentionally customized this one — keep their edits
            guard !customizedIDs.contains(pick.id) else { return pick }
            // Refresh from static definition if available
            guard let canonical = FoodCategory.allKnownCategories.first(where: { $0.id == pick.id }) else { return pick }
            return canonical
        }

        if FeatureFlags.broadSearchEnabled {
            return refreshed
        }

        // Launch mode: respect saved picks from launch categories,
        // plus append saved custom picks (up to maxCustomItems)
        let launchIDs = Set(FeatureFlags.defaultCategories)
        let savedLaunch = refreshed.filter { launchIDs.contains($0.id) }
        let savedCustom = refreshed.filter { !launchIDs.contains($0.id) }

        var result = savedLaunch
        for pick in savedCustom.prefix(FeatureFlags.maxCustomItems) {
            if !result.contains(pick) {
                result.append(pick)
            }
        }

        // Must have at least 1 pick — fall back to defaults if somehow empty
        return result.isEmpty ? FoodCategory.defaultPicks : result
    }

    private func saveCustomPickCount() {
        UserDefaults.standard.set(customPickCount, forKey: customPicksKey)
    }

    private func loadCustomPickCount() -> Int {
        let saved = UserDefaults.standard.integer(forKey: customPicksKey)
        // Clamp to maxCustomItems in case the flag was lowered
        return min(saved, FeatureFlags.maxCustomItems)
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
