import Foundation
import AsyncHTTPClient
import NIOCore

/// Provider for The Trivia API (the-trivia-api.com)
final class TheTriviaAPIProvider: TriviaProvider {
    let name = "TheTriviaAPI"
    var isEnabled = true

    private let httpClient: HTTPClient
    private let baseURL = "https://the-trivia-api.com/v2/questions"

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchQuestions(count: Int) async throws -> [TriviaQuestion] {
        let limit = min(count, 50)
        let url = "\(baseURL)?limit=\(limit)"

        var request = HTTPClientRequest(url: url)
        request.method = .GET

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 1024 * 1024)

        guard response.status == .ok else {
            throw ProviderError.networkError("Status: \(response.status)")
        }

        let data = Data(buffer: body)
        let apiQuestions = try JSONDecoder().decode([TriviaAPIQuestion].self, from: data)

        return apiQuestions.map { q in
            var allAnswers = q.incorrectAnswers
            let correctIndex = Int.random(in: 0...allAnswers.count)
            allAnswers.insert(q.correctAnswer, at: correctIndex)

            let choices = allAnswers.enumerated().map { index, text in
                TriviaChoice(text: text, isCorrect: index == correctIndex)
            }

            return TriviaQuestion(
                text: q.question.text, choices: choices,
                correctChoiceIndex: correctIndex, category: q.category.capitalized,
                difficulty: Difficulty.from(q.difficulty ?? "medium"),
                explanation: nil, hint: nil, source: "TheTriviaAPI"
            )
        }
    }
}

private struct TriviaAPIQuestion: Codable {
    let id: String
    let category: String
    let correctAnswer: String
    let incorrectAnswers: [String]
    let question: TriviaAPIQuestionText
    let tags: [String]?
    let type: String?
    let difficulty: String?
    let regions: [String]?
    let isNiche: Bool?
}

private struct TriviaAPIQuestionText: Codable {
    let text: String
}
