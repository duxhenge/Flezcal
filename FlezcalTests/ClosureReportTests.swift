import XCTest
@testable import Flezcal

final class ClosureReportTests: XCTestCase {

    // MARK: - City Extraction (via ClosureReportService helper)

    /// Tests the city extraction logic that ClosureReportService uses.
    /// This mirrors the private `extractCity(from:)` method.
    func testCityExtraction_typicalAddress() {
        // "123 Main St, Somerville, MA 02143" → second component = "Somerville"
        let address = "123 Main St, Somerville, MA 02143"
        let city = extractCity(from: address)
        XCTAssertEqual(city, "Somerville")
    }

    func testCityExtraction_twoComponents() {
        let address = "Downtown, Boston"
        let city = extractCity(from: address)
        XCTAssertEqual(city, "Boston")
    }

    func testCityExtraction_singleComponent() {
        let address = "Boston"
        let city = extractCity(from: address)
        XCTAssertEqual(city, "Boston") // returns full address
    }

    func testCityExtraction_extraSpaces() {
        let address = "123 Main St ,  Cambridge , MA"
        let city = extractCity(from: address)
        XCTAssertEqual(city, "Cambridge")
    }

    // Mirror of the private helper for testing
    private func extractCity(from address: String) -> String {
        let components = address.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.count >= 2 {
            return components[1]
        }
        return address
    }

    // MARK: - Codable

    func testClosureReportCodable() throws {
        let report = ClosureReport(
            spotID: "spot1",
            spotName: "Test Spot",
            spotCity: "Boston",
            reporterUserID: "user1",
            date: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(report)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(ClosureReport.self, from: data)

        XCTAssertEqual(decoded.spotID, "spot1")
        XCTAssertEqual(decoded.spotName, "Test Spot")
        XCTAssertEqual(decoded.spotCity, "Boston")
        XCTAssertEqual(decoded.reporterUserID, "user1")
        XCTAssertNil(decoded.adminAction)
        XCTAssertNil(decoded.adminActionDate)
    }
}
