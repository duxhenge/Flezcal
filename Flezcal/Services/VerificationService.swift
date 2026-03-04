import Foundation
import FirebaseFirestore

@MainActor
class VerificationService: ObservableObject {
    @Published var verifications: [Verification] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// All verifications across all spots — loaded for leaderboard point calculation
    @Published var allVerifications: [Verification] = []

    private let db = Firestore.firestore()
    private let collectionName = FirestoreCollections.verifications

    // MARK: - Fetch Verifications for a Spot

    func fetchVerifications(for spotID: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("spotID", isEqualTo: spotID)
                .getDocuments()

            verifications = snapshot.documents
                .compactMap { try? $0.data(as: Verification.self) }
                .sorted { $0.date > $1.date }
        } catch {
            errorMessage = "Failed to load verifications: \(error.localizedDescription)"
            CrashReporter.record(error, context: "VerificationService.fetchVerifications")
        }
        isLoading = false
    }

    // MARK: - Fetch All Verifications (for leaderboard)

    func fetchAllVerifications() async {
        do {
            let snapshot = try await db.collection(collectionName)
                .getDocuments()

            allVerifications = snapshot.documents
                .compactMap { try? $0.data(as: Verification.self) }
        } catch {
            errorMessage = "Failed to load verifications: \(error.localizedDescription)"
        }
    }

    // MARK: - Fetch User's Verifications (for profile history)

    func fetchUserVerifications(userID: String) async -> [Verification] {
        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("userID", isEqualTo: userID)
                .getDocuments()

            return snapshot.documents
                .compactMap { try? $0.data(as: Verification.self) }
                .sorted { $0.date > $1.date }
        } catch {
            #if DEBUG
            print("[VerificationService] fetchUserVerifications failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    // MARK: - Get User's Existing Vote & Rating

    /// Returns the user's existing vote for a specific category (nil if not voted)
    func userVote(for category: SpotCategory, userID: String) -> Bool? {
        verifications.first {
            $0.userID == userID && $0.category == category.rawValue
        }?.vote
    }

    /// Returns the user's existing rating for a specific category (nil if not rated)
    func userRating(for category: SpotCategory, userID: String) -> Int? {
        verifications.first {
            $0.userID == userID && $0.category == category.rawValue
        }?.rating
    }

    /// Whether the user has already voted on this category
    func hasUserVoted(for category: SpotCategory, userID: String) -> Bool {
        verifications.contains {
            $0.userID == userID && $0.category == category.rawValue
        }
    }

    // MARK: - Aggregate Rating for a Category

    /// Compute the aggregate rating for a category from all verifications with ratings.
    /// Returns nil if no ratings exist.
    func categoryAggregateRating(for category: SpotCategory) -> CategoryRating? {
        let rated = verifications.filter {
            $0.category == category.rawValue && $0.vote == true && $0.rating != nil
        }
        guard !rated.isEmpty else { return nil }
        let sum = rated.compactMap(\.rating).reduce(0, +)
        let avg = Double(sum) / Double(rated.count)
        return CategoryRating(average: avg, count: rated.count)
    }

    /// Number of users who confirmed (thumbs up) for a category
    func confirmationCount(for category: SpotCategory) -> Int {
        verifications.filter {
            $0.category == category.rawValue && $0.vote == true
        }.count
    }

    // MARK: - Submit, Change, or Retract Vote

    /// Creates a new vote, flips an existing one, or retracts if tapping the same vote again.
    /// When flipping to thumbs-down, any existing rating is cleared.
    /// Updates running tallies on the spot document using FieldValue.increment().
    /// Returns true on success.
    func submitVote(spotID: String, userID: String, category: SpotCategory, vote: Bool) async -> Bool {
        let existing = verifications.first {
            $0.userID == userID && $0.category == category.rawValue
        }

        let spotRef = db.collection(FirestoreCollections.spots).document(spotID)
        let catKey = category.rawValue

        if let existing = existing {
            if existing.vote == vote {
                // Same vote tapped again — retract (delete the verification)
                do {
                    try await db.collection(collectionName).document(existing.id).delete()
                } catch {
                    errorMessage = "Failed to retract vote: \(error.localizedDescription)"
                    CrashReporter.record(error, context: "VerificationService.retractVote")
                    return false
                }

                // Verification deleted — update local state immediately
                verifications.removeAll { $0.id == existing.id }

                // Best-effort tally decrement (don't fail the retract if this errors)
                do {
                    var tallyUpdate: [String: Any] = [
                        "verificationUserCount": FieldValue.increment(Int64(-1))
                    ]
                    if vote {
                        tallyUpdate["verificationUpCount.\(catKey)"] = FieldValue.increment(Int64(-1))
                    } else {
                        tallyUpdate["verificationDownCount.\(catKey)"] = FieldValue.increment(Int64(-1))
                    }
                    try await spotRef.updateData(tallyUpdate)
                } catch {
                    #if DEBUG
                    print("⚠️ Tally decrement failed (non-fatal): \(error.localizedDescription)")
                    #endif
                }

                return true
            } else {
                // User is flipping their vote
                var updateData: [String: Any] = [
                    "vote": vote,
                    "updatedDate": Date()
                ]
                // If flipping to thumbs-down, clear any existing rating
                if !vote {
                    updateData["rating"] = FieldValue.delete()
                }

                do {
                    try await db.collection(collectionName).document(existing.id).updateData(updateData)
                } catch {
                    errorMessage = "Failed to update vote: \(error.localizedDescription)"
                    CrashReporter.record(error, context: "VerificationService.flipVote")
                    return false
                }

                // Vote flipped — update local state immediately
                if let index = verifications.firstIndex(where: { $0.id == existing.id }) {
                    verifications[index].vote = vote
                    verifications[index].updatedDate = Date()
                    if !vote {
                        verifications[index].rating = nil
                    }
                }

                // Log the flip for analytics (monthly rollup)
                AnalyticsService.shared.logVerificationVote(
                    spotID: spotID, category: category, isUpvote: vote
                )

                // Best-effort tally update
                do {
                    var tallyUpdate: [String: Any] = [
                        "lastVerificationDate": Date()
                    ]
                    if vote {
                        tallyUpdate["verificationUpCount.\(catKey)"] = FieldValue.increment(Int64(1))
                        tallyUpdate["verificationDownCount.\(catKey)"] = FieldValue.increment(Int64(-1))
                    } else {
                        tallyUpdate["verificationUpCount.\(catKey)"] = FieldValue.increment(Int64(-1))
                        tallyUpdate["verificationDownCount.\(catKey)"] = FieldValue.increment(Int64(1))
                    }
                    try await spotRef.updateData(tallyUpdate)
                } catch {
                    #if DEBUG
                    print("⚠️ Tally update failed (non-fatal): \(error.localizedDescription)")
                    #endif
                }

                return true
            }
        } else {
            // New vote — create verification document
            // Check if this is the first thumbs-up for this category on this spot
            let isFirstUpvote = vote && !verifications.contains {
                $0.category == catKey && $0.vote == true
            }

            let verification = Verification(
                spotID: spotID,
                userID: userID,
                category: catKey,
                vote: vote,
                date: Date(),
                isOriginalVerifier: isFirstUpvote
            )

            do {
                try db.collection(collectionName).document(verification.id).setData(from: verification)
            } catch {
                errorMessage = "Failed to submit vote: \(error.localizedDescription)"
                CrashReporter.record(error, context: "VerificationService.submitVote")
                return false
            }

            // Vote created — update local state immediately
            verifications.insert(verification, at: 0)

            // Log the new vote for analytics (monthly rollup)
            AnalyticsService.shared.logVerificationVote(
                spotID: spotID, category: category, isUpvote: vote
            )

            // Best-effort tally increment
            do {
                var tallyUpdate: [String: Any] = [
                    "lastVerificationDate": Date(),
                    "verificationUserCount": FieldValue.increment(Int64(1))
                ]
                if vote {
                    tallyUpdate["verificationUpCount.\(catKey)"] = FieldValue.increment(Int64(1))
                } else {
                    tallyUpdate["verificationDownCount.\(catKey)"] = FieldValue.increment(Int64(1))
                }
                try await spotRef.updateData(tallyUpdate)
            } catch {
                #if DEBUG
                print("⚠️ Tally increment failed (non-fatal): \(error.localizedDescription)")
                #endif
            }

            return true
        }
    }

    // MARK: - Submit Rating

    /// Submits or updates a rating for a category. Automatically sets vote to true (thumbs up)
    /// since rating implies verification. Also updates the aggregate category rating on the Spot.
    /// Returns true on success.
    func submitRating(spotID: String, userID: String, category: SpotCategory,
                      rating: Int, spotService: SpotService) async -> Bool {
        let existing = verifications.first {
            $0.userID == userID && $0.category == category.rawValue
        }
        let catKey = category.rawValue

        if let existing = existing {
            // Update existing verification with rating (and ensure vote = true)
            var updateData: [String: Any] = [
                "rating": rating,
                "updatedDate": Date()
            ]

            // If they had thumbs-down, flip to thumbs-up (rating implies verification)
            let needsVoteFlip = !existing.vote
            if needsVoteFlip {
                updateData["vote"] = true
            }

            do {
                try await db.collection(collectionName).document(existing.id).updateData(updateData)
            } catch {
                errorMessage = "Failed to submit rating: \(error.localizedDescription)"
                CrashReporter.record(error, context: "VerificationService.submitRating")
                return false
            }

            // Update local state
            if let index = verifications.firstIndex(where: { $0.id == existing.id }) {
                verifications[index].rating = rating
                verifications[index].updatedDate = Date()
                if needsVoteFlip {
                    verifications[index].vote = true
                }
            }

            // Update tally if vote was flipped
            if needsVoteFlip {
                let spotRef = db.collection(FirestoreCollections.spots).document(spotID)
                do {
                    try await spotRef.updateData([
                        "verificationUpCount.\(catKey)": FieldValue.increment(Int64(1)),
                        "verificationDownCount.\(catKey)": FieldValue.increment(Int64(-1)),
                        "lastVerificationDate": Date()
                    ])
                } catch {
                    #if DEBUG
                    print("⚠️ Tally flip failed (non-fatal): \(error.localizedDescription)")
                    #endif
                }
            }
        } else {
            // New verification with rating — vote = true, isOriginalVerifier if first
            let isFirstUpvote = !verifications.contains {
                $0.category == catKey && $0.vote == true
            }

            let verification = Verification(
                spotID: spotID,
                userID: userID,
                category: catKey,
                vote: true,
                rating: rating,
                date: Date(),
                isOriginalVerifier: isFirstUpvote
            )

            do {
                try db.collection(collectionName).document(verification.id).setData(from: verification)
            } catch {
                errorMessage = "Failed to submit rating: \(error.localizedDescription)"
                CrashReporter.record(error, context: "VerificationService.submitRating")
                return false
            }

            verifications.insert(verification, at: 0)

            // Log for analytics
            AnalyticsService.shared.logVerificationVote(
                spotID: spotID, category: category, isUpvote: true
            )

            // Tally increment
            let spotRef = db.collection(FirestoreCollections.spots).document(spotID)
            do {
                try await spotRef.updateData([
                    "verificationUpCount.\(catKey)": FieldValue.increment(Int64(1)),
                    "lastVerificationDate": Date(),
                    "verificationUserCount": FieldValue.increment(Int64(1))
                ])
            } catch {
                #if DEBUG
                print("⚠️ Tally increment failed (non-fatal): \(error.localizedDescription)")
                #endif
            }
        }

        // Recalculate and persist aggregate category rating
        if let aggregate = categoryAggregateRating(for: category) {
            await spotService.updateCategoryRating(
                spotID: spotID, category: catKey,
                newAverage: aggregate.average, newCount: aggregate.count
            )
        }

        return true
    }

    // MARK: - Remove Rating (keep verification)

    /// Removes a rating without changing the user's thumbs up/down vote.
    /// Returns true on success.
    func removeRating(spotID: String, userID: String, category: SpotCategory,
                      spotService: SpotService) async -> Bool {
        guard let existing = verifications.first(where: {
            $0.userID == userID && $0.category == category.rawValue
        }), existing.rating != nil else { return true }  // nothing to remove

        do {
            try await db.collection(collectionName).document(existing.id).updateData([
                "rating": FieldValue.delete(),
                "updatedDate": Date()
            ])
        } catch {
            errorMessage = "Failed to remove rating: \(error.localizedDescription)"
            CrashReporter.record(error, context: "VerificationService.removeRating")
            return false
        }

        // Update local state
        if let index = verifications.firstIndex(where: { $0.id == existing.id }) {
            verifications[index].rating = nil
            verifications[index].updatedDate = Date()
        }

        // Recalculate aggregate
        let catKey = category.rawValue
        if let aggregate = categoryAggregateRating(for: category) {
            await spotService.updateCategoryRating(
                spotID: spotID, category: catKey,
                newAverage: aggregate.average, newCount: aggregate.count
            )
        } else {
            // No more ratings — zero out the category rating
            await spotService.updateCategoryRating(
                spotID: spotID, category: catKey,
                newAverage: 0, newCount: 0
            )
        }

        return true
    }

    // MARK: - Legacy Review Migration

    /// Backfills verification documents from legacy reviews that don't already have
    /// a corresponding verification. Creates a thumbs-up verification with the
    /// review's rating for each unmatched review. Idempotent — safe to run repeatedly.
    func migrateReviewsToVerifications(spotID: String, reviews: [Review],
                                        spotService: SpotService) async {
        // Only consider non-hidden reviews for this spot
        let spotReviews = reviews.filter { $0.spotID == spotID && !$0.isHidden }
        guard !spotReviews.isEmpty else { return }

        for review in spotReviews {
            let catKey = review.category ?? "flan"  // Legacy reviews default to flan

            // Check if this user already has a verification for this category
            let alreadyExists = verifications.contains {
                $0.userID == review.userID && $0.category == catKey
            }
            guard !alreadyExists else { continue }

            // Create verification from review
            let verification = Verification(
                spotID: spotID,
                userID: review.userID,
                category: catKey,
                vote: true,
                rating: review.rating,
                date: review.date,
                isOriginalVerifier: false
            )

            do {
                try db.collection(collectionName).document(verification.id).setData(from: verification)
                verifications.insert(verification, at: 0)
            } catch {
                #if DEBUG
                print("[VerificationService] Migration failed for review \(review.id): \(error.localizedDescription)")
                #endif
            }
        }

        // Recalculate aggregates for each category that had migrated reviews
        let affectedCategories = Set(spotReviews.compactMap { $0.category ?? "flan" })
        for catKey in affectedCategories {
            if let cat = SpotCategory(rawValue: catKey),
               let aggregate = categoryAggregateRating(for: cat) {
                await spotService.updateCategoryRating(
                    spotID: spotID, category: catKey,
                    newAverage: aggregate.average, newCount: aggregate.count
                )
            }
        }
    }

    // MARK: - Freshness Helpers

    /// Relative time string for the last verification date
    static func freshnessText(lastDate: Date?, userCount: Int) -> String {
        guard let lastDate = lastDate else {
            return "No verifications yet — be the first to verify!"
        }

        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        if lastDate < sixMonthsAgo {
            return "No recent confirmations — be the first to verify!"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeTime = formatter.localizedString(for: lastDate, relativeTo: Date())

        if userCount > 0 {
            return "Last verified \(relativeTime) by \(userCount) \(userCount == 1 ? "user" : "users")"
        } else {
            return "Last verified \(relativeTime)"
        }
    }
}
