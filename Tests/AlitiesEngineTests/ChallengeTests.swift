import XCTest
@testable import AlitiesEngine

final class ChallengeTests: XCTestCase {

    // MARK: - Custom Decoder

    func testDecodeFullChallenge() throws {
        let json = """
        {
            "id": "test-id",
            "topic": "Science",
            "pic": "atom",
            "question": "What is H2O?",
            "answers": ["Water", "Salt", "Sugar", "Oil"],
            "correct": "Water",
            "explanation": "H2O is the chemical formula for water",
            "hint": "You drink it",
            "aisource": "opentdb",
            "date": 123456.0
        }
        """.data(using: .utf8)!

        let challenge = try JSONDecoder().decode(Challenge.self, from: json)
        XCTAssertEqual(challenge.id, "test-id")
        XCTAssertEqual(challenge.topic, "Science")
        XCTAssertEqual(challenge.pic, "atom")
        XCTAssertEqual(challenge.question, "What is H2O?")
        XCTAssertEqual(challenge.answers, ["Water", "Salt", "Sugar", "Oil"])
        XCTAssertEqual(challenge.correct, "Water")
        XCTAssertEqual(challenge.explanation, "H2O is the chemical formula for water")
        XCTAssertEqual(challenge.hint, "You drink it")
        XCTAssertEqual(challenge.aisource, "opentdb")
        XCTAssertEqual(challenge.date, 123456.0)
    }

    func testDecodeMissingOptionalFields() throws {
        let json = """
        {
            "topic": "Science",
            "question": "What is H2O?",
            "answers": ["Water", "Salt"],
            "correct": "Water"
        }
        """.data(using: .utf8)!

        let challenge = try JSONDecoder().decode(Challenge.self, from: json)
        XCTAssertFalse(challenge.id.isEmpty)
        XCTAssertEqual(challenge.pic, "questionmark.circle")
        XCTAssertEqual(challenge.explanation, "")
        XCTAssertEqual(challenge.hint, "")
        XCTAssertEqual(challenge.aisource, "unknown")
        XCTAssertEqual(challenge.date, 0)
    }

    func testDecodeNullOptionalFields() throws {
        let json = """
        {
            "id": null,
            "topic": "History",
            "pic": null,
            "question": "When was WWII?",
            "answers": ["1939", "1945"],
            "correct": "1939",
            "explanation": null,
            "hint": null,
            "aisource": null,
            "date": null
        }
        """.data(using: .utf8)!

        let challenge = try JSONDecoder().decode(Challenge.self, from: json)
        XCTAssertFalse(challenge.id.isEmpty)
        XCTAssertEqual(challenge.pic, "questionmark.circle")
        XCTAssertEqual(challenge.explanation, "")
        XCTAssertEqual(challenge.hint, "")
        XCTAssertEqual(challenge.aisource, "unknown")
        XCTAssertEqual(challenge.date, 0)
    }

    func testChallengeRoundTrip() throws {
        let original = Challenge(
            id: "round-trip",
            topic: "Music",
            pic: "music.note",
            question: "Who wrote Bohemian Rhapsody?",
            answers: ["Queen", "Beatles", "Stones", "Zeppelin"],
            correct: "Queen",
            explanation: "Written by Freddie Mercury",
            hint: "British band",
            aisource: "opentdb",
            date: 100.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Challenge.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.topic, original.topic)
        XCTAssertEqual(decoded.question, original.question)
        XCTAssertEqual(decoded.correct, original.correct)
    }

    // MARK: - GameDataOutput

    func testGameDataOutputRoundTrip() throws {
        let challenges = [
            Challenge(topic: "Science", question: "Q1?", answers: ["A", "B"], correct: "A"),
            Challenge(topic: "History", question: "Q2?", answers: ["C", "D"], correct: "C"),
        ]
        let output = GameDataOutput(id: "test", generated: 1000.0, challenges: challenges)

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(GameDataOutput.self, from: data)
        XCTAssertEqual(decoded.id, "test")
        XCTAssertEqual(decoded.generated, 1000.0)
        XCTAssertEqual(decoded.challenges.count, 2)
        XCTAssertEqual(decoded.challenges[0].topic, "Science")
        XCTAssertEqual(decoded.challenges[1].topic, "History")
    }

    // MARK: - toProfiled

    func testChallengeToProfiled() {
        let challenge = Challenge(
            topic: "Geography",
            pic: "globe",
            question: "Capital of France?",
            answers: ["London", "Paris", "Berlin"],
            correct: "Paris",
            explanation: "It's Paris",
            hint: "City of Light",
            aisource: "opentdb"
        )

        let profiled = challenge.toProfiled()
        XCTAssertEqual(profiled.question, "Capital of France?")
        XCTAssertEqual(profiled.answers, ["London", "Paris", "Berlin"])
        XCTAssertEqual(profiled.correctAnswer, "Paris")
        XCTAssertEqual(profiled.correctIndex, 1)
        XCTAssertEqual(profiled.category, "Geography")
        XCTAssertEqual(profiled.explanation, "It's Paris")
        XCTAssertEqual(profiled.hint, "City of Light")
        XCTAssertEqual(profiled.source, "opentdb")
    }

    func testChallengeToProfiledEmptyFieldsBecomeNil() {
        let challenge = Challenge(
            topic: "Science",
            question: "Q?",
            answers: ["A"],
            correct: "A",
            explanation: "",
            hint: "",
            aisource: "unknown"
        )

        let profiled = challenge.toProfiled()
        XCTAssertNil(profiled.explanation)
        XCTAssertNil(profiled.hint)
        XCTAssertNil(profiled.source)
    }
}
