import XCTest
@testable import Flezcal

final class SpotModelTests: XCTestCase {

    // MARK: - Helper: make a default Spot for tests

    private func makeSpot(
        categories: [SpotCategory] = [.flan],
        averageRating: Double = 0,
        reviewCount: Int = 0,
        categoryRatings: [String: CategoryRating]? = nil,
        offerings: [String: [String]]? = nil,
        verificationUpCount: [String: Int]? = nil,
        verificationDownCount: [String: Int]? = nil,
        websiteDetectedCategories: [String]? = nil,
        locationStatus: String? = nil,
        isOwnerVerified: Bool = false,
        ownerUserId: String? = nil,
        ownerLockedCategories: [String]? = nil,
        categoryAddedBy: [String: String]? = nil
    ) -> Spot {
        Spot(
            name: "Test Spot",
            address: "123 Main St, Boston, MA",
            latitude: 42.36,
            longitude: -71.06,
            mapItemName: "Test Spot",
            categories: categories,
            addedByUserID: "user1",
            addedDate: Date(),
            averageRating: averageRating,
            reviewCount: reviewCount,
            categoryRatings: categoryRatings,
            offerings: offerings,
            verificationUpCount: verificationUpCount,
            verificationDownCount: verificationDownCount,
            websiteDetectedCategories: websiteDetectedCategories,
            locationStatus: locationStatus,
            isOwnerVerified: ownerVerified,
            ownerUserId: ownerUserId,
            ownerLockedCategories: ownerLockedCategories,
            categoryAddedBy: categoryAddedBy
        )
    }

    // MARK: - Category Helpers

    func testHasFlan() {
        let spot = makeSpot(categories: [.flan, .mezcal])
        XCTAssertTrue(spot.hasFlan)
        XCTAssertTrue(spot.hasMezcal)
        XCTAssertFalse(spot.hasTortillas)
    }

    func testPrimaryCategory_bothFlanAndMezcal() {
        let spot = makeSpot(categories: [.flan, .mezcal])
        XCTAssertEqual(spot.primaryCategory, .mezcal, "Mezcal should win when both are present")
    }

    func testPrimaryCategory_singleCategory() {
        let spot = makeSpot(categories: [.tortillas])
        XCTAssertEqual(spot.primaryCategory, .tortillas)
    }

    func testPrimaryCategory_empty_defaultsToFlan() {
        let spot = makeSpot(categories: [])
        XCTAssertEqual(spot.primaryCategory, .flan)
    }

    func testMatchesFilter_nil_matchesAll() {
        let spot = makeSpot(categories: [.flan])
        XCTAssertTrue(spot.matchesFilter(nil))
    }

    func testMatchesFilter_matching() {
        let spot = makeSpot(categories: [.flan, .mezcal])
        XCTAssertTrue(spot.matchesFilter(.mezcal))
    }

    func testMatchesFilter_nonMatching() {
        let spot = makeSpot(categories: [.flan])
        XCTAssertFalse(spot.matchesFilter(.mezcal))
    }

    // MARK: - Offerings

    func testOfferingsForCategory() {
        let spot = makeSpot(offerings: ["mezcal": ["Del Maguey", "Vago"], "flan": ["Classic"]])
        XCTAssertEqual(spot.offerings(for: .mezcal), ["Del Maguey", "Vago"])
        XCTAssertEqual(spot.offerings(for: .flan), ["Classic"])
        XCTAssertEqual(spot.offerings(for: .tortillas), [])
    }

    func testHasAnyOfferings() {
        let empty = makeSpot(offerings: nil)
        XCTAssertFalse(empty.hasAnyOfferings)

        let withOfferings = makeSpot(offerings: ["mezcal": ["Vago"]])
        XCTAssertTrue(withOfferings.hasAnyOfferings)

        let emptyArrays = makeSpot(offerings: ["mezcal": []])
        XCTAssertFalse(emptyArrays.hasAnyOfferings)
    }

    func testMezcalOfferingsLegacyAccessor() {
        var spot = makeSpot(offerings: ["mezcal": ["Del Maguey"]])
        XCTAssertEqual(spot.mezcalOfferings, ["Del Maguey"])

        spot.mezcalOfferings = ["Vago", "Bozal"]
        XCTAssertEqual(spot.offerings?["mezcal"], ["Vago", "Bozal"])
    }

