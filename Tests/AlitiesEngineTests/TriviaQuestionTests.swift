import XCTest
@testable import AlitiesEngine

final class TriviaQuestionTests: XCTestCase {

    // MARK: - Difficulty

    func testDifficultyFromValidStrings() {
        XCTAssertEqual(Difficulty.from("easy"), .easy)
        XCTAssertEqual(Difficulty.from("medium"), .medium)
        XCTAssertEqual(Difficulty.from("hard"), .hard)
    }

    func testDifficultyFromCaseInsensitive() {
        XCTAssertEqual(Difficulty.from("EASY"), .easy)
        XCTAssertEqual(Difficulty.from("Medium"), .medium)
        XCTAssertEqual(Difficulty.from("HARD"), .hard)
    }

    func testDifficultyFromUnknownDefaultsToMedium() {
        XCTAssertEqual(Difficulty.from("impossible"), .medium)
        XCTAssertEqual(Difficulty.from(""), .medium)
        XCTAssertEqual(Difficulty.from("expert"), .medium)
    }

    func testDifficultyCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for diff in Difficulty.allCases {
            let data = try encoder.encode(diff)
            let decoded = try decoder.decode(Difficulty.self, from: data)
            XCTAssertEqual(decoded, diff)
        }
    }

    // MARK: - TriviaQuestion

    func testCorrectAnswerFromIndex() {
        let q = makeTriviaQuestion(correctIndex: 2)
        XCTAssertEqual(q.correctAnswer, "Paris")
    }

    func testCorrectAnswerFallbackToIsCorrect() {
        // Out-of-range index falls back to isCorrect flag
        let q = makeTriviaQuestion(correctIndex: 99)
        XCTAssertEqual(q.correctAnswer, "Paris")
    }

    func testCorrectAnswerNegativeIndex() {
        let q = makeTriviaQuestion(correctIndex: -1)
        XCTAssertEqual(q.correctAnswer, "Paris")
    }

    func testNormalizedText() {
        let q = makeTriviaQuestion(text: "What is the Capital of France?!")
        XCTAssertEqual(q.normalizedText, "what is the capital of france")
    }

    func testNormalizedTextStripsSpecialChars() {
        let q = makeTriviaQuestion(text: "Who's the #1 player?")
        XCTAssertEqual(q.normalizedText, "whos the 1 player")
    }

    func testAisourceMapping() {
        XCTAssertEqual(makeTriviaQuestion(source: "AI Generated").aisource, "openai")
        XCTAssertEqual(makeTriviaQuestion(source: "Custom Source").aisource, "customsource")
    }

    func testTriviaQuestionCodable() throws {
        let q = makeTriviaQuestion()
        let data = try JSONEncoder().encode(q)
        let decoded = try JSONDecoder().decode(TriviaQuestion.self, from: data)
        XCTAssertEqual(decoded.text, q.text)
        XCTAssertEqual(decoded.category, q.category)
        XCTAssertEqual(decoded.difficulty, q.difficulty)
        XCTAssertEqual(decoded.choices.count, q.choices.count)
        XCTAssertEqual(decoded.correctChoiceIndex, q.correctChoiceIndex)
    }

    func testTriviaQuestionHashable() {
        let q1 = makeTriviaQuestion(text: "Q1")
        let q2 = makeTriviaQuestion(text: "Q2")
        let q3 = makeTriviaQuestion(text: "Q1")
        var set = Set<TriviaQuestion>()
        set.insert(q1)
        set.insert(q2)
        set.insert(q3)
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Helpers

    private func makeTriviaQuestion(
        text: String = "What is the capital of France?",
        correctIndex: Int = 2,
        source: String = "AI Generated"
    ) -> TriviaQuestion {
        TriviaQuestion(
            text: text,
            choices: [
                TriviaChoice(text: "London", isCorrect: false),
                TriviaChoice(text: "Berlin", isCorrect: false),
                TriviaChoice(text: "Paris", isCorrect: true),
                TriviaChoice(text: "Madrid", isCorrect: false),
            ],
            correctChoiceIndex: correctIndex,
            category: "Geography",
            difficulty: .medium,
            explanation: "Paris is the capital of France",
            hint: "City of Light",
            source: source
        )
    }
}
