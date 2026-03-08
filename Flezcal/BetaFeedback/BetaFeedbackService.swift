import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Handles writing beta feedback documents to Firestore and reading them for admin.
@MainActor
final class BetaFeedbackService: ObservableObject {
    private let db = Firestore.firestore()
    private let collectionName = "beta_feedback"

    @Published var isSubmitting = false
    @Published var feedbackItems: [BetaFeedback] = []
    @Published var feedbackCount: Int = 0

    // MARK: - Submit feedback (user-facing)

    /// Submits a feedback document to Firestore. Returns true on success.
    func submitFeedback(
        category: FeedbackCategory,
        city: String,
        feedbackText: String,
        selectedCategories: [String]
    ) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            #if DEBUG
            print("[BetaFeedback] No authenticated user. Cannot submit.")
            #endif
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let data: [String: Any] = [
            "userId": userId,
            "category": category.rawValue,
            "city": city,
            "feedbackText": feedbackText,
            "timestamp": FieldValue.serverTimestamp(),
            "appVersion": AppConstants.appVersion,
            "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "deviceModel": Self.deviceModel(),
            "iOSVersion": Self.iOSVersion(),
            "selectedCategories": selectedCategories,
        ]

        do {
            try await db.collection(collectionName).addDocument(data: data)
            #if DEBUG
            print("[BetaFeedback] Submitted: \(category.rawValue) from \(city.isEmpty ? "no city" : city)")
            #endif
            return true
        } catch {
            #if DEBUG
            print("[BetaFeedback] Submit failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    // MARK: - Admin: fetch all feedback

    func fetchAllFeedback() async {
        do {
            let snapshot = try await db.collection(collectionName)
                .order(by: "timestamp", descending: true)
                .getDocuments()
            feedbackItems = snapshot.documents.compactMap { doc in
                try? doc.data(as: BetaFeedback.self)
            }
            feedbackCount = feedbackItems.count
            #if DEBUG
            print("[BetaFeedback] Fetched \(feedbackItems.count) items")
            #endif
        } catch {
            #if DEBUG
            print("[BetaFeedback] Fetch failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Returns the count of feedback documents. Lightweight query for admin overview.
    func fetchCount() async {
        do {
            let snapshot = try await db.collection(collectionName)
                .count
                .getAggregation(source: .server)
            feedbackCount = Int(truncating: snapshot.count)
        } catch {
            #if DEBUG
            print("[BetaFeedback] Count fetch failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Admin: export

    /// Exports all feedback as a JSON string for sharing with Claude Chat.
    func exportAsJSON() -> String {
        let items = feedbackItems.map { item -> [String: Any] in
            [
                "id": item.id ?? "unknown",
                "category": item.category,
                "city": item.city,
                "feedbackText": item.feedbackText,
                "timestamp": item.formattedDate,
                "appVersion": item.appVersion,
                "buildNumber": item.buildNumber,
                "deviceModel": item.deviceModel,
                "iOSVersion": item.iOSVersion,
                "selectedCategories": item.selectedCategories,
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Device info helpers

    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier // e.g. "iPhone16,1"
    }

    private static func iOSVersion() -> String {
        let device = ProcessInfo.processInfo.operatingSystemVersion
        return "\(device.majorVersion).\(device.minorVersion).\(device.patchVersion)"
    }
}
