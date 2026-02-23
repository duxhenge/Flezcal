import Foundation
import Combine

/// Persists the user's chosen food/drink picks across app launches.
/// Picks are stored as JSON in UserDefaults — no Firestore needed,
/// preferences are device-local.
///
/// Supports both hardcoded FoodCategory picks and user-created custom picks.
/// Default state (no picks stored): mezcal + flan, matching the original app behaviour.
@MainActor
class UserPicksService: ObservableObject {

    /// The user's current picks, always between 1 and maxPicks entries.
    @Published private(set) var picks: [FoodCategory] = []

    /// Maximum number of picks the user can select (hardcoded + custom combined).
    static let maxPicks = 3

    /// Number of custom picks the user has created this session.
    @Published private(set) var customPickCount: Int = 0

    private let defaultsKey = "userFoodCategoryPicks"
    private let customPicksKey = "userCustomPicks"

    init() {
        picks = loadPicks()
        customPickCount = loadCustomPickCount()
    }

    // MARK: - Public API

    /// Whether a given category is currently selected.
    func isSelected(_ category: FoodCategory) -> Bool {
        picks.contains(category)
    }

    /// Toggle a pick on/off.
    /// - Adding: only allowed when picks.count < maxPicks.
    /// - Removing: only allowed when picks.count > 1 (must keep at least one).
    @discardableResult
    func toggle(_ category: FoodCategory) -> Bool {
        if isSelected(category) {
            guard picks.count > 1 else { return false }   // must keep at least one
            picks.removeAll { $0 == category }
        } else {
            guard picks.count < Self.maxPicks else { return false }  // cap at max
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
        guard customPickCount < 3 else { return false }
        guard !isSelected(category) else { return false }

        picks.append(category)
        customPickCount += 1
        savePicks()
        saveCustomPickCount()
        return true
    }

    /// Whether adding this category is currently allowed.
    var canAddMore: Bool { picks.count < Self.maxPicks }

    /// Whether the user can create another custom pick.
    var canCreateCustom: Bool {
        customPickCount < 3 && canAddMore
    }

    // MARK: - Persistence

    private func savePicks() {
        guard let data = try? JSONEncoder().encode(picks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func loadPicks() -> [FoodCategory] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([FoodCategory].self, from: data),
              !saved.isEmpty
        else {
            return FoodCategory.defaultPicks
        }
        return saved
    }

    private func saveCustomPickCount() {
        UserDefaults.standard.set(customPickCount, forKey: customPicksKey)
    }

    private func loadCustomPickCount() -> Int {
        UserDefaults.standard.integer(forKey: customPicksKey)
    }
}
