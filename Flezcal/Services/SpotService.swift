import Foundation
import FirebaseFirestore

@MainActor
class SpotService: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let collectionName = FirestoreCollections.spots

    // MARK: - Fetch All Spots

    func fetchSpots() async {
        isLoading = true
        errorMessage = nil
        do {
            let snapshot = try await db.collection(collectionName)
                .order(by: "addedDate", descending: true)
                .getDocuments()

            spots = snapshot.documents.compactMap { doc in
                try? doc.data(as: Spot.self)
            }

            // Clean up comma-separated mezcal entries, then deduplicate spots
            await cleanupCommaSeparatedMezcals()
            await deduplicateSpots()
            await backfillUserAddedVerification()
            await backfillGeohash()
        } catch {
            errorMessage = "Failed to load spots: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.loadSpots")
        }
        isLoading = false
    }

    // MARK: - Clean Up Comma-Separated Offering Entries

    /// Finds any offerings entries that contain commas (bulk-entered),
    /// splits them into individual items, and re-saves the cleaned list.
    /// Safe to call on every launch — no-ops if data is already clean.
    func cleanupCommaSeparatedOfferings() async {
        for spot in spots {
            guard let allOfferings = spot.offerings, !allOfferings.isEmpty else { continue }
            var needsUpdate = false
            var cleanedAll: [String: [String]] = [:]

            for (catKey, items) in allOfferings {
                guard !items.isEmpty else { continue }
                var expanded: [String] = []
                for entry in items {
                    let parts = entry.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }.filter { !$0.isEmpty }
                    expanded.append(contentsOf: parts)
                }
                var cleaned: [String] = []
                for item in expanded {
                    if !cleaned.contains(where: { $0.localizedCaseInsensitiveCompare(item) == .orderedSame }) {
                        cleaned.append(item)
                    }
                }
                cleanedAll[catKey] = cleaned
                if cleaned.count != items.count || Set(cleaned.map { $0.lowercased() }) != Set(items.map { $0.lowercased() }) {
                    needsUpdate = true
                }
            }

            guard needsUpdate else { continue }

            do {
                var data: [String: Any] = ["offerings": cleanedAll]
                if let mezcal = cleanedAll["mezcal"] {
                    data["mezcalOfferings"] = mezcal
                }
                try await db.collection(collectionName).document(spot.id).updateData(data)
                if let index = spots.firstIndex(where: { $0.id == spot.id }) {
                    spots[index].offerings = cleanedAll
                }
            } catch {
                // Permission denied or network error — stop batch to avoid write storm
                #if DEBUG
                print("[Backfill] Offerings cleanup aborted after error: \(error.localizedDescription)")
                #endif
                return
            }
        }
    }

    /// Legacy name — routes to cleanupCommaSeparatedOfferings
    func cleanupCommaSeparatedMezcals() async {
        await cleanupCommaSeparatedOfferings()
    }

    // MARK: - Deduplicate Existing Spots

    /// Finds duplicate spots (same name + nearby location), merges ALL mezcal offerings
    /// and categories from every duplicate into the oldest entry, then deletes the rest.
    ///
    /// Uses spot IDs (not array indices) for all tracking so that deletions during
    /// the loop never cause index-out-of-range crashes.
    private func deduplicateSpots() async {
        let threshold = 0.005 // ~550 meters — wide enough to catch Apple Maps vs OSM geocoding variance
        var processed: Set<String> = []

        // Snapshot the current spot list — we look up by ID so deletions are safe.
        let snapshot = spots

        for i in 0..<snapshot.count {
            let anchor = snapshot[i]
            guard !processed.contains(anchor.id) else { continue }

            // Collect IDs of all duplicates of this spot
            var groupIDs: [String] = [anchor.id]
            for j in (i + 1)..<snapshot.count {
                let candidate = snapshot[j]
                guard !processed.contains(candidate.id) else { continue }

                let nameMatch = anchor.name.localizedCaseInsensitiveContains(candidate.name)
                                || candidate.name.localizedCaseInsensitiveContains(anchor.name)
                let nearbyLat = abs(anchor.latitude - candidate.latitude) < threshold
                let nearbyLon = abs(anchor.longitude - candidate.longitude) < threshold

                if nameMatch && nearbyLat && nearbyLon {
                    groupIDs.append(candidate.id)
                }
            }

            // Only process groups with actual duplicates
            guard groupIDs.count > 1 else { continue }

            // Gather the Spot values for this group from the snapshot
            let groupSpots = snapshot.filter { groupIDs.contains($0.id) }

            // Keep the oldest entry
            guard let keeper = groupSpots.min(by: { $0.addedDate < $1.addedDate }) else { continue }

            // Merge ALL offerings from every entry in the group
            var mergedOfferings: [String: [String]] = [:]
            var allCategories: [SpotCategory] = []
            for member in groupSpots {
                if let memberOfferings = member.offerings {
                    for (catKey, items) in memberOfferings {
                        var existing = mergedOfferings[catKey] ?? []
                        for item in items {
                            let trimmed = item.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !existing.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                                existing.append(trimmed)
                            }
                        }
                        mergedOfferings[catKey] = existing
                    }
                }
                for cat in member.categories {
                    if !allCategories.contains(cat) {
                        allCategories.append(cat)
                    }
                }
                processed.insert(member.id)
            }

            // Apply merged data to the kept entry
            for (catKey, items) in mergedOfferings where !items.isEmpty {
                if let cat = SpotCategory(rawValue: catKey) {
                    _ = await addOfferings(spotID: keeper.id, category: cat, newOfferings: items)
                }
            }
            if allCategories.count > keeper.categories.count {
                _ = await addCategories(spotID: keeper.id, newCategories: allCategories)
            }

            // Delete all other entries
            for member in groupSpots where member.id != keeper.id {
                _ = await deleteSpot(spotID: member.id)
            }
        }
    }

    // MARK: - Backfill: mark user-added spots as verified

    /// One-time migration: any spot added by a real user (source == nil) that
    /// isn't already communityVerified gets flipped to true.  No-ops once all
    /// user-added spots are verified.
    private func backfillUserAddedVerification() async {
        for spot in spots where spot.source == nil && !spot.communityVerified {
            do {
                let data: [String: Any] = ["communityVerified": true]
                try await db.collection(collectionName).document(spot.id).updateData(data)
                if let index = spots.firstIndex(where: { $0.id == spot.id }) {
                    spots[index].communityVerified = true
                }
            } catch {
                // Permission denied or network error — stop the entire batch
                // to avoid flooding Firestore with 75+ doomed write attempts
                // that pile up and freeze the app.
                #if DEBUG
                print("[Backfill] Verification backfill aborted after error: \(error.localizedDescription)")
                #endif
                return
            }
        }
    }

    // MARK: - Backfill Geohash for Analytics

    /// Sets `geohash4` on spots that don't have one yet. Used for regional
    /// analytics grouping (~20 km cells). Non-fatal — will retry next launch.
    private func backfillGeohash() async {
        for spot in spots where spot.geohash4 == nil {
            let hash = Geohash.encode(latitude: spot.latitude, longitude: spot.longitude)
            do {
                try await db.collection(collectionName).document(spot.id).updateData([
                    "geohash4": hash
                ])
                if let index = spots.firstIndex(where: { $0.id == spot.id }) {
                    spots[index].geohash4 = hash
                }
            } catch {
                // Permission denied or network error — stop the entire batch
                // to avoid flooding Firestore with doomed write attempts.
                #if DEBUG
                print("[Backfill] Geohash backfill aborted after error: \(error.localizedDescription)")
                #endif
                return
            }
        }
    }

    // MARK: - Add a Spot

    func addSpot(_ spot: Spot) async -> Bool {
        do {
            try db.collection(collectionName).document(spot.id).setData(from: spot)
            spots.insert(spot, at: 0)
            return true
        } catch {
            errorMessage = "Failed to add spot: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.addSpot")
            return false
        }
    }

    // MARK: - Find Existing Spot (duplicate detection)

    func findExistingSpot(name: String, latitude: Double, longitude: Double) -> Spot? {
        // Match by name similarity and proximity (within ~550 meters)
        let threshold = 0.005 // ~550 meters — catches geocoding variance between sources
        return spots.first { spot in
            spot.name.localizedCaseInsensitiveContains(name) &&
            abs(spot.latitude - latitude) < threshold &&
            abs(spot.longitude - longitude) < threshold
        }
    }

    // MARK: - Add Offerings to Existing Spot

    /// Add offerings for a specific category. Mezcal offerings are also mirrored
    /// to the legacy "mezcalOfferings" field for backward compatibility.
    func addOfferings(spotID: String, category: SpotCategory, newOfferings: [String]) async -> Bool {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return false }

        let existing = spots[index].offerings(for: category)
        var merged = existing
        for offering in newOfferings {
            let trimmed = offering.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !merged.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                merged.append(trimmed)
            }
        }

        do {
            var allOfferings = spots[index].offerings ?? [:]
            allOfferings[category.rawValue] = merged
            var data: [String: Any] = ["offerings": allOfferings]
            // Legacy compat: also write mezcalOfferings for mezcal
            if category == .mezcal {
                data["mezcalOfferings"] = merged
            }
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].offerings = allOfferings
            return true
        } catch {
            errorMessage = "Failed to update offerings: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.addOfferings")
            return false
        }
    }

    /// Legacy wrapper — calls addOfferings for mezcal category.
    func addMezcalOfferings(spotID: String, newOfferings: [String]) async -> Bool {
        await addOfferings(spotID: spotID, category: .mezcal, newOfferings: newOfferings)
    }

    // MARK: - Update Spot Rating

    func updateSpotRating(spotID: String, newAverage: Double, newCount: Int) async {
        do {
            let data: [String: Any] = ["averageRating": newAverage, "reviewCount": newCount]
            try await db.collection(collectionName).document(spotID).updateData(data)
            if let index = spots.firstIndex(where: { $0.id == spotID }) {
                spots[index].averageRating = newAverage
                spots[index].reviewCount = newCount
            }
        } catch {
            errorMessage = "Failed to update rating: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.updateSpotRating")
        }
    }

    /// Updates per-category rating and recalculates the overall spot average.
    func updateCategoryRating(spotID: String, category: String,
                               newAverage: Double, newCount: Int) async {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return }

        // Build updated per-category map
        var ratings = spots[index].categoryRatings ?? [:]
        ratings[category] = CategoryRating(average: newAverage, count: newCount)

        // Recalculate overall from all categories (weighted average)
        var totalReviews = 0
        var weightedSum = 0.0
        for entry in ratings.values {
            totalReviews += entry.count
            weightedSum += entry.average * Double(entry.count)
        }
        let overallAverage = totalReviews > 0 ? weightedSum / Double(totalReviews) : 0.0

        do {
            // Encode categoryRatings to Firestore-compatible format
            var catRatingsData: [String: [String: Any]] = [:]
            for (key, val) in ratings {
                catRatingsData[key] = ["average": val.average, "count": val.count]
            }
            let data: [String: Any] = [
                "categoryRatings": catRatingsData,
                "averageRating": overallAverage,
                "reviewCount": totalReviews
            ]
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].categoryRatings = ratings
            spots[index].averageRating = overallAverage
            spots[index].reviewCount = totalReviews
        } catch {
            errorMessage = "Failed to update category rating: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.updateCategoryRating")
        }
    }

    // MARK: - Report a Spot

    func reportSpot(spotID: String, reporterUserID: String) async {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return }

        // Prevent duplicate reports
        if spots[index].reportedByUserIDs.contains(reporterUserID) {
            errorMessage = "You have already reported this spot."
            return
        }

        // Prevent reporting your own spot
        if spots[index].addedByUserID == reporterUserID {
            errorMessage = "You cannot report your own spot."
            return
        }

        let newCount = spots[index].reportCount + 1
        let shouldHide = newCount >= 3

        do {
            let data: [String: Any] = [
                "isReported": true,
                "reportCount": newCount,
                "reportedByUserIDs": FieldValue.arrayUnion([reporterUserID]),
                "isHidden": shouldHide
            ]
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].isReported = true
            spots[index].reportCount = newCount
            spots[index].reportedByUserIDs.append(reporterUserID)
            spots[index].isHidden = shouldHide
        } catch {
            errorMessage = "Failed to report spot: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.reportSpot")
        }
    }

    // MARK: - Hide a Spot (soft delete by owner)

    /// Hides a spot by setting isHidden = true. Used when the spot creator
    /// removes the last category — the spot disappears from all lists but
    /// the Firestore document is preserved so it can be restored if needed.
    func hideSpot(spotID: String) async {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return }
        do {
            let data: [String: Any] = ["isHidden": true]
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].isHidden = true
        } catch {
            errorMessage = "Failed to hide spot: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.hideSpot")
        }
    }

    // MARK: - Delete a Spot

    func deleteSpot(spotID: String) async -> Bool {
        do {
            try await db.collection(collectionName).document(spotID).delete()
            spots.removeAll { $0.id == spotID }
            return true
        } catch {
            errorMessage = "Failed to delete spot: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.deleteSpot")
            return false
        }
    }

    // MARK: - Filter Spots by Category

    func filteredSpots(for filter: SpotFilter) -> [Spot] {
        guard let category = filter.category else {
            return spots.filter { !$0.isHidden && !$0.isClosed }
        }
        return spots.filter { $0.matchesFilter(category) && !$0.isHidden && !$0.isClosed }
    }

    // MARK: - Community Verification (imported spots)

    /// Flips `communityVerified` to true on a spot that was seeded from an external
    /// source (source != nil).  Idempotent — safe to call multiple times.
    /// Also clears any accumulated flags so a legitimate re-confirmation resets
    /// the soft-warning state (abuse protection: the report threshold still applies).
    func markCommunityVerified(spotID: String) async {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return }
        guard !spots[index].communityVerified else { return }  // Already verified — no-op

        do {
            let data: [String: Any] = [
                "communityVerified": true,
                // Clear accumulated flags so the warning banner is dismissed
                "isReported": false,
                "reportCount": 0,
                "reportedByUserIDs": [String](),
                "isHidden": false
            ]
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].communityVerified = true
            spots[index].isReported = false
            spots[index].reportCount = 0
            spots[index].reportedByUserIDs = []
            spots[index].isHidden = false
        } catch {
            errorMessage = "Failed to verify spot: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.verifySpot")
        }
    }

    // MARK: - Add Category to Existing Spot

    /// Adds new categories to an existing spot (e.g., adding flan to a mezcal spot).
    /// When `addedBy` is provided, records per-category attribution in `categoryAddedBy`.
    func addCategories(spotID: String, newCategories: [SpotCategory], addedBy userID: String? = nil) async -> Bool {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return false }

        var merged = spots[index].categories
        var attribution = spots[index].categoryAddedBy ?? [:]
        for cat in newCategories {
            if !merged.contains(cat) {
                merged.append(cat)
                if let userID {
                    attribution[cat.rawValue] = userID
                }
            }
        }

        // No change needed
        if merged.count == spots[index].categories.count { return true }

        do {
            let rawCategories = merged.map { $0.rawValue }
            var data: [String: Any] = ["categories": rawCategories]
            if !attribution.isEmpty {
                data["categoryAddedBy"] = attribution
            }
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].categories = merged
            spots[index].categoryAddedBy = attribution.isEmpty ? nil : attribution
            return true
        } catch {
            errorMessage = "Failed to update categories: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.addCategory")
            return false
        }
    }

    // MARK: - Remove Category from Existing Spot

    /// Removes a category from an existing spot. The spot must have at least 2 categories
    /// (cannot remove the last one). Also cleans up the `categoryAddedBy` attribution entry.
    func removeCategory(spotID: String, category: SpotCategory) async -> Bool {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return false }
        guard spots[index].categories.count > 1 else { return false }

        var updated = spots[index].categories
        updated.removeAll { $0 == category }

        // Safety: don't leave an empty array
        guard !updated.isEmpty else { return false }

        do {
            let rawCategories = updated.map { $0.rawValue }
            var data: [String: Any] = ["categories": rawCategories]

            // Clean up per-category attribution
            var attribution = spots[index].categoryAddedBy ?? [:]
            attribution.removeValue(forKey: category.rawValue)
            data["categoryAddedBy"] = attribution.isEmpty ? FieldValue.delete() : attribution

            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].categories = updated
            spots[index].categoryAddedBy = attribution.isEmpty ? nil : attribution
            return true
        } catch {
            errorMessage = "Failed to remove category: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.removeCategory")
            return false
        }
    }

    // MARK: - Owner Verified — Update Owner Fields

    /// Updates the owner-editable fields on a spot. Only the verified owner
    /// (spot.ownerUserId matching the current user) should call this.
    func updateOwnerFields(
        spotID: String,
        ownerBrands: [String]?,
        ownerDetails: String?,
        reservationURL: String?,
        ownerLockedCategories: [String]?
    ) async -> Bool {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return false }

        do {
            var data: [String: Any] = [:]
            // Use FieldValue.delete() for nil/empty values to keep Firestore clean
            if let brands = ownerBrands, !brands.isEmpty {
                data["ownerBrands"] = brands
            } else {
                data["ownerBrands"] = FieldValue.delete()
            }
            if let details = ownerDetails, !details.isEmpty {
                data["ownerDetails"] = details
            } else {
                data["ownerDetails"] = FieldValue.delete()
            }
            if let url = reservationURL, !url.isEmpty {
                data["reservationURL"] = url
            } else {
                data["reservationURL"] = FieldValue.delete()
            }
            if let locked = ownerLockedCategories, !locked.isEmpty {
                data["ownerLockedCategories"] = locked
            } else {
                data["ownerLockedCategories"] = FieldValue.delete()
            }

            try await db.collection(collectionName).document(spotID).updateData(data)

            // Update local model
            spots[index].ownerBrands = ownerBrands?.isEmpty == true ? nil : ownerBrands
            spots[index].ownerDetails = ownerDetails?.isEmpty == true ? nil : ownerDetails
            spots[index].reservationURL = reservationURL?.isEmpty == true ? nil : reservationURL
            spots[index].ownerLockedCategories = ownerLockedCategories?.isEmpty == true ? nil : ownerLockedCategories
            return true
        } catch {
            errorMessage = "Failed to update owner fields: \(error.localizedDescription)"
            CrashReporter.record(error, context: "SpotService.updateOwnerFields")
            return false
        }
    }

    // MARK: - Update Verification Tallies Locally

    /// Updates the local spot's verification tally counts after a vote so the UI
    /// reflects the change immediately (Firestore is already updated by VerificationService).
    ///
    /// Three cases:
    /// - `previousVote == nil`: new vote → increment the matching tally
    /// - `previousVote != vote`: flip → decrement old, increment new
    /// - `previousVote == vote`: retract → decrement the matching tally
    func updateVerificationTallies(spotID: String, category: SpotCategory, vote: Bool, previousVote: Bool?) {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return }

        let catKey = category.rawValue

        // Ensure dictionaries exist
        if spots[index].verificationUpCount == nil {
            spots[index].verificationUpCount = [:]
        }
        if spots[index].verificationDownCount == nil {
            spots[index].verificationDownCount = [:]
        }

        if let previousVote = previousVote {
            if previousVote == vote {
                // Retract — user tapped the same vote again, remove it
                if vote {
                    spots[index].verificationUpCount?[catKey, default: 0] -= 1
                } else {
                    spots[index].verificationDownCount?[catKey, default: 0] -= 1
                }
            } else {
                // Flip — decrement old, increment new
                if vote {
                    spots[index].verificationUpCount?[catKey, default: 0] += 1
                    spots[index].verificationDownCount?[catKey, default: 0] -= 1
                } else {
                    spots[index].verificationUpCount?[catKey, default: 0] -= 1
                    spots[index].verificationDownCount?[catKey, default: 0] += 1
                }
            }
        } else {
            // New vote
            if vote {
                spots[index].verificationUpCount?[catKey, default: 0] += 1
            } else {
                spots[index].verificationDownCount?[catKey, default: 0] += 1
            }
        }

        spots[index].lastVerificationDate = Date()
    }
}
