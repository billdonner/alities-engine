import Foundation
import AsyncHTTPClient
import NIOCore

/// Provider for category-focused trivia (via the-trivia-api.com)
final class JServiceProvider: TriviaProvider {
    let name = "jService"
    var isEnabled = true

    private let httpClient: HTTPClient
    private let baseURL = "https://the-trivia-api.com/v2/questions"
    private let categories = [
        "history", "science", "geography", "society_and_culture", "arts_and_literature",
    ]
    private var categoryIndex = 0

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchQuestions(count: Int) async throws -> [TriviaQuestion] {
        let limit = min(count, 50)
        let category = categories[categoryIndex % categories.count]
        categoryIndex += 1

        let url = "\(baseURL)?limit=\(limit)&categories=\(category)"

        var request = HTTPClientRequest(url: url)
        request.method = .GET

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 1024 * 1024)

        guard response.status == .ok else {
            throw ProviderError.networkError("Status: \(response.status)")
        }

        let data = Data(buffer: body)
        let apiQuestions = try JSONDecoder().decode([JServiceAPIQuestion].self, from: data)

        return apiQuestions.map { q in
            var allAnswers = q.incorrectAnswers
            let correctIndex = Int.random(in: 0...allAnswers.count)
            allAnswers.insert(q.correctAnswer, at: correctIndex)

            let choices = allAnswers.enumerated().map { index, text in
                TriviaChoice(text: text, isCorrect: index == correctIndex)
            }

            let categoryName = q.category
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")

            return TriviaQuestion(
                text: q.question.text, choices: choices,
                correctChoiceIndex: correctIndex, category: categoryName,
                difficulty: Difficulty.from(q.difficulty ?? "medium"),
                explanation: nil, hint: nil, source: "jService"
            )
        }
    }
}

private struct JServiceAPIQuestion: Codable {
    let id: String
    let category: String
    let correctAnswer: String
    let incorrectAnswers: [String]
    let question: JServiceQuestionText
    let difficulty: String?
}

private struct JServiceQuestionText: Codable {
    let text: String
}
