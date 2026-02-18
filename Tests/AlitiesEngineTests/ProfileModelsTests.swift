import XCTest
@testable import AlitiesEngine

final class ProfileModelsTests: XCTestCase {

    // MARK: - RawQuestion

    func testRawQuestionCodable() throws {
        let raw = RawQuestion(
            text: "What color is the sky?",
            choices: [
                RawChoice(text: "Blue", isCorrect: true),
                RawChoice(text: "Red", isCorrect: false),
            ],
            correctChoiceIndex: 0,
            category: "Science",
            difficulty: "easy",
            explanation: "Rayleigh scattering",
            hint: "Look up",
            source: "test"
        )

        let data = try JSONEncoder().encode(raw)
        let decoded = try JSONDecoder().decode(RawQuestion.self, from: data)
        XCTAssertEqual(decoded.text, raw.text)
        XCTAssertEqual(decoded.choices.count, 2)
        XCTAssertEqual(decoded.correctChoiceIndex, 0)
        XCTAssertEqual(decoded.category, "Science")
        XCTAssertEqual(decoded.difficulty, "easy")
    }

    func testRawQuestionToProfiled() {
        let raw = RawQuestion(
            text: "Capital of Japan?",
            choices: [
                RawChoice(text: "Seoul", isCorrect: false),
                RawChoice(text: "Tokyo", isCorrect: true),
                RawChoice(text: "Beijing", isCorrect: false),
            ],
            correctChoiceIndex: 1,
            category: "Geography",
            difficulty: "easy",
            explanation: "Tokyo is the capital",
            hint: "Island nation",
            source: "opentdb"
        )

        let profiled = raw.toProfiled()
        XCTAssertEqual(profiled.question, "Capital of Japan?")
        XCTAssertEqual(profiled.answers, ["Seoul", "Tokyo", "Beijing"])
        XCTAssertEqual(profiled.correctAnswer, "Tokyo")
        XCTAssertEqual(profiled.correctIndex, 1)
        XCTAssertEqual(profiled.category, "Geography")
        XCTAssertEqual(profiled.difficulty, "easy")
        XCTAssertEqual(profiled.source, "opentdb")
    }

    func testRawQuestionToProfiledFallbackCorrectAnswer() {
        // If correctChoiceIndex is out of range, falls back to isCorrect flag
        let raw = RawQuestion(
            text: "Q?",
            choices: [
                RawChoice(text: "Wrong", isCorrect: false),
                RawChoice(text: "Right", isCorrect: true),
            ],
            correctChoiceIndex: 99,
            category: "Test",
            difficulty: nil,
            explanation: nil,
            hint: nil,
            source: nil
        )

        let profiled = raw.toProfiled()
        XCTAssertEqual(profiled.correctAnswer, "Right")
    }

    // MARK: - DataLoader

    func testDataLoaderGameDataFormat() throws {
        let challenges = [
            Challenge(topic: "Science", question: "Q1?", answers: ["A", "B"], correct: "A"),
        ]
        let gameData = GameDataOutput(id: "test", generated: 1000.0, challenges: challenges)
        let data = try JSONEncoder().encode(gameData)

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_gamedata.json")
        try data.write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = try DataLoader.load(from: tmpFile)
        XCTAssertEqual(result.format, .gameData)
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertEqual(result.questions[0].question, "Q1?")
        XCTAssertNotNil(result.generated)
    }

    func testDataLoaderRawFormat() throws {
        let raw = [
            RawQuestion(
                text: "Q1?",
                choices: [RawChoice(text: "A", isCorrect: true), RawChoice(text: "B", isCorrect: false)],
                correctChoiceIndex: 0,
                category: "Test",
                difficulty: "easy",
                explanation: nil,
                hint: nil,
                source: "test"
            ),
        ]
        let data = try JSONEncoder().encode(raw)

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_raw.json")
        try data.write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = try DataLoader.load(from: tmpFile)
        XCTAssertEqual(result.format, .raw)
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertNil(result.generated)
    }

    func testDataLoaderUnrecognizedFormat() {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_bad.json")
        try? "{ \"invalid\": true }".data(using: .utf8)!.write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        XCTAssertThrowsError(try DataLoader.load(from: tmpFile)) { error in
            XCTAssertTrue(error is ProfileError)
        }
    }
}
