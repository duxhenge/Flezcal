import XCTest
@testable import Flezcal

final class CustomCategoryTests: XCTestCase {

    // MARK: - Keyword Generation

    func testSuggestedKeywords_singleWord() {
        let keywords = CustomCategory.suggestedKeywords(for: "Empanadas")
        XCTAssertTrue(keywords.contains("empanadas"))
        // Already ends in "s" so no plural added
        XCTAssertFalse(keywords.contains("empanadass"))
    }

    func testSuggestedKeywords_singleWordNoPlural() {
        let keywords = CustomCategory.suggestedKeywords(for: "Flan")
        XCTAssertTrue(keywords.contains("flan"))
        XCTAssertTrue(keywords.contains("flans"))
    }

    func testSuggestedKeywords_multiWord() {
        let keywords = CustomCategory.suggestedKeywords(for: "Peameal Bacon")
        XCTAssertTrue(keywords.contains("peameal bacon"))
        XCTAssertTrue(keywords.contains("peameal bacon" + "s"))
        // "peameal" is 7 chars (≥ 4), should be included as individual keyword
        XCTAssertTrue(keywords.contains("peameal"))
        // "bacon" is in the tooGeneric set, should NOT be included
        XCTAssertFalse(keywords.contains("bacon"))
    }

    func testSuggestedKeywords_shortWordsFiltered() {
        let keywords = CustomCategory.suggestedKeywords(for: "Pad Thai")
        XCTAssertTrue(keywords.contains("pad thai"))
        // "pad" is 3 chars (< 4), "thai" is 4 chars — only "thai" should be an individual keyword
        XCTAssertFalse(keywords.contains("pad"))
        XCTAssertTrue(keywords.contains("thai"))
    }

    func testSuggestedKeywords_empty() {
        let keywords = CustomCategory.suggestedKeywords(for: "   ")
        XCTAssertTrue(keywords.isEmpty)
    }

    // MARK: - Alcoholic Detection

