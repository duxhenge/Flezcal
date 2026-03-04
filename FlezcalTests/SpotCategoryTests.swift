import XCTest
@testable import Flezcal

final class SpotCategoryTests: XCTestCase {

    // MARK: - All cases have required properties

    func testAllCases_haveDisplayName() {
        for cat in SpotCategory.allCases {
            XCTAssertFalse(cat.displayName.isEmpty, "\(cat.rawValue) missing displayName")
        }
    }

    func testAllCases_haveEmoji() {
        for cat in SpotCategory.allCases {
            XCTAssertFalse(cat.emoji.isEmpty, "\(cat.rawValue) missing emoji")
        }
    }

    func testAllCases_haveIcon() {
        for cat in SpotCategory.allCases {
            XCTAssertFalse(cat.icon.isEmpty, "\(cat.rawValue) missing icon")
        }
    }

    func testAllCases_haveWebsiteKeywords() {
        for cat in SpotCategory.allCases {
            XCTAssertFalse(cat.websiteKeywords.isEmpty,
                           "\(cat.rawValue) missing websiteKeywords")
        }
    }

    func testAllCases_haveAddSpotPrompt() {
        for cat in SpotCategory.allCases {
            XCTAssertFalse(cat.addSpotPrompt.isEmpty,
                           "\(cat.rawValue) missing addSpotPrompt")
        }
    }

    func testAllCases_haveOfferingsLabel() {
        for cat in SpotCategory.allCases {
            XCTAssertFalse(cat.offeringsLabel.isEmpty,
                           "\(cat.rawValue) missing offeringsLabel")
        }
    }

    // MARK: - Launch trio

    func testLaunchTrio_exists() {
        XCTAssertNotNil(SpotCategory(rawValue: "mezcal"))
        XCTAssertNotNil(SpotCategory(rawValue: "flan"))
        XCTAssertNotNil(SpotCategory(rawValue: "tortillas"))
    }

    // MARK: - Raw value stability (critical for Firestore)

    func testRawValues_stableForFirestore() {
        // These raw values are stored in Firestore — changing them would break existing data
        XCTAssertEqual(SpotCategory.mezcal.rawValue, "mezcal")
        XCTAssertEqual(SpotCategory.flan.rawValue, "flan")
        XCTAssertEqual(SpotCategory.tortillas.rawValue, "tortillas")
        XCTAssertEqual(SpotCategory.bourbon.rawValue, "bourbon")
        XCTAssertEqual(SpotCategory.oysters.rawValue, "oysters")
        XCTAssertEqual(SpotCategory.ramen.rawValue, "ramen")
        XCTAssertEqual(SpotCategory.tacos.rawValue, "tacos")
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        for cat in SpotCategory.allCases {
            let data = try JSONEncoder().encode(cat)
            let decoded = try JSONDecoder().decode(SpotCategory.self, from: data)
            XCTAssertEqual(decoded, cat)
        }
    }

    // MARK: - supportsOfferings (all categories support it now)

    func testAllCategories_supportOfferings() {
        for cat in SpotCategory.allCases {
            XCTAssertTrue(cat.supportsOfferings, "\(cat.rawValue) should support offerings")
        }
    }
}
