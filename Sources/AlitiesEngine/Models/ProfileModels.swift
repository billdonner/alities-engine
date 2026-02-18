import Foundation

// MARK: - Raw Format (flat array of questions)

struct RawQuestion: Codable {
    let text: String
    let choices: [RawChoice]
    let correctChoiceIndex: Int
    let category: String
    let difficulty: String?
    let explanation: String?
    let hint: String?
    let source: String?
}

struct RawChoice: Codable {
    let text: String
    let isCorrect: Bool
}

// MARK: - Unified format for reporting

struct ProfiledQuestion {
    let question: String
    let answers: [String]
    let correctAnswer: String
    let correctIndex: Int
    let category: String
    let difficulty: String?
    let explanation: String?
    let hint: String?
    let source: String?
}

// MARK: - Conversion

extension Challenge {
    func toProfiled() -> ProfiledQuestion {
        let idx = answers.firstIndex(of: correct) ?? 0
        return ProfiledQuestion(
            question: question,
            answers: answers,
            correctAnswer: correct,
            correctIndex: idx,
            category: topic,
            difficulty: nil,
            explanation: explanation.isEmpty ? nil : explanation,
            hint: hint.isEmpty ? nil : hint,
            source: aisource == "unknown" ? nil : aisource
        )
    }
}

extension RawQuestion {
    func toProfiled() -> ProfiledQuestion {
        let answerTexts = choices.map(\.text)
        let correctText = choices.indices.contains(correctChoiceIndex)
            ? choices[correctChoiceIndex].text
            : (choices.first(where: \.isCorrect)?.text ?? "")
        return ProfiledQuestion(
            question: text,
            answers: answerTexts,
            correctAnswer: correctText,
            correctIndex: correctChoiceIndex,
            category: category,
            difficulty: difficulty,
            explanation: explanation,
            hint: hint,
            source: source
        )
    }
}

// MARK: - Format detection

enum DataFormat {
    case gameData
    case raw
}

struct DataLoader {
    static func load(from url: URL) throws -> (questions: [ProfiledQuestion], format: DataFormat, generated: Date?) {
        let data = try Data(contentsOf: url)

        // Try game data format first
        if let gameData = try? JSONDecoder().decode(GameDataOutput.self, from: data) {
            let questions = gameData.challenges.map { $0.toProfiled() }
            let date = Date(timeIntervalSinceReferenceDate: gameData.generated)
            return (questions, .gameData, date)
        }

        // Try raw format
        if let rawQuestions = try? JSONDecoder().decode([RawQuestion].self, from: data) {
            let questions = rawQuestions.map { $0.toProfiled() }
            return (questions, .raw, nil)
        }

        throw ProfileError.unrecognizedFormat
    }
}

enum ProfileError: Error, CustomStringConvertible {
    case unrecognizedFormat
    case fileNotFound(String)

    var description: String {
        switch self {
        case .unrecognizedFormat:
            return "Unrecognized JSON format. Expected game data (with id/generated/challenges) or raw question array."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
