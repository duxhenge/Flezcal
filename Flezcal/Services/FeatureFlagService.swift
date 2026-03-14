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

    /// When true, all 50 categories are selectable. When false, only launch defaults are active.
    /// Fail-closed default: true (matches Constants.FeatureFlags.broadSearchEnabled).
    @Published var broadSearchEnabled = true

    /// The IDs of the locked launch categories (e.g. ["mezcal", "flan", "tacos"]).
    /// Fail-closed default matches Constants.FeatureFlags.defaultCategories.
    @Published var defaultCategories = ["mezcal", "flan", "tacos"]

    /// When true, the voice search mic button is visible on the Spots tab.
    /// Fail-closed default: false (hidden until explicitly enabled from admin).
    @Published var voiceSearchEnabled = false

    /// When true, the Concierge tab is visible and becomes the app's default landing screen.
    /// Fail-closed default: false (hidden until explicitly enabled from admin).
    @Published var conciergeEnabled = false

    /// Default emoji for all trending/custom Flezcals. Changeable from admin.
    /// Fail-closed default: 🐛 (worm).
    @Published var trendingEmoji = "🐛" {
        didSet { Self.trendingEmojiSnapshot = trendingEmoji }
    }

    /// Thread-safe snapshot for non-MainActor access (e.g. SpotCategory.emoji).
    nonisolated(unsafe) private(set) static var trendingEmojiSnapshot = "🐛"

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
                    // Document doesn't exist yet. Keep defaults (feedback disabled, broad search on).
                    #if DEBUG
                    print("[FeatureFlags] No document found. Using fail-closed defaults.")
                    #endif
                    Task { @MainActor in
                        self.betaFeedbackEnabled = false
                        self.broadSearchEnabled = true
                        self.defaultCategories = ["mezcal", "flan", "tacos"]
                        self.trendingEmoji = "🐛"
                        self.voiceSearchEnabled = false
                        self.conciergeEnabled = false
                    }
                    return
                }
                let enabled = data["betaFeedbackEnabled"] as? Bool ?? false
                let prompt = data["betaFeedbackPromptText"] as? String ?? ""
                let broad = data["broadSearchEnabled"] as? Bool ?? true
                let defaults = data["defaultCategories"] as? [String] ?? ["mezcal", "flan", "tacos"]
                let trending = data["trendingEmoji"] as? String ?? "🐛"
                let voice = data["voiceSearchEnabled"] as? Bool ?? false
                let concierge = data["conciergeEnabled"] as? Bool ?? false
                Task { @MainActor in
                    self.betaFeedbackEnabled = enabled
                    if !prompt.isEmpty {
                        self.betaFeedbackPromptText = prompt
                    }
                    self.broadSearchEnabled = broad
                    if !defaults.isEmpty {
                        self.defaultCategories = defaults
                    }
                    if !trending.isEmpty {
                        self.trendingEmoji = trending
                    }
                    self.voiceSearchEnabled = voice
                    self.conciergeEnabled = concierge
                }
                #if DEBUG
                print("[FeatureFlags] Updated: betaFeedback=\(enabled) broadSearch=\(broad) defaults=\(defaults) trendingEmoji=\(trending) voiceSearch=\(voice) concierge=\(concierge)")
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

    /// Toggles whether all 50 categories are selectable. Admin-only.
    func setBroadSearchEnabled(_ enabled: Bool) async throws {
        try await db.collection("app_config").document("feature_flags")
            .setData(["broadSearchEnabled": enabled], merge: true)
    }

    /// Updates the locked launch category IDs. Admin-only.
    func setDefaultCategories(_ categories: [String]) async throws {
        try await db.collection("app_config").document("feature_flags")
            .setData(["defaultCategories": categories], merge: true)
    }

    /// Toggles voice search visibility. Admin-only.
    func setVoiceSearchEnabled(_ enabled: Bool) async throws {
        try await db.collection("app_config").document("feature_flags")
            .setData(["voiceSearchEnabled": enabled], merge: true)
    }

    /// Updates the default emoji for trending/custom Flezcals. Admin-only.
    func setTrendingEmoji(_ emoji: String) async throws {
        try await db.collection("app_config").document("feature_flags")
            .setData(["trendingEmoji": emoji], merge: true)
    }

    /// Toggles Concierge Mode visibility. Admin-only.
    func setConciergeEnabled(_ enabled: Bool) async throws {
        try await db.collection("app_config").document("feature_flags")
            .setData(["conciergeEnabled": enabled], merge: true)
    }
}
