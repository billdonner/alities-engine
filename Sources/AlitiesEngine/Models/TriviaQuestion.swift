import Foundation

struct TriviaQuestion: Codable, Hashable {
    let text: String
    let choices: [TriviaChoice]
    let correctChoiceIndex: Int
    let category: String
    let difficulty: Difficulty
    let explanation: String?
    let hint: String?
    let source: String

    var correctAnswer: String {
        guard correctChoiceIndex >= 0 && correctChoiceIndex < choices.count else {
            return choices.first(where: { $0.isCorrect })?.text ?? ""
        }
        return choices[correctChoiceIndex].text
    }

    // For similarity comparison
    var normalizedText: String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
    }
}

struct TriviaChoice: Codable, Hashable {
    let text: String
    let isCorrect: Bool
}

enum Difficulty: String, Codable, CaseIterable {
    case easy
    case medium
    case hard

    static func from(_ string: String) -> Difficulty {
        switch string.lowercased() {
        case "easy": return .easy
        case "medium": return .medium
        case "hard": return .hard
        default: return .medium
        }
    }
}

struct Category: Codable {
    let id: UUID
    let name: String
    let description: String?
    let choiceCount: Int
}
