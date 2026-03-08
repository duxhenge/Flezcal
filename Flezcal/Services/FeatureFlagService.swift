import Foundation
import FirebaseFirestore

/// Reads and caches feature flags from Firestore `app_config/feature_flags`.
/// Uses a snapshot listener for near-real-time updates (no app restart needed).
/// Designed to support additional flags beyond beta feedback in the future.
@MainActor
final class FeatureFlagService: ObservableObject {
    static let shared = FeatureFlagService()

    // MARK: - Published flags

    @Published var betaFeedbackEnabled = false
    @Published var betaFeedbackPromptText = "How's your Flezcal experience? Share your thoughts!"

    // MARK: - Private

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        // Fail closed: defaults are already false / default prompt text.
        listener = db.collection("app_config").document("feature_flags")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    #if DEBUG
                    print("[FeatureFlags] Listener error: \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let data = snapshot?.data() else {
                    // Document doesn't exist yet. Keep defaults (feedback disabled).
                    #if DEBUG
                    print("[FeatureFlags] No document found. Defaulting to disabled.")
                    #endif
                    Task { @MainActor in
                        self.betaFeedbackEnabled = false
                    }
                    return
                }
                let enabled = data["betaFeedbackEnabled"] as? Bool ?? false
                let prompt = data["betaFeedbackPromptText"] as? String ?? ""
                Task { @MainActor in
                    self.betaFeedbackEnabled = enabled
                    if !prompt.isEmpty {
                        self.betaFeedbackPromptText = prompt
                    }
                }
                #if DEBUG
                print("[FeatureFlags] Updated: betaFeedback=\(enabled) prompt='\(prompt)'")
                #endif
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Admin writes

    /// Toggles the beta feedback flag in Firestore. Admin-only.
    func setBetaFeedbackEnabled(_ enabled: Bool) async throws {
        try await db.collection("app_config").document("feature_flags")
            .setData(["betaFeedbackEnabled": enabled], merge: true)
    }

    /// Updates the beta feedback prompt text in Firestore. Admin-only.
    func setBetaFeedbackPromptText(_ text: String) async throws {
        try await db.collection("app_config").document("feature_flags")
            .setData(["betaFeedbackPromptText": text], merge: true)
    }
}
