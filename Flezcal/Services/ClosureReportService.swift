import Foundation
import FirebaseFirestore

@MainActor
class ClosureReportService: ObservableObject {
    @Published var reports: [ClosureReport] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let collectionName = FirestoreCollections.closureReports

    // MARK: - Fetch Reports for a Spot

    func fetchReports(for spotID: String) async {
        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("spotID", isEqualTo: spotID)
                .getDocuments()

            reports = snapshot.documents
                .compactMap { try? $0.data(as: ClosureReport.self) }
                .sorted { $0.date > $1.date }
        } catch {
            errorMessage = "Failed to load closure reports: \(error.localizedDescription)"
        }
    }

    // MARK: - Fetch All Pending Reports (for admin dashboard)

    func fetchPendingReports() async {
        isLoading = true
        do {
            let snapshot = try await db.collection(collectionName)
                .getDocuments()

            reports = snapshot.documents
                .compactMap { try? $0.data(as: ClosureReport.self) }
                .filter { $0.adminAction == nil }
                .sorted { $0.date < $1.date }  // oldest first for admin review
        } catch {
            errorMessage = "Failed to load closure reports: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Check if User Already Reported

    func hasUserReported(userID: String) -> Bool {
        reports.contains { $0.reporterUserID == userID }
    }

    // MARK: - Submit Closure Report

    func submitReport(spotID: String, spotName: String, spotAddress: String, reporterUserID: String) async -> Bool {
        guard await RateLimiter.shared.allowAction("closure-\(spotID)", cooldown: 5.0) else {
            return false
        }

        // Extract city from address (take last component before state/zip or use full address)
        let city = extractCity(from: spotAddress)

        let report = ClosureReport(
            spotID: spotID,
            spotName: spotName,
            spotCity: city,
            reporterUserID: reporterUserID,
            date: Date()
        )

        do {
            try db.collection(collectionName).document(report.id).setData(from: report)

            // Increment closure report count on the spot
            try await db.collection(FirestoreCollections.spots).document(spotID).updateData([
                "closureReportCount": FieldValue.increment(Int64(1))
            ])

            reports.insert(report, at: 0)
            return true
        } catch {
            errorMessage = "Failed to submit closure report: \(error.localizedDescription)"
            CrashReporter.record(error, context: "ClosureReportService.submitReport")
            return false
        }
    }

    // MARK: - Admin Actions

    /// Admin confirms the spot is permanently closed.
    /// Sets locationStatus = "closed" on the spot document.
    func confirmClosure(spotID: String) async -> Bool {
        do {
            // Update spot
            try await db.collection(FirestoreCollections.spots).document(spotID).updateData([
                "locationStatus": "closed",
                "closureReportCount": 0
            ])

            // Mark all reports for this spot as confirmed
            let reportsForSpot = reports.filter { $0.spotID == spotID }
            for report in reportsForSpot {
                try await db.collection(collectionName).document(report.id).updateData([
                    "adminAction": "confirmed",
                    "adminActionDate": Date()
                ])
            }

            // Update local state
            reports.removeAll { $0.spotID == spotID }
            return true
        } catch {
            errorMessage = "Failed to confirm closure: \(error.localizedDescription)"
            CrashReporter.record(error, context: "ClosureReportService.confirmClosure")
            return false
        }
    }

    /// Admin dismisses closure reports for a spot.
    /// Resets closureReportCount to 0 on the spot document.
    func dismissReports(spotID: String) async -> Bool {
        do {
            // Reset spot
            try await db.collection(FirestoreCollections.spots).document(spotID).updateData([
                "closureReportCount": 0
            ])

            // Mark all reports for this spot as dismissed
            let reportsForSpot = reports.filter { $0.spotID == spotID }
            for report in reportsForSpot {
                try await db.collection(collectionName).document(report.id).updateData([
                    "adminAction": "dismissed",
                    "adminActionDate": Date()
                ])
            }

            // Update local state
            reports.removeAll { $0.spotID == spotID }
            return true
        } catch {
            errorMessage = "Failed to dismiss reports: \(error.localizedDescription)"
            CrashReporter.record(error, context: "ClosureReportService.dismissReports")
            return false
        }
    }

    // MARK: - Helpers

    /// Extracts city name from a full address string.
    /// e.g. "123 Main St, Somerville, MA 02143" → "Somerville"
    private func extractCity(from address: String) -> String {
        let components = address.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        // Typically: [street, city, state+zip] — take the second component if available
        if components.count >= 2 {
            return components[1]
        }
        return address
    }
}