    // MARK: - Verification Status

    func testVerificationStatus_noVotes_unverified() {
        let spot = makeSpot()
        XCTAssertEqual(spot.verificationStatus(for: .flan), .unverified)
    }

    func testVerificationStatus_noVotes_websiteDetected_potential() {
        let spot = makeSpot(websiteDetectedCategories: ["flan"])
        XCTAssertEqual(spot.verificationStatus(for: .flan), .potential)
    }

    func testVerificationStatus_oneThumbsUp_confirmed() {
        let spot = makeSpot(verificationUpCount: ["flan": 1])
        XCTAssertEqual(spot.verificationStatus(for: .flan), .confirmed)
    }

    func testVerificationStatus_onlyThumbsDown_unverified() {
        let spot = makeSpot(verificationDownCount: ["flan": 3])
        XCTAssertEqual(spot.verificationStatus(for: .flan), .unverified)
    }

    func testVerificationStatus_lessThan10_anyThumbsUp_confirmed() {
        let spot = makeSpot(
            verificationUpCount: ["mezcal": 2],
            verificationDownCount: ["mezcal": 5]
        )
        // Total = 7 (< 10), ups > 0 → confirmed
        XCTAssertEqual(spot.verificationStatus(for: .mezcal), .confirmed)
    }

    func testVerificationStatus_10plus_above70percent() {
        let spot = makeSpot(
            verificationUpCount: ["flan": 8],
            verificationDownCount: ["flan": 2]
        )
        // 8/10 = 80% ≥ 70% → confirmed
        XCTAssertEqual(spot.verificationStatus(for: .flan), .confirmed)
    }

    func testVerificationStatus_10plus_below70percent() {
        let spot = makeSpot(
            verificationUpCount: ["flan": 6],
            verificationDownCount: ["flan": 5]
        )
        // 6/11 = 54.5% < 70% → unverified
        XCTAssertEqual(spot.verificationStatus(for: .flan), .unverified)
    }

    func testVerificationStatus_10plus_exactly70percent() {
        let spot = makeSpot(
            verificationUpCount: ["flan": 7],
            verificationDownCount: ["flan": 3]
        )
        // 7/10 = 70% ≥ 70% → confirmed
        XCTAssertEqual(spot.verificationStatus(for: .flan), .confirmed)
    }

    // MARK: - Badges

    func testIsHiddenGem_highRatingFewReviews() {
        let spot = makeSpot(averageRating: 4.8, reviewCount: 2)
        XCTAssertTrue(spot.isHiddenGem)
    }

    func testIsHiddenGem_highRatingManyReviews() {
        let spot = makeSpot(averageRating: 4.8, reviewCount: 10)
        XCTAssertFalse(spot.isHiddenGem)
    }

    func testIsHiddenGem_lowRating() {
        let spot = makeSpot(averageRating: 3.0, reviewCount: 1)
        XCTAssertFalse(spot.isHiddenGem)
    }

    func testIsHiddenGem_noReviews() {
        let spot = makeSpot(averageRating: 5.0, reviewCount: 0)
        XCTAssertFalse(spot.isHiddenGem)
    }

    func testIsHiddenGem_withCategoryRatings() {
        let spot = makeSpot(
            categoryRatings: ["mezcal": CategoryRating(average: 4.6, count: 2)]
        )
        XCTAssertTrue(spot.isHiddenGem)
    }

    func testIsClosed() {
        let open = makeSpot()
        XCTAssertFalse(open.isClosed)

        let closed = makeSpot(locationStatus: "closed")
        XCTAssertTrue(closed.isClosed)
    }

    // MARK: - Owner Helpers

    func testIsOwner() {
        let spot = makeSpot(isOwnerVerified: true, ownerUserId: "owner123")
        XCTAssertTrue(spot.isOwner(userID: "owner123"))
        XCTAssertFalse(spot.isOwner(userID: "otherUser"))
        XCTAssertFalse(spot.isOwner(userID: nil))
    }

