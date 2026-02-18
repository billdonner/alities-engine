import XCTest
@testable import AlitiesEngine

final class TopicPicMappingTests: XCTestCase {

    func testKnownCategories() {
        XCTAssertEqual(TopicPicMapping.symbol(for: "History"), "clock")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Science"), "atom")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Nature"), "leaf")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Animals"), "hare")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Geography"), "globe.americas")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Sports"), "sportscourt")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Music"), "music.note")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Movies"), "film")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Television"), "tv")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Art"), "paintbrush")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Literature"), "book")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Technology"), "desktopcomputer")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Food"), "fork.knife")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Mathematics"), "number")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Politics"), "building.columns")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Mythology"), "sparkles")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Vehicles"), "car")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Games"), "gamecontroller")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(TopicPicMapping.symbol(for: "HISTORY"), "clock")
        XCTAssertEqual(TopicPicMapping.symbol(for: "science"), "atom")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Music"), "music.note")
    }

    func testSubstringMatching() {
        XCTAssertEqual(TopicPicMapping.symbol(for: "World History"), "clock")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Computer Science"), "atom")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Pop Culture"), "star")
        XCTAssertEqual(TopicPicMapping.symbol(for: "Video Games"), "gamecontroller")
    }

    func testUnknownCategoryReturnsFallback() {
        XCTAssertEqual(TopicPicMapping.symbol(for: "Quantum Mechanics"), "questionmark.circle")
        XCTAssertEqual(TopicPicMapping.symbol(for: ""), "questionmark.circle")
        XCTAssertEqual(TopicPicMapping.symbol(for: "xyz"), "questionmark.circle")
    }

    func testPriorityOrder() {
        // "science" matches before "nature" for "Science & Nature"
        let result = TopicPicMapping.symbol(for: "Science & Nature")
        XCTAssertEqual(result, "atom") // "science" appears first in mappings
    }
}
