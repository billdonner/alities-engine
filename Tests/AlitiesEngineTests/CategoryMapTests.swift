import XCTest
@testable import AlitiesEngine

final class CategoryMapTests: XCTestCase {

    // MARK: - normalize

    func testNormalizeKnownAliases() {
        XCTAssertEqual(CategoryMap.normalize("science"), "Science & Nature")
        XCTAssertEqual(CategoryMap.normalize("nature"), "Science & Nature")
        XCTAssertEqual(CategoryMap.normalize("animals"), "Science & Nature")
        XCTAssertEqual(CategoryMap.normalize("technology"), "Technology")
        XCTAssertEqual(CategoryMap.normalize("science - computers"), "Technology")
        XCTAssertEqual(CategoryMap.normalize("mathematics"), "Mathematics")
        XCTAssertEqual(CategoryMap.normalize("history"), "History")
        XCTAssertEqual(CategoryMap.normalize("geography"), "Geography")
        XCTAssertEqual(CategoryMap.normalize("sports"), "Sports")
        XCTAssertEqual(CategoryMap.normalize("sport_and_leisure"), "Sports")
        XCTAssertEqual(CategoryMap.normalize("music"), "Music")
        XCTAssertEqual(CategoryMap.normalize("movies"), "Film & TV")
        XCTAssertEqual(CategoryMap.normalize("film_and_tv"), "Film & TV")
        XCTAssertEqual(CategoryMap.normalize("television"), "Film & TV")
        XCTAssertEqual(CategoryMap.normalize("video games"), "Video Games")
        XCTAssertEqual(CategoryMap.normalize("food & drink"), "Food & Drink")
        XCTAssertEqual(CategoryMap.normalize("food_and_drink"), "Food & Drink")
        XCTAssertEqual(CategoryMap.normalize("mythology"), "Mythology")
        XCTAssertEqual(CategoryMap.normalize("general knowledge"), "General Knowledge")
        XCTAssertEqual(CategoryMap.normalize("general_knowledge"), "General Knowledge")
    }

    func testNormalizeCaseInsensitive() {
        XCTAssertEqual(CategoryMap.normalize("SCIENCE"), "Science & Nature")
        XCTAssertEqual(CategoryMap.normalize("History"), "History")
        XCTAssertEqual(CategoryMap.normalize("GEOGRAPHY"), "Geography")
    }

    func testNormalizeTrimsWhitespace() {
        XCTAssertEqual(CategoryMap.normalize("  science  "), "Science & Nature")
        XCTAssertEqual(CategoryMap.normalize(" history "), "History")
    }

    func testNormalizeUnknownPassesThrough() {
        XCTAssertEqual(CategoryMap.normalize("Quantum Physics"), "Quantum Physics")
        XCTAssertEqual(CategoryMap.normalize("Underwater Basket Weaving"), "Underwater Basket Weaving")
    }

    // MARK: - symbol

    func testSymbolForKnownCategories() {
        XCTAssertEqual(CategoryMap.symbol(for: "Science & Nature"), "atom")
        XCTAssertEqual(CategoryMap.symbol(for: "Technology"), "desktopcomputer")
        XCTAssertEqual(CategoryMap.symbol(for: "History"), "clock")
        XCTAssertEqual(CategoryMap.symbol(for: "Geography"), "globe.americas")
        XCTAssertEqual(CategoryMap.symbol(for: "Sports"), "sportscourt")
        XCTAssertEqual(CategoryMap.symbol(for: "Music"), "music.note")
        XCTAssertEqual(CategoryMap.symbol(for: "Film & TV"), "film")
        XCTAssertEqual(CategoryMap.symbol(for: "Food & Drink"), "fork.knife")
    }

    func testSymbolForUnknownCategoryReturnsFallback() {
        XCTAssertEqual(CategoryMap.symbol(for: "Quantum Physics"), "questionmark.circle")
        XCTAssertEqual(CategoryMap.symbol(for: ""), "questionmark.circle")
    }

    // MARK: - Consistency

    func testAllAliasesMapToValidCanonical() {
        for (_, canonical) in CategoryMap.aliasToCanonical {
            XCTAssertNotNil(CategoryMap.canonicalToSymbol[canonical],
                "Canonical '\(canonical)' has no symbol mapping")
        }
    }
}