    func testIsOwner_notVerified() {
        let spot = makeSpot(isOwnerVerified: false, ownerUserId: "owner123")
        XCTAssertFalse(spot.isOwner(userID: "owner123"))
    }

    func testIsCategoryLocked() {
        let spot = makeSpot(ownerLockedCategories: ["mezcal", "flan"])
        XCTAssertTrue(spot.isCategoryLocked(.mezcal))
        XCTAssertTrue(spot.isCategoryLocked(.flan))
        XCTAssertFalse(spot.isCategoryLocked(.tortillas))
    }

    // MARK: - Category Attribution

    func testCategoryAddedByUser_withAttribution() {
        let spot = makeSpot(categoryAddedBy: ["mezcal": "userA", "flan": "userB"])
        XCTAssertEqual(spot.categoryAddedByUser(.mezcal), "userA")
        XCTAssertEqual(spot.categoryAddedByUser(.flan), "userB")
    }

    func testCategoryAddedByUser_fallsBackToCreator() {
        let spot = makeSpot() // addedByUserID = "user1"
        XCTAssertEqual(spot.categoryAddedByUser(.flan), "user1")
    }

    func testCanRemoveCategory() {
        let spot = makeSpot(categoryAddedBy: ["mezcal": "userA"])
        XCTAssertTrue(spot.canRemoveCategory(.mezcal, userID: "userA"))
        XCTAssertFalse(spot.canRemoveCategory(.mezcal, userID: "userB"))
        XCTAssertFalse(spot.canRemoveCategory(.mezcal, userID: nil))
    }

    // MARK: - Photo URL Priority

    func testDisplayPhotoURL_prefersUserPhoto() {
        var spot = makeSpot()
        spot.photoURL = "auto.jpg"
        spot.userPhotoURL = "user.jpg"
        XCTAssertEqual(spot.displayPhotoURL, "user.jpg")
    }

    func testDisplayPhotoURL_fallsBackToAutoPhoto() {
        var spot = makeSpot()
        spot.photoURL = "auto.jpg"
        spot.userPhotoURL = nil
        XCTAssertEqual(spot.displayPhotoURL, "auto.jpg")
    }

    func testDisplayPhotoURL_nilWhenNoPhotos() {
        let spot = makeSpot()
        XCTAssertNil(spot.displayPhotoURL)
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        let original = makeSpot(
            categories: [.mezcal, .flan],
            averageRating: 4.5,
            reviewCount: 10,
            offerings: ["mezcal": ["Vago", "Del Maguey"]]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(Spot.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.categories, original.categories)
        XCTAssertEqual(decoded.averageRating, original.averageRating)
        XCTAssertEqual(decoded.reviewCount, original.reviewCount)
        XCTAssertEqual(decoded.offerings?["mezcal"], ["Vago", "Del Maguey"])
    }

    func testDecoding_legacyMezcalOfferings() throws {
        // Simulate old Firestore docs with "mezcalOfferings" instead of "offerings"
        let json = """
        {
            "id": "test1",
            "name": "Test",
            "address": "123 Main",
            "latitude": 42.36,
            "longitude": -71.06,
            "mapItemName": "Test",
            "categories": ["flan"],
            "addedByUserID": "user1",
            "addedDate": 1700000000,
            "averageRating": 4.0,
            "reviewCount": 5,
            "mezcalOfferings": ["Del Maguey", "Vago"]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let spot = try decoder.decode(Spot.self, from: json)

        XCTAssertEqual(spot.offerings?["mezcal"], ["Del Maguey", "Vago"],
                       "Legacy mezcalOfferings should be migrated to offerings dict")
    }

    func testDecoding_legacySingleCategory() throws {
        // Simulate old docs with single "category" field
        let json = """
        {
            "id": "test2",
            "name": "Test",
            "address": "123 Main",
            "latitude": 42.36,
            "longitude": -71.06,
            "mapItemName": "Test",
            "category": "mezcal",
            "addedByUserID": "user1",
            "addedDate": 1700000000,
            "averageRating": 3.5,
            "reviewCount": 2
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let spot = try decoder.decode(Spot.self, from: json)

        XCTAssertEqual(spot.categories, [.mezcal],
                       "Single legacy category should be wrapped in array")
    }
}
