import Foundation
import AsyncHTTPClient
import NIOCore

/// Provider that generates trivia questions using AI (OpenAI GPT)
final class AIGeneratorProvider: TriviaProvider {
    let name = "AI Generator"
    var isEnabled = true

    private let httpClient: HTTPClient
    private let apiKey: String?
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let concurrentBatches = 5

    private let categories = [
        "Science", "History", "Geography", "Sports", "Movies",
        "Music", "Literature", "Art", "Technology", "Nature",
        "Food & Drink", "Pop Culture", "Mathematics", "Politics", "Mythology"
    ]

    init(httpClient: HTTPClient, apiKey: String?) {
        self.httpClient = httpClient
        self.apiKey = apiKey
    }

    func fetchQuestions(count: Int) async throws -> [TriviaQuestion] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ProviderError.apiKeyMissing
        }

        let batches = min(concurrentBatches, max(1, count / 10))
        let shuffled = categories.shuffled()

        return try await withThrowingTaskGroup(of: [TriviaQuestion].self) { group in
            for i in 0..<batches {
                let category = shuffled[i % shuffled.count]
                let difficulty = Difficulty.allCases.randomElement() ?? .medium
                group.addTask { [httpClient, baseURL] in
                    try await Self.fetchBatch(
                        httpClient: httpClient, baseURL: baseURL,
                        apiKey: apiKey, count: 10,
                        category: category, difficulty: difficulty
                    )
                }
            }
            var all = [TriviaQuestion]()
            for try await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }
    }

    private static func fetchBatch(
        httpClient: HTTPClient, baseURL: String, apiKey: String,
        count: Int, category: String, difficulty: Difficulty
    ) async throws -> [TriviaQuestion] {
        let prompt = buildPrompt(count: count, category: category, difficulty: difficulty)

        var request = HTTPClientRequest(url: baseURL)
        request.method = .POST
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.headers.add(name: "Content-Type", value: "application/json")

        let requestBody = OpenAIRequest(
            model: "gpt-4o-mini",
            messages: [
                OpenAIMessage(role: "system", content: "You are a trivia question generator. Generate unique, factually accurate trivia questions. Always respond with valid JSON only."),
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.8, maxTokens: 2000
        )

        let bodyData = try JSONEncoder().encode(requestBody)
        request.body = .bytes(ByteBuffer(data: bodyData))

        let response = try await httpClient.execute(request, timeout: .seconds(60))
        let body = try await response.body.collect(upTo: 1024 * 1024)

        guard response.status == .ok else {
            let errorBody = String(buffer: body)
            throw ProviderError.networkError("Status: \(response.status), Body: \(errorBody)")
        }

        let data = Data(buffer: body)
        let aiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = aiResponse.choices.first?.message.content else {
            throw ProviderError.invalidResponse
        }

        return try parseAIResponse(content, category: category, difficulty: difficulty)
    }

    private static func buildPrompt(count: Int, category: String, difficulty: Difficulty) -> String {
        """
        Generate \(count) unique trivia questions about \(category) at \(difficulty.rawValue) difficulty level.

        Return a JSON array with this exact structure:
        [
          {
            "question": "The question text?",
            "correct_answer": "The correct answer",
            "incorrect_answers": ["Wrong 1", "Wrong 2", "Wrong 3"],
            "explanation": "Brief explanation of why the answer is correct",
            "hint": "A subtle clue that helps without giving away the answer"
          }
        ]

        Requirements:
        - Questions must be factually accurate
        - Each question must have exactly 3 incorrect answers
        - Incorrect answers should be plausible but clearly wrong
        - Each hint should nudge toward the correct answer without being too obvious
        - For \(difficulty.rawValue) difficulty: \(difficultyGuidance(difficulty))
        - Return ONLY the JSON array, no other text
        """
    }

    private static func difficultyGuidance(_ difficulty: Difficulty) -> String {
        switch difficulty {
        case .easy: return "Questions should be common knowledge that most people would know"
        case .medium: return "Questions should require some specific knowledge but not be obscure"
        case .hard: return "Questions should be challenging and require specialized knowledge"
        }
    }

    private static func parseAIResponse(_ content: String, category: String, difficulty: Difficulty) throws -> [TriviaQuestion] {
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let startRange = jsonString.range(of: "["),
           let endRange = jsonString.range(of: "]", options: .backwards),
           startRange.lowerBound < endRange.upperBound {
            jsonString = String(jsonString[startRange.lowerBound..<endRange.upperBound])
        }

        guard let data = jsonString.data(using: .utf8), !data.isEmpty else {
            throw ProviderError.invalidResponse
        }

        let questions = try JSONDecoder().decode([AIGeneratedQuestion].self, from: data)

        return questions.map { q in
            var allAnswers = q.incorrectAnswers
            let correctIndex = Int.random(in: 0...allAnswers.count)
            allAnswers.insert(q.correctAnswer, at: correctIndex)

            let choices = allAnswers.enumerated().map { index, text in
                TriviaChoice(text: text, isCorrect: index == correctIndex)
            }

            return TriviaQuestion(
                text: q.question, choices: choices,
                correctChoiceIndex: correctIndex, category: category,
                difficulty: difficulty, explanation: q.explanation,
                hint: q.hint, source: "AI Generated"
            )
        }
    }
}

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

private struct AIGeneratedQuestion: Codable {
    let question: String
    let correctAnswer: String
    let incorrectAnswers: [String]
    let explanation: String?
    let hint: String?
    enum CodingKeys: String, CodingKey {
        case question
        case correctAnswer = "correct_answer"
        case incorrectAnswers = "incorrect_answers"
        case explanation, hint
    }
}
