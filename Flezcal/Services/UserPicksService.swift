import Foundation
import Combine

/// Persists the user's chosen food/drink picks across app launches.
/// Picks are stored as JSON in UserDefaults — no Firestore needed,
/// preferences are device-local.
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
}
