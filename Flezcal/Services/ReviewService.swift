import Foundation
import FirebaseFirestore

@MainActor
class ReviewService: ObservableObject {
    @Published var reviews: [Review] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let collectionName = FirestoreCollections.reviews

    // MARK: - Fetch All Reviews (for leaderboard)

    @Published var allReviews: [Review] = []

    func fetchAllReviews() async {
        do {
            let snapshot = try await db.collection(collectionName)
                .order(by: "date", descending: true)
                .getDocuments()

            allReviews = snapshot.documents.compactMap { doc in
                try? doc.data(as: Review.self)
            }

            await migrateEmailUserNames()
        } catch {
            errorMessage = "Failed to load reviews: \(error.localizedDescription)"
        }
    }

    // MARK: - One-time migration: replace email addresses stored as userName

    /// Finds any reviews where userName contains "@" (i.e. an email was stored)
    /// and replaces it with "Flan & Mezcal Fan". Safe to call on every launch — no-ops once clean.
    private func migrateEmailUserNames() async {
        let emailReviews = allReviews.filter { $0.userName.contains("@") }
        guard !emailReviews.isEmpty else { return }

        for review in emailReviews {
            do {
                let update: [String: Any] = ["userName": "Flan & Mezcal Fan"]
                try await db.collection(collectionName).document(review.id)
                    .updateData(update)
                if let index = allReviews.firstIndex(where: { $0.id == review.id }) {
                    allReviews[index].userName = "Flan & Mezcal Fan"
                }
            } catch {
                // Non-fatal — will retry next launch
            }
        }
    }

    // MARK: - Fetch Reviews for a Spot

    func fetchReviews(for spotID: String) async {
        isLoading = true
        errorMessage = nil
        do {
            // Filter by spotID only (no compound index needed).
            // Sort client-side to avoid requiring a Firestore composite index.
            let snapshot = try await db.collection(collectionName)
                .whereField("spotID", isEqualTo: spotID)
                .getDocuments()

            reviews = snapshot.documents
                .compactMap { try? $0.data(as: Review.self) }
                .sorted { $0.date > $1.date }
        } catch {
            errorMessage = "Failed to load reviews: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Add a Review

    func addReview(_ review: Review) async -> Bool {
        do {
            try db.collection(collectionName).document(review.id).setData(from: review)
            reviews.insert(review, at: 0)
            return true
        } catch {
            errorMessage = "Failed to add review: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Report a Review

    func reportReview(reviewID: String, reporterUserID: String) async {
        guard let index = reviews.firstIndex(where: { $0.id == reviewID }) else { return }

        // Prevent duplicate reports from same user
        if reviews[index].reportedByUserIDs.contains(reporterUserID) {
            errorMessage = "You have already reported this review."
            return
        }

        // Prevent reporting your own review
        if reviews[index].userID == reporterUserID {
            errorMessage = "You cannot report your own review."
            return
        }

        let newCount = reviews[index].reportCount + 1
        let shouldHide = newCount >= 3

        do {
            let data: [String: Any] = [
                "isReported": true,
                "reportCount": newCount,
                "reportedByUserIDs": FieldValue.arrayUnion([reporterUserID]),
                "isHidden": shouldHide
            ]
            try await db.collection(collectionName).document(reviewID).updateData(data)
            reviews[index].isReported = true
            reviews[index].reportCount = newCount
            reviews[index].reportedByUserIDs.append(reporterUserID)
            reviews[index].isHidden = shouldHide
        } catch {
            errorMessage = "Failed to report review: \(error.localizedDescription)"
        }
    }

    // MARK: - Visible Reviews (hides auto-moderated)

    var visibleReviews: [Review] {
        reviews.filter { !$0.isHidden }
    }

    // MARK: - Calculate Average Rating

    var averageRating: Double {
        guard !reviews.isEmpty else { return 0 }
        let total = reviews.reduce(0) { $0 + $1.rating }
        return Double(total) / Double(reviews.count)
    }

    // MARK: - Check if User Already Reviewed

    func hasUserReviewed(userID: String) -> Bool {
        reviews.contains { $0.userID == userID }
    }

    // MARK: - Transcendent Badge

    /// True if any visible review for this spot uses the word "transcendent"
    var hasTranscendentReview: Bool {
        visibleReviews.contains { $0.isTranscendent }
    }
}
