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

    private let defaultsKey = "userFoodCategoryPicks"
    private let customPicksKey = "userCustomPicks"

    init() {
        picks = loadPicks()
        customPickCount = loadCustomPickCount()
        FoodCategory.registerUserPicks(picks)
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
    /// Returns false if not found.
    @discardableResult
    func updatePick(_ updated: FoodCategory) -> Bool {
        guard let index = picks.firstIndex(where: { $0.id == updated.id }) else { return false }
        picks[index] = updated
        savePicks()
        return true
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

        if FeatureFlags.broadSearchEnabled {
            return saved
        }

        // Launch mode: respect saved picks from launch categories,
        // plus append saved custom picks (up to maxCustomItems)
        let launchIDs = Set(FeatureFlags.defaultCategories)
        let savedLaunch = saved.filter { launchIDs.contains($0.id) }
        let savedCustom = saved.filter { !launchIDs.contains($0.id) }

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

    /// Track which categories the user has picked in the `categoryPicks`
    /// Firestore collection with per-user dedup via `pickers` subcollection.
    /// Previous picks that were removed get decremented.
    /// Fire-and-forget — never blocks the UI.
    private func syncPicksToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let currentIDs = Set(picks.map { $0.id })
        let previousIDs = Set(previousSyncedPicks)

        let added = currentIDs.subtracting(previousIDs)
        let removed = previousIDs.subtracting(currentIDs)

        for catID in added {
            let displayName = picks.first(where: { $0.id == catID })?.displayName ?? catID
            incrementPick(categoryID: catID, displayName: displayName, uid: uid)
        }

        for catID in removed {
            decrementPick(categoryID: catID, uid: uid)
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

        Task.detached {
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

    private func decrementPick(categoryID: String, uid: String) {
        let docRef = db.collection(Self.pickCollection).document(categoryID)
        let pickerRef = docRef.collection("pickers").document(uid)

        Task.detached {
            do {
                let pickerDoc = try await pickerRef.getDocument()
                guard pickerDoc.exists else { return } // Wasn't counted

                try await docRef.updateData(["pickCount": FieldValue.increment(Int64(-1))])
                try await pickerRef.delete()
                #if DEBUG
                print("[PickTrack] Decremented '\(categoryID)' for user \(uid)")
                #endif
            } catch {
                #if DEBUG
                print("[PickTrack] Error decrementing '\(categoryID)': \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Admin: Fetch Global Pick Counts

    /// Fetches all category pick counts from Firestore, ranked by popularity.
    /// Used by the admin dashboard to rank hardcoded categories.
    static func fetchPickCounts() async -> [(categoryID: String, displayName: String, pickCount: Int)] {
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection(pickCollection)
                .order(by: "pickCount", descending: true)
                .limit(to: 20)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
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
}
