import XCTest
@testable import AlitiesEngine

final class GameDataTransformerTests: XCTestCase {

    func testTransformBasic() {
        let questions = [
            TriviaQuestion(
                text: "What is 2+2?",
                choices: [
                    TriviaChoice(text: "3", isCorrect: false),
                    TriviaChoice(text: "4", isCorrect: true),
                    TriviaChoice(text: "5", isCorrect: false),
                ],
                correctChoiceIndex: 1,
                category: "Mathematics",
                difficulty: .easy,
                explanation: "Basic arithmetic",
                hint: "Even number",
                source: "AI Generated"
            ),
        ]

        let output = GameDataTransformer.transform(questions: questions)
        XCTAssertFalse(output.id.isEmpty)
        XCTAssertGreaterThan(output.generated, 0)
        XCTAssertEqual(output.challenges.count, 1)

        let challenge = output.challenges[0]
        XCTAssertEqual(challenge.topic, "Mathematics")
        XCTAssertEqual(challenge.question, "What is 2+2?")
        XCTAssertEqual(challenge.answers, ["3", "4", "5"])
        XCTAssertEqual(challenge.correct, "4")
        XCTAssertEqual(challenge.explanation, "Basic arithmetic")
        XCTAssertEqual(challenge.hint, "Even number")
        XCTAssertEqual(challenge.aisource, "openai")
    }

    func testTransformUsesTopicPicMapping() {
        let questions = [
            TriviaQuestion(
                text: "Q?", choices: [TriviaChoice(text: "A", isCorrect: true)],
                correctChoiceIndex: 0, category: "History",
                difficulty: .medium, explanation: nil, hint: nil, source: "test"
            ),
        ]

        let output = GameDataTransformer.transform(questions: questions)
        XCTAssertEqual(output.challenges[0].pic, "clock")
    }

    func testTransformNilFieldsBecomeEmptyStrings() {
        let questions = [
            TriviaQuestion(
                text: "Q?", choices: [TriviaChoice(text: "A", isCorrect: true)],
                correctChoiceIndex: 0, category: "Test",
                difficulty: .hard, explanation: nil, hint: nil, source: "test"
            ),
        ]

        let output = GameDataTransformer.transform(questions: questions)
        XCTAssertEqual(output.challenges[0].explanation, "")
        XCTAssertEqual(output.challenges[0].hint, "")
    }

    func testTransformEmptyInput() {
        let output = GameDataTransformer.transform(questions: [])
        XCTAssertTrue(output.challenges.isEmpty)
        XCTAssertFalse(output.id.isEmpty)
    }

    func testTransformMultipleQuestions() {
        let questions = (1...5).map { i in
            TriviaQuestion(
                text: "Question \(i)?",
                choices: [TriviaChoice(text: "Answer \(i)", isCorrect: true)],
                correctChoiceIndex: 0,
                category: "Science",
                difficulty: .medium,
                explanation: nil, hint: nil,
                source: "test"
            )
        }

        let output = GameDataTransformer.transform(questions: questions)
        XCTAssertEqual(output.challenges.count, 5)
        for (i, challenge) in output.challenges.enumerated() {
            XCTAssertEqual(challenge.question, "Question \(i + 1)?")
        }
    }
}
