import Foundation
import FirebaseFirestore

/// Reads curated offering lists (e.g. mezcal brands, tea varieties) from Firestore.
/// Any category can have a curated list; categories without one use hardcoded defaults
/// (MezcalBrands, TeaVarieties) or community-sourced data.
///
/// Firestore document: `app_config/offering_lists`
/// Structure: `{ "mezcal": ["Del Maguey", "Vago", ...], "tea": ["Sencha", ...], ... }`
@MainActor
final class OfferingListService: ObservableObject {
    static let shared = OfferingListService()

    /// Category ID → curated offering list. Empty dict = use hardcoded defaults.
    @Published private(set) var overrides: [String: [String]] = [:] {
        didSet { Self.overridesSnapshot = overrides }
    }

    /// Thread-safe snapshot for non-MainActor contexts (e.g. CommunityOfferings.suggestions).
    nonisolated(unsafe) private(set) static var overridesSnapshot: [String: [String]] = [:]

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        listener = db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.offeringLists)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    #if DEBUG
                    print("[OfferingLists] Listener error: \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let data = snapshot?.data() else {
                    #if DEBUG
                    print("[OfferingLists] No document found. Using hardcoded defaults.")
                    #endif
                    Task { @MainActor in self.overrides = [:] }
                    return
                }

                var parsed: [String: [String]] = [:]
                for (key, value) in data {
                    guard key != "updatedAt" else { continue }
                    if let list = value as? [String], !list.isEmpty {
                        parsed[key] = list
                    }
                }

                Task { @MainActor in
                    self.overrides = parsed
                }
                #if DEBUG
                print("[OfferingLists] Loaded \(parsed.count) list(s): \(parsed.keys.sorted().joined(separator: ", "))")
                #endif
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Admin writes

    /// Saves a curated offering list for a category. Merges into the existing document.
    func saveOfferings(categoryID: String, offerings: [String]) async throws {
        try await db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.offeringLists)
            .setData([
                categoryID: offerings,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    /// Removes the curated list for a category (reverts to hardcoded/community defaults).
    func removeOfferings(categoryID: String) async throws {
        try await db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.offeringLists)
            .updateData([
                categoryID: FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }
}
