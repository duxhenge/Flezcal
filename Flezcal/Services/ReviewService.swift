import Foundation
import SwiftUI
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
            CrashReporter.record(error, context: "ReviewService.fetchAllReviews")
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
            CrashReporter.record(error, context: "ReviewService.fetchReviews")
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
            CrashReporter.record(error, context: "ReviewService.addReview")
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
            CrashReporter.record(error, context: "ReviewService.reportReview")
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

    // MARK: - Per-Category Rating Helpers

    /// Average rating for reviews tagged with a specific category
    func averageRating(for category: SpotCategory) -> Double {
        let relevant = visibleReviews.filter { $0.category == category.rawValue }
        guard !relevant.isEmpty else { return 0 }
        return Double(relevant.reduce(0) { $0 + $1.rating }) / Double(relevant.count)
    }

    /// Number of visible reviews tagged with a specific category
    func reviewCount(for category: SpotCategory) -> Int {
        visibleReviews.filter { $0.category == category.rawValue }.count
    }

    // MARK: - Delete a Review (admin only)

    /// Deletes a review and recalculates the spot's per-category and overall ratings.
    /// Pass spotService so the spot document in Firestore stays in sync.
    func deleteReview(reviewID: String, spotID: String, spotService: SpotService) async -> Bool {
        // Capture the deleted review's category before removing it from the local array
        let deletedCategory = reviews.first(where: { $0.id == reviewID })?.category

        do {
            try await db.collection(collectionName).document(reviewID).delete()
            withAnimation {
                reviews.removeAll { $0.id == reviewID }
            }

            // Recalculate per-category ratings from remaining visible reviews
            let remaining = reviews.filter { !$0.isHidden }

            if remaining.isEmpty {
                // No reviews left — reset everything
                await spotService.updateSpotRating(spotID: spotID, newAverage: 0.0, newCount: 0)
            } else if let catKey = deletedCategory {
                // Recalculate just the affected category — updateCategoryRating
                // handles the overall weighted average recalculation automatically
                let catReviews = remaining.filter { $0.category == catKey }
                let catCount = catReviews.count
                let catAverage: Double = catCount > 0
                    ? Double(catReviews.reduce(0) { $0 + $1.rating }) / Double(catCount)
                    : 0.0

                await spotService.updateCategoryRating(
                    spotID: spotID,
                    category: catKey,
                    newAverage: catAverage,
                    newCount: catCount
                )
            } else {
                // Legacy uncategorized review — recalculate overall from all reviews
                let newCount = remaining.count
                let newAverage = Double(remaining.reduce(0) { $0 + $1.rating }) / Double(newCount)
                await spotService.updateSpotRating(spotID: spotID, newAverage: newAverage, newCount: newCount)
            }

            return true
        } catch {
            errorMessage = "Failed to delete review: \(error.localizedDescription)"
            CrashReporter.record(error, context: "ReviewService.deleteReview")
            return false
        }
    }

    // MARK: - Legacy Migration: Auto-Tag Single-Category Reviews

    /// For spots with exactly one category, assigns that category to any untagged
    /// legacy reviews. Updates both Firestore and the per-category aggregates on
    /// the spot document. Safe to call repeatedly — no-ops when nothing to migrate.
    func migrateUntaggedReviews(spot: Spot, spotService: SpotService) async {
        // Only auto-assign when the spot has exactly one category — for multi-category
        // spots we can't guess which food/drink the reviewer was rating.
        guard spot.categories.count == 1,
              let category = spot.categories.first else { return }

        let untagged = reviews.filter { $0.category == nil }
        guard !untagged.isEmpty else { return }

        let categoryKey = category.rawValue

        for review in untagged {
            do {
                try await db.collection(collectionName).document(review.id)
                    .updateData(["category": categoryKey])
                if let index = reviews.firstIndex(where: { $0.id == review.id }) {
                    reviews[index].category = categoryKey
                }
            } catch {
                #if DEBUG
                print("[ReviewService] category backfill failed for \(review.id): \(error.localizedDescription)")
                #endif
                // Non-fatal — will retry on next view
            }
        }

        // Recalculate per-category aggregate from all visible reviews now that they're tagged
        let visible = reviews.filter { !$0.isHidden && $0.category == categoryKey }
        let count = visible.count
        let average: Double = count > 0
            ? Double(visible.reduce(0) { $0 + $1.rating }) / Double(count)
            : 0.0

        await spotService.updateCategoryRating(
            spotID: spot.id,
            category: categoryKey,
            newAverage: average,
            newCount: count
        )

        #if DEBUG
        print("[ReviewService] migrated \(untagged.count) untagged review(s) to '\(categoryKey)' on \(spot.name)")
        #endif
    }

    // MARK: - Check if User Already Reviewed

    func hasUserReviewed(userID: String) -> Bool {
        reviews.contains { $0.userID == userID }
    }

    /// Returns true if the user has already reviewed a specific category on this spot.
    func hasUserReviewed(userID: String, category: SpotCategory) -> Bool {
        reviews.contains { $0.userID == userID && $0.category == category.rawValue }
    }

    /// Returns the categories on this spot that the user has NOT yet rated.
    func unratedCategories(userID: String, spotCategories: [SpotCategory]) -> [SpotCategory] {
        spotCategories.filter { cat in
            !reviews.contains { $0.userID == userID && $0.category == cat.rawValue }
        }
    }
}