    func testIsLikelyAlcoholic_exactMatches() {
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("whiskey"))
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("mezcal"))
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("sake"))
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("ipa"))
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("champagne"))
    }

    func testIsLikelyAlcoholic_compoundNames() {
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("Japanese Whisky"))
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("Craft Cocktails"))
        XCTAssertTrue(CustomCategory.isLikelyAlcoholic("Natural Wine"))
    }

    func testIsLikelyAlcoholic_nonAlcoholic() {
        XCTAssertFalse(CustomCategory.isLikelyAlcoholic("flan"))
        XCTAssertFalse(CustomCategory.isLikelyAlcoholic("tacos"))
        XCTAssertFalse(CustomCategory.isLikelyAlcoholic("empanadas"))
        XCTAssertFalse(CustomCategory.isLikelyAlcoholic("ramen"))
    }

    func testIsLikelyWine() {
        XCTAssertTrue(CustomCategory.isLikelyWine("natural wine"))
        XCTAssertTrue(CustomCategory.isLikelyWine("prosecco"))
        XCTAssertFalse(CustomCategory.isLikelyWine("bourbon"))
        XCTAssertFalse(CustomCategory.isLikelyWine("craft beer"))
    }

    func testIsLikelyBeer() {
        XCTAssertTrue(CustomCategory.isLikelyBeer("craft beer"))
        XCTAssertTrue(CustomCategory.isLikelyBeer("ipa"))
        XCTAssertTrue(CustomCategory.isLikelyBeer("stout"))
        XCTAssertFalse(CustomCategory.isLikelyBeer("mezcal"))
        XCTAssertFalse(CustomCategory.isLikelyBeer("wine"))
    }

    // MARK: - Map Search Terms

    func testCreate_alcoholic_addsBarAndLiquorStore() {
        let cat = CustomCategory.create(displayName: "Bourbon", emoji: "🥃", createdBy: "user1")
        XCTAssertTrue(cat.mapSearchTerms.contains("bar"))
        XCTAssertTrue(cat.mapSearchTerms.contains("liquor store"))
        XCTAssertFalse(cat.mapSearchTerms.contains("cafe"))
    }

    func testCreate_wine_addsWineShop() {
        let cat = CustomCategory.create(displayName: "Natural Wine", emoji: "🍷", createdBy: "user1")
        XCTAssertTrue(cat.mapSearchTerms.contains("wine shop"))
        XCTAssertTrue(cat.mapSearchTerms.contains("bar"))
    }

    func testCreate_beer_addsBrewery() {
        let cat = CustomCategory.create(displayName: "Craft Beer", emoji: "🍺", createdBy: "user1")
        XCTAssertTrue(cat.mapSearchTerms.contains("brewery"))
    }

    func testCreate_food_addsRestaurantAndCafe() {
        let cat = CustomCategory.create(displayName: "Empanadas", emoji: "🥟", createdBy: "user1")
        XCTAssertTrue(cat.mapSearchTerms.contains("restaurant"))
        XCTAssertTrue(cat.mapSearchTerms.contains("cafe"))
        XCTAssertFalse(cat.mapSearchTerms.contains("bar"))
    }

    // MARK: - Blocked Content Detection

    func testIsBlocked_exactMatch() {
        XCTAssertTrue(CustomCategory.isBlocked("cat"))
        XCTAssertTrue(CustomCategory.isBlocked("dog"))
        XCTAssertTrue(CustomCategory.isBlocked("human"))
    }

    func testIsBlocked_substringMatch() {
        XCTAssertTrue(CustomCategory.isBlocked("human meat pie"))
        XCTAssertTrue(CustomCategory.isBlocked("roadkill surprise"))
    }

    func testIsBlocked_legitimateFood() {
        XCTAssertFalse(CustomCategory.isBlocked("flan"))
        XCTAssertFalse(CustomCategory.isBlocked("empanadas"))
        XCTAssertFalse(CustomCategory.isBlocked("lobster rolls"))
        XCTAssertFalse(CustomCategory.isBlocked("mezcal"))
    }

    // MARK: - Validation

    func testValidate_tooShort() {
        XCTAssertNotNil(CustomCategory.validate("a"))
    }

    func testValidate_tooLong() {
        let long = String(repeating: "a", count: 31)
        XCTAssertNotNil(CustomCategory.validate(long))
    }

    func testValidate_genericTerms() {
        XCTAssertNotNil(CustomCategory.validate("food"))
        XCTAssertNotNil(CustomCategory.validate("restaurant"))
        XCTAssertNotNil(CustomCategory.validate("seafood"))
    }

    func testValidate_existingCategory() {
        // SpotCategory already has these
        XCTAssertNotNil(CustomCategory.validate("mezcal"))
        XCTAssertNotNil(CustomCategory.validate("flan"))
    }

    func testValidate_valid() {
        XCTAssertNil(CustomCategory.validate("Empanadas"))
        XCTAssertNil(CustomCategory.validate("Poutine"))
    }

    // MARK: - FoodCategory Conversion

    func testToFoodCategory() {
        let custom = CustomCategory.create(displayName: "Empanadas", emoji: "🥟", createdBy: "user1")
        let food = custom.toFoodCategory()

        XCTAssertEqual(food.id, "custom_empanadas")
        XCTAssertEqual(food.displayName, "Empanadas")
        XCTAssertEqual(food.emoji, "🥟")
        XCTAssertFalse(food.websiteKeywords.isEmpty)
        XCTAssertFalse(food.mapSearchTerms.isEmpty)
    }

    // MARK: - Equatable / Identity

    func testEquality_byNormalizedName() {
        let a = CustomCategory.create(displayName: "Empanadas", emoji: "🥟", createdBy: "user1")
        let b = CustomCategory.create(displayName: "empanadas", emoji: "🍴", createdBy: "user2")
        XCTAssertEqual(a, b, "CustomCategories with the same normalizedName should be equal")
    }

    func testID_isNormalizedName() {
        let cat = CustomCategory.create(displayName: "Pad Thai", emoji: "🍜", createdBy: "user1")
        XCTAssertEqual(cat.id, "pad thai")
    }
}
