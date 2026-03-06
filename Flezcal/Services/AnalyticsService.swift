import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Silent analytics event logger. Fire-and-forget — never blocks UI.
///
/// Not `ObservableObject` — intentionally **not** injected as `@EnvironmentObject`
/// to avoid re-render cascades (see Explore search stability contract in MEMORY.md).
///
/// All public methods return `Void` and dispatch Firestore writes on a background
/// task. Failures are silently logged in DEBUG only (matches VerificationService pattern).
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let db = Firestore.firestore()

    /// Spots already viewed this session — prevents double-counting on sheet re-open.
    private var viewedThisSession: Set<String> = []

    private init() {}

    // MARK: - Helpers

    private var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Public API

    /// Log a spot detail view. Call from SpotDetailView `.task`.
    /// Idempotent per session — repeated views of the same spot are ignored.
    func logSpotView(spotID: String) {
        guard let userID, !viewedThisSession.contains(spotID) else { return }
        viewedThisSession.insert(spotID)

        let monthKey = currentMonthKey
        Task.detached(priority: .utility) { [weak self] in
            await self?.writeSpotView(spotID: spotID, userID: userID, monthKey: monthKey)
        }
    }

    /// Log a reservation URL click. Call when the user taps the reservation link.
    func logReservationClick(spotID: String) {
        guard userID != nil else { return }
        let monthKey = currentMonthKey
        Task.detached(priority: .utility) { [weak self] in
            await self?.writeReservationClick(spotID: spotID, monthKey: monthKey)
        }
    }

    /// Log a verification vote. Call from VerificationService after a successful
    /// new vote or flip vote. Retractions are not logged (the vote is being removed).
    func logVerificationVote(spotID: String, category: SpotCategory, isUpvote: Bool) {
        let monthKey = currentMonthKey
        let catKey = category.rawValue
        Task.detached(priority: .utility) { [weak self] in
            await self?.writeVerificationVote(
                spotID: spotID, catKey: catKey, isUpvote: isUpvote, monthKey: monthKey
            )
        }
    }

    // MARK: - Internal Writes

    private func writeSpotView(spotID: String, userID: String, monthKey: String) async {
        let spotRef = db.collection(FirestoreCollections.spots).document(spotID)
        let monthRef = spotRef.collection(FirestoreCollections.analyticsMonthly).document(monthKey)
        let viewerRef = spotRef.collection(FirestoreCollections.viewerLog).document(userID)

        // 1. Increment all-time view count on spot document
        do {
            try await spotRef.updateData([
                "analyticsViewCount": FieldValue.increment(Int64(1))
            ])
        } catch {
            #if DEBUG
            print("Analytics: spot view count increment failed (non-fatal): \(error.localizedDescription)")
            #endif
        }

        // 2. Increment monthly view count
        do {
            try await monthRef.setData([
                "viewCount": FieldValue.increment(Int64(1))
            ], merge: true)
        } catch {
            #if DEBUG
            print("Analytics: monthly view count increment failed (non-fatal): \(error.localizedDescription)")
            #endif
        }

        // 3. Update viewer log (new vs returning)
        do {
            let viewerDoc = try await viewerRef.getDocument()
            if viewerDoc.exists {
                // Returning viewer — update lastSeen
                try await viewerRef.updateData([
                    "lastSeen": FieldValue.serverTimestamp()
                ])
                try await monthRef.setData([
                    "returningViewerCount": FieldValue.increment(Int64(1))
                ], merge: true)
            } else {
                // New viewer — create document
                try await viewerRef.setData([
                    "firstSeen": FieldValue.serverTimestamp(),
                    "lastSeen": FieldValue.serverTimestamp(),
                    "monthFirstSeen": monthKey
                ])
                try await monthRef.setData([
                    "newViewerCount": FieldValue.increment(Int64(1))
                ], merge: true)
            }
        } catch {
            #if DEBUG
            print("Analytics: viewer log update failed (non-fatal): \(error.localizedDescription)")
            #endif
        }
    }

    private func writeReservationClick(spotID: String, monthKey: String) async {
        let spotRef = db.collection(FirestoreCollections.spots).document(spotID)
        let monthRef = spotRef.collection(FirestoreCollections.analyticsMonthly).document(monthKey)

        // 1. Increment all-time reservation clicks
        do {
            try await spotRef.updateData([
                "analyticsReservationClicks": FieldValue.increment(Int64(1))
            ])
        } catch {
            #if DEBUG
            print("Analytics: reservation click increment failed (non-fatal): \(error.localizedDescription)")
            #endif
        }

        // 2. Increment monthly reservation clicks
        do {
            try await monthRef.setData([
                "reservationClickCount": FieldValue.increment(Int64(1))
            ], merge: true)
        } catch {
            #if DEBUG
            print("Analytics: monthly reservation click increment failed (non-fatal): \(error.localizedDescription)")
            #endif
        }
    }

    private func writeVerificationVote(
        spotID: String, catKey: String, isUpvote: Bool, monthKey: String
    ) async {
        let monthRef = db.collection(FirestoreCollections.spots)
            .document(spotID)
            .collection(FirestoreCollections.analyticsMonthly)
            .document(monthKey)

        let field = isUpvote
            ? "verificationVotes.\(catKey).up"
            : "verificationVotes.\(catKey).down"

        do {
            try await monthRef.setData([
                field: FieldValue.increment(Int64(1))
            ], merge: true)
        } catch {
            #if DEBUG
            print("Analytics: monthly verification vote failed (non-fatal): \(error.localizedDescription)")
            #endif
        }
    }
}
