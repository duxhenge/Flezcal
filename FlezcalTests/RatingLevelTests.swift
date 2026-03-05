import XCTest
@testable import Flezcal

final class RatingLevelTests: XCTestCase {

    // MARK: - All cases exist

    func testAllCasesCount() {
        XCTAssertEqual(RatingLevel.allCases.count, 5)
    }

    // MARK: - Raw values map 1-5

    func testRawValues() {
        XCTAssertEqual(RatingLevel.youDecide.rawValue, 1)
        XCTAssertEqual(RatingLevel.popIn.rawValue, 2)
        XCTAssertEqual(RatingLevel.bookIt.rawValue, 3)
        XCTAssertEqual(RatingLevel.roadTrip.rawValue, 4)
        XCTAssertEqual(RatingLevel.pilgrimage.rawValue, 5)
    }

    // MARK: - Labels

    func testLabels() {
        XCTAssertEqual(RatingLevel.youDecide.label, "You Decide")
        XCTAssertEqual(RatingLevel.pilgrimage.label, "Pilgrimage")
    }

    // MARK: - Emoji scale

    func testEmojiCounts() {
        XCTAssertEqual(RatingLevel.youDecide.emoji.filter { $0 == "🍮" }.count, 1)
        XCTAssertEqual(RatingLevel.pilgrimage.emoji.filter { $0 == "🍮" }.count, 5)
    }

    // MARK: - Compact emoji

    func testCompactEmoji() {
        XCTAssertEqual(RatingLevel.bookIt.compactEmoji, "3🍮")
    }

    // MARK: - From Int

    func testFromInt_validRange() {
        for i in 1...5 {
            XCTAssertNotNil(RatingLevel.from(i))
        }
    }

    func testFromInt_outOfRange() {
        XCTAssertNil(RatingLevel.from(0))
        XCTAssertNil(RatingLevel.from(6))
        XCTAssertNil(RatingLevel.from(-1))
    }

    // MARK: - Descriptions are non-empty

    func testDescriptions() {
        for level in RatingLevel.allCases {
            XCTAssertFalse(level.description.isEmpty)
        }
    }

    // MARK: - Confirmation questions

    func testConfirmationQuestions() {
        XCTAssertEqual(
            RatingLevel.pilgrimage.confirmationQuestion(for: "Mezcal"),
            "Is the mezcal here worth booking a flight?"
        )
        XCTAssertEqual(
            RatingLevel.roadTrip.confirmationQuestion(for: "Flan"),
            "Is the flan here worth going out of your way?"
        )
        XCTAssertEqual(
            RatingLevel.bookIt.confirmationQuestion(for: "Handmade Tortillas"),
            "Does the handmade tortillas here satisfy the craving?"
        )
        XCTAssertEqual(
            RatingLevel.popIn.confirmationQuestion(for: "Bourbon"),
            "Are you glad the bourbon is on the menu here?"
        )
        XCTAssertEqual(
            RatingLevel.youDecide.confirmationQuestion(for: "Paella"),
            "You can't recommend the paella here?"
        )
    }

    func testConfirmationQuestionLowercasesCategory() {
        XCTAssertEqual(
            RatingLevel.pilgrimage.confirmationQuestion(for: "MEZCAL"),
            "Is the mezcal here worth booking a flight?"
        )
    }
}
