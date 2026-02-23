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
        } catch {
            errorMessage = "Failed to load spots: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Clean Up Comma-Separated Mezcal Entries

    /// Finds any mezcalOfferings entries that contain commas (bulk-entered),
    /// splits them into individual brands, and re-saves the cleaned list.
    /// Safe to call on every launch — no-ops if data is already clean.
    func cleanupCommaSeparatedMezcals() async {
        for spot in spots {
            guard let offerings = spot.mezcalOfferings, !offerings.isEmpty else { continue }

            // Split any entry that contains a comma
            var expanded: [String] = []
            for entry in offerings {
                let parts = entry.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
                expanded.append(contentsOf: parts)
            }

            // Deduplicate (case-insensitive)
            var cleaned: [String] = []
            for brand in expanded {
                if !cleaned.contains(where: { $0.localizedCaseInsensitiveCompare(brand) == .orderedSame }) {
                    cleaned.append(brand)
                }
            }

            // Only update if the content actually changed (count or entries differ)
            let cleanedSet = Set(cleaned.map { $0.lowercased() })
            let originalSet = Set(offerings.map { $0.lowercased() })
            guard cleanedSet != originalSet || cleaned.count != offerings.count else { continue }

            do {
                let data: [String: Any] = ["mezcalOfferings": cleaned]
                try await db.collection(collectionName).document(spot.id).updateData(data)
                if let index = spots.firstIndex(where: { $0.id == spot.id }) {
                    spots[index].mezcalOfferings = cleaned
                }
            } catch {
                // Non-fatal — will retry next launch
            }
        }
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

            // Merge ALL mezcal offerings from every entry in the group
            var allOfferings: [String] = []
            var allCategories: [SpotCategory] = []
            for member in groupSpots {
                for offering in member.mezcalOfferings ?? [] {
                    let trimmed = offering.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !allOfferings.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                        allOfferings.append(trimmed)
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
            if !allOfferings.isEmpty {
                _ = await addMezcalOfferings(spotID: keeper.id, newOfferings: allOfferings)
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
                // Non-fatal — will retry next launch
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

    // MARK: - Add Mezcals to Existing Spot

    func addMezcalOfferings(spotID: String, newOfferings: [String]) async -> Bool {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return false }

        let existingOfferings = spots[index].mezcalOfferings ?? []
        // Merge and deduplicate (case-insensitive)
        var merged = existingOfferings
        for offering in newOfferings {
            let trimmed = offering.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !merged.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                merged.append(trimmed)
            }
        }

        do {
            let data: [String: Any] = ["mezcalOfferings": merged]
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].mezcalOfferings = merged
            return true
        } catch {
            errorMessage = "Failed to update mezcal offerings: \(error.localizedDescription)"
            return false
        }
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
        }
    }

    // MARK: - Update Mezcal Offerings

    func updateMezcalOfferings(spotID: String, offerings: [String]) async {
        do {
            let data: [String: Any] = ["mezcalOfferings": offerings]
            try await db.collection(collectionName).document(spotID).updateData(data)
            if let index = spots.firstIndex(where: { $0.id == spotID }) {
                spots[index].mezcalOfferings = offerings
            }
        } catch {
            errorMessage = "Failed to update offerings: \(error.localizedDescription)"
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
            return false
        }
    }

    // MARK: - Filter Spots by Category

    func filteredSpots(for filter: SpotFilter) -> [Spot] {
        guard let category = filter.category else {
            return spots.filter { !$0.isHidden }
        }
        return spots.filter { $0.matchesFilter(category) && !$0.isHidden }
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
        }
    }

    // MARK: - Add Category to Existing Spot

    /// Adds a new category to an existing spot (e.g., adding flan to a mezcal spot)
    func addCategories(spotID: String, newCategories: [SpotCategory]) async -> Bool {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return false }

        var merged = spots[index].categories
        for cat in newCategories {
            if !merged.contains(cat) {
                merged.append(cat)
            }
        }

        // No change needed
        if merged.count == spots[index].categories.count { return true }

        do {
            let rawCategories = merged.map { $0.rawValue }
            let data: [String: Any] = ["categories": rawCategories]
            try await db.collection(collectionName).document(spotID).updateData(data)
            spots[index].categories = merged
            return true
        } catch {
            errorMessage = "Failed to update categories: \(error.localizedDescription)"
            return false
        }
    }
}
