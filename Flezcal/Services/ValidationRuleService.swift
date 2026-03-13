import Foundation
import FirebaseFirestore

/// Reads validation rules (blocked terms, too-generic terms) from Firestore.
/// Defense-in-depth: Firestore lists **union** with hardcoded lists in CustomCategory.
/// Accidental deletion of the Firestore document cannot remove safety protections.
///
/// Firestore document: `app_config/validation_rules`
/// Structure:
/// ```
/// {
///   "blockedExact": ["cat", "dog", ...],
///   "blockedSubstrings": ["human meat", "cannibal", ...],
///   "tooGenericTerms": ["food", "restaurant", ...]
/// }
/// ```
@MainActor
final class ValidationRuleService: ObservableObject {
    static let shared = ValidationRuleService()

    @Published private(set) var tooGenericTerms: Set<String> = [] {
        didSet { updateSnapshot() }
    }
    @Published private(set) var blockedExact: Set<String> = [] {
        didSet { updateSnapshot() }
    }
    @Published private(set) var blockedSubstrings: [String] = [] {
        didSet { updateSnapshot() }
    }

    /// Thread-safe snapshot for non-MainActor contexts (CustomCategory.isBlocked is static).
    nonisolated(unsafe) private(set) static var snapshot = ValidationSnapshot.empty

    struct ValidationSnapshot {
        let tooGenericTerms: Set<String>
        let blockedExact: Set<String>
        let blockedSubstrings: [String]
        static let empty = ValidationSnapshot(tooGenericTerms: [], blockedExact: [], blockedSubstrings: [])
        var isEmpty: Bool { tooGenericTerms.isEmpty && blockedExact.isEmpty && blockedSubstrings.isEmpty }
    }

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    private func updateSnapshot() {
        Self.snapshot = ValidationSnapshot(
            tooGenericTerms: tooGenericTerms,
            blockedExact: blockedExact,
            blockedSubstrings: blockedSubstrings
        )
    }

    // MARK: - Lifecycle

    func startListening() {
        listener = db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.validationRules)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    #if DEBUG
                    print("[ValidationRules] Listener error: \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let data = snapshot?.data() else {
                    #if DEBUG
                    print("[ValidationRules] No document found. Using hardcoded defaults only.")
                    #endif
                    Task { @MainActor in
                        self.tooGenericTerms = []
                        self.blockedExact = []
                        self.blockedSubstrings = []
                    }
                    return
                }

                let generic = data["tooGenericTerms"] as? [String] ?? []
                let exact = data["blockedExact"] as? [String] ?? []
                let subs = data["blockedSubstrings"] as? [String] ?? []

                Task { @MainActor in
                    self.tooGenericTerms = Set(generic)
                    self.blockedExact = Set(exact)
                    self.blockedSubstrings = subs
                }
                #if DEBUG
                print("[ValidationRules] Loaded: \(generic.count) generic, \(exact.count) exact, \(subs.count) substring rules")
                #endif
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Admin writes

    func saveTooGenericTerms(_ terms: [String]) async throws {
        try await db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.validationRules)
            .setData(["tooGenericTerms": terms, "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }

    func saveBlockedExact(_ terms: [String]) async throws {
        try await db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.validationRules)
            .setData(["blockedExact": terms, "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }

    func saveBlockedSubstrings(_ terms: [String]) async throws {
        try await db.collection(FirestoreCollections.appConfig)
            .document(FirestoreCollections.validationRules)
            .setData(["blockedSubstrings": terms, "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }
}
