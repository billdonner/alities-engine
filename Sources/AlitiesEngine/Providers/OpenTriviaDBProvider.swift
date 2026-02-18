import Foundation
import AsyncHTTPClient
import NIOCore

/// Provider for Open Trivia Database (opentdb.com)
final class OpenTriviaDBProvider: TriviaProvider {
    let name = "OpenTriviaDB"
    var isEnabled = true

    private let httpClient: HTTPClient
    private let baseURL = "https://opentdb.com/api.php"

    private let categoryMapping: [Int: String] = [
        9: "General Knowledge", 10: "Entertainment: Books",
        11: "Entertainment: Film", 12: "Entertainment: Music",
        13: "Entertainment: Musicals & Theatres", 14: "Entertainment: Television",
        15: "Entertainment: Video Games", 16: "Entertainment: Board Games",
        17: "Science & Nature", 18: "Science: Computers",
        19: "Science: Mathematics", 20: "Mythology",
        21: "Sports", 22: "Geography", 23: "History", 24: "Politics",
        25: "Art", 26: "Celebrities", 27: "Animals", 28: "Vehicles",
        29: "Entertainment: Comics", 30: "Science: Gadgets",
        31: "Entertainment: Japanese Anime & Manga",
        32: "Entertainment: Cartoon & Animations"
    ]

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchQuestions(count: Int) async throws -> [TriviaQuestion] {
        let amount = min(count, 50)
        let url = "\(baseURL)?amount=\(amount)&type=multiple&encode=url3986"

        var request = HTTPClientRequest(url: url)
        request.method = .GET

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 1024 * 1024)

        guard response.status == .ok else {
            throw ProviderError.networkError("Status: \(response.status)")
        }

        let data = Data(buffer: body)
        let otdbResponse = try JSONDecoder().decode(OpenTDBResponse.self, from: data)

        guard otdbResponse.responseCode == 0 else {
            if otdbResponse.responseCode == 5 {
                throw ProviderError.rateLimited
            }
            throw ProviderError.noResults
        }

        return otdbResponse.results.map { result in
            let questionText = result.question.removingPercentEncoding ?? result.question
            let correctAnswer = result.correctAnswer.removingPercentEncoding ?? result.correctAnswer
            let incorrectAnswers = result.incorrectAnswers.map {
                $0.removingPercentEncoding ?? $0
            }
            let categoryName = (result.category.removingPercentEncoding ?? result.category)
                .replacingOccurrences(of: "Entertainment: ", with: "")
                .replacingOccurrences(of: "Science: ", with: "Science - ")

            var allAnswers = incorrectAnswers
            let correctIndex = Int.random(in: 0...allAnswers.count)
            allAnswers.insert(correctAnswer, at: correctIndex)

            let choices = allAnswers.enumerated().map { index, text in
                TriviaChoice(text: text, isCorrect: index == correctIndex)
            }

            return TriviaQuestion(
                text: questionText, choices: choices,
                correctChoiceIndex: correctIndex, category: categoryName,
                difficulty: Difficulty.from(result.difficulty),
                explanation: nil, hint: nil, source: "OpenTriviaDB"
            )
        }
    }
}

private struct OpenTDBResponse: Codable {
    let responseCode: Int
    let results: [OpenTDBQuestion]
    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case results
    }
}

private struct OpenTDBQuestion: Codable {
    let category: String
    let type: String
    let difficulty: String
    let question: String
    let correctAnswer: String
    let incorrectAnswers: [String]
    enum CodingKeys: String, CodingKey {
        case category, type, difficulty, question
        case correctAnswer = "correct_answer"
        case incorrectAnswers = "incorrect_answers"
    }
}
